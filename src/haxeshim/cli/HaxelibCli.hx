package haxeshim.cli;

using tink.CoreApi;
using haxe.io.Path;
using StringTools;
using sys.FileSystem;

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

  function callHaxelib(args:Array<String>)
    exitWithCode(Exec.sync(installation.haxelib, Sys.getCwd(), args, installation.env()));

  public function new(scope) {
    Neko.setEnv();//TODO: this is an awkward place to put this
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

    var resolved = Exec.gracefully(scope.resolve.bind(args)),
        i = 0;

    while(i < resolved.length) {
      switch resolved[i] {
        case '-lib':
          switch resolved[++i] {
            case Args.getNdll(_) => Some(v):
              out.push('-L $v');
            case wtf:
              Sys.println('Unexpected -lib $wtf returned from haxelib path ${libs.join(' ')}');
              Sys.exit(500);
          }
        case '--cwd': i++; // skip
        case '-cp': out.push(resolved[++i].addTrailingSlash());
        case v if (v.charCodeAt(0) == '-'.code): out.push('$v ${resolved[++i]}');
        default:
      }
      i++;
    }

    Sys.print(out.join('\n'));
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
              Sys.println('Unable to find haxelib.json for $lib at ${resolved[i + 1]}');
              Sys.exit(500);
            }
          case _:
        }
      }
      
      Sys.println('Unable to resolve libpath for $lib');
      Sys.exit(500);
      throw 'unreachable';
    }
    
    Sys.println(libs.map(resolve).join('\n'));
  }

  public function run(args:Array<String>)
    scope.getLibCommand(args)
      .handle(function (o) switch o {
        case Success(cmd):
          exit(cmd());
        case Failure(e):
          callHaxelib(['run'].concat(args));
      });

  public function runDir(name:String, path:String, args:Array<String>) {
    Fs.get('$path/haxelib.json')
      .next(
        function (s)
          try return Success((haxe.Json.parse(s).main :Null<String>))
          catch (e:Dynamic) return Failure(Error.withData('failed to parse haxelib.json', e))
      )
      .next(
        function (main) return switch main {
          case null:
            Exec.sync('neko', path, ['$path/run.n'].concat(args).concat([Sys.getCwd().removeTrailingSlashes() + '/']), { HAXELIB_RUN: '1', HAXELIB_LIBNAME: name });
          case v:
            switch installation.compiler {
              case haxe if (haxe.exists()):
                Exec.sync(haxe, path, 
                  ['--run', main].concat(args).concat([Sys.getCwd().removeTrailingSlashes() + '/']), 
                  { HAXELIB_RUN: '1', HAXELIB_LIBNAME: name }
                );
              case path:
                Exec.die(404, 'haxe compiler not found at the expected location "$path"');
            }
        }
      ).handle(exitWithCode);
  }

  public function dispatch(args:Array<String>) {
    switch args[0] {
      case 'run-dir':
        if (args.length < 3)
          Exec.die(402, 'Not enough arguments. Syntax is `haxelib run-dir <name> <path> <...args>');
        args = args.slice(1).map(scope.interpolate.bind());
        var name = args.shift();
        var path = args.shift();
        runDir(name, path, args);
      case 'run':
        run(args.slice(1));
      case 'path':
        path(args.slice(1));
      case 'libpath':
        libpath(args.slice(1));
      default:
        callHaxelib(args);
    }
  }

  static function main() {
    #if nodejs
    js.Node.process.stdout.on('error', function () {});//hxcpp apparently closes stdout and then writing to it fails
    #end
    new HaxelibCli(Scope.seek()).dispatch(Sys.args());
  }

}
