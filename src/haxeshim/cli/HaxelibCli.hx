package haxeshim.cli;

import haxeshim.scope.*;
import haxeshim.sys.*;

using haxe.io.Path;
using sys.FileSystem;

typedef ParsedHaxelibArgs = {
  var commandArgs:Array<String>;
  var cwd:Null<String>;
}

class HaxelibCli {
  static function exit<T>(o:Outcome<T, Error>)
    switch o {
      case Success(_): Sys.exit(0);
      case Failure(e): Exec.die(e.code, e.message);
    };

  static function exitWithCode(o:Outcome<Int, Error>)
    switch o {
      case Success(code): Sys.exit(code);
      case Failure(e): Exec.die(e.code, e.message);
    };

  var scope:Scope;
  var installation:HaxeInstallation;

  function callHaxelib(args:Array<String>, ?env:Env)
    exitWithCode(Exec.sync(installation.haxelib, Sys.getCwd(), args, switch env {
      case null: installation.env;
      case v: v.mergeInto(installation.env);
    }));

  public function new(scope) {
    this.scope = scope;
    this.installation = scope.haxeInstallation;
  }

  public function path(libs:Array<String>) {
    var args = [],
        out = [];

    for (lib in libs)
      switch Args.getNdll(lib) {
        case Some(v):
          out.push('-L $v');
        default:
          args.push('-lib');
          args.push(lib.split(':')[0]);
      }

    var resolved = Exec.gracefully(() -> scope.resolve(args)),
        i = 0;

    while(i < resolved.length) {
      switch resolved[i] {
        case '-lib':
          switch resolved[++i] {
            case Args.getNdll(_) => Some(v):
              out.push('-L $v');
            case wtf:
              Out.println('Unexpected -lib $wtf returned from haxelib path ${libs.join(' ')}');
              Sys.exit(500);
          }
        case '-cwd' | '--cwd': i++; // skip value
        case '-cp': out.push(resolved[++i].addTrailingSlash());
        case v if (v.charCodeAt(0) == '-'.code): out.push('$v ${resolved[++i]}');
        default:
      }
      i++;
    }

    Out.print(out.join('\n'));
    Sys.exit(0);
  }
  
  public function libpath(libs:Array<String>) {
    // resolving libpath is a bit tricky because we don't really store the lib root folder anywhere
    // so we have to resolve it by finding the haxelib.json, starting from the lib's classpath and goes up
    function resolve(lib:String) {
      final resolved = scope.resolve(['-lib', lib]);
      for(i in 0...resolved.length) {
        switch resolved[i] {
          case '-cp':
            var path = resolved[i + 1];
            if(path.contains('/$lib/')) {
              do {
                if(FileSystem.exists(Path.join([path, 'haxelib.json'])))
                  return path.addTrailingSlash();
              } while((path = Path.directory(path)) != '');
              Out.println('Unable to find haxelib.json for $lib at ${resolved[i + 1]}');
              Sys.exit(500);
            }
          case _:
        }
      }
      
      Out.println('Unable to resolve libpath for $lib');
      Sys.exit(500);
      throw 'unreachable';
    }
    
    Out.println(libs.map(resolve).join('\n'));
  }

  public function run(args:Array<String>, rawArgs:Array<String>)
    scope.getLibCommand(args)
      .handle(function (o) switch o {
        case Success(cmd):
          exit(cmd());
        case Failure(e):
          callHaxelib(rawArgs, scope.runEnv);// stock haxelib runs the script with the library's directory as cwd
      });

  function runWithHaxe(name:String, path:String, main:String, args:Array<String>, ?env:Env):Outcome<Int, Error> {
    return switch installation.compiler {
      case haxe if (haxe.exists()):
        Exec.sync(haxe, path,
          scope.resolve(['-lib', name])
            .concat(['--run', main])
            .concat(args)
            .concat([Sys.getCwd().removeTrailingSlashes() + '/']),
          env
        );
      case compilerPath:
        Exec.die(404, 'haxe compiler not found at the expected location "$compilerPath"');
    }
  }

  public function runDir(name:String, path:String, args:Array<String>) {
    final env = scope.runEnv.mergeInto({ HAXELIB_RUN: '1', HAXELIB_RUN_NAME: name, HAXELIB_LIBNAME: name });
    Fs.get('$path/haxelib.json')
      .next(
        function (s)
          try return Success((haxe.Json.parse(s).main :Null<String>))
          catch (e:Dynamic) return Failure(Error.withData('failed to parse haxelib.json', e))
      )
      .next(
        function (main) return switch main {
          case null:
            if ('$path/run.n'.exists())
              Exec.sync('neko', path, ['$path/run.n'].concat(args).concat([Sys.getCwd().removeTrailingSlashes() + '/']), env);
            else if ('$path/Run.hx'.exists())
              runWithHaxe(name, path, 'Run', args, env);
            else
              return Failure(new Error(404, 'Library $name does not have a run script'));
          case _:
            runWithHaxe(name, path, main, args, env);
        }
      ).handle(exitWithCode);
  }

  public function dispatch(commandArgs:Array<String>, rawArgs:Array<String>) {
    switch commandArgs[0] {
      case 'run-dir':
        if (commandArgs.length < 3)
          Exec.die(402, 'Not enough arguments. Syntax is `haxelib run-dir <name> <path> <...args>');
        var args = commandArgs.slice(1).map(v -> scope.interpolate(v));
        var name = args.shift();
        var path = args.shift();
        runDir(name, path, args);
      case 'run':
        run(commandArgs.slice(1), rawArgs);
      case 'path':
        path(commandArgs.slice(1));
      case 'libpath':
        libpath(commandArgs.slice(1));
      default:
        callHaxelib(rawArgs);
    }
  }

  static function parseGlobalPrefix(args:Array<String>):ParsedHaxelibArgs {
    var i = 0;
    var cwd:Null<String> = null;
    while (i < args.length)
      switch args[i] {
        case '-cwd' | '--cwd':
          if (++i >= args.length)
            Exec.die(500, '${args[i - 1]} requires argument');
          cwd = args[i++];
        case '--global':
          i++;
        case arg if (arg.charCodeAt(0) == '-'.code):
          Exec.die(500, 'Global flag \'$arg\' is not supported by haxeshim; please report a bug');
        default:
          return { commandArgs: args.slice(i), cwd: cwd };
      }
    return { commandArgs: [], cwd: cwd };
  }

  static function main() {
    // note: write errors on stdout - e.g. because whoever spawned us closed it - are swallowed by `Out`,
    // which also never touches `process.stdout`, because that would put the file descriptor into
    // non-blocking mode when stdout happens to be a pipe
    exec();
  }

  static public function exec(?scope:Scope, ?args:Array<String>) {
    var raw = args ?? Sys.args();
    var parsed = parseGlobalPrefix(raw);
    if (parsed.cwd != null) {
      try Sys.setCwd(parsed.cwd)
      catch (e:Dynamic)
        Exec.die(500, 'Invalid directory: ${parsed.cwd}');
      Scope.dropInheritedScope();
    }
    scope = scope ?? Scope.seek();
    new HaxelibCli(scope).dispatch(parsed.commandArgs, raw);
  }

}
