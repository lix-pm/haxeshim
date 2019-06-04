package haxeshim;

using tink.CoreApi;
using haxe.io.Path;

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
    var args = [];
    for(lib in libs) {
      args.push('-lib');
      args.push(lib.split(':')[0]);
    }
    var resolved = Exec.gracefully(scope.resolve.bind(args));
    var out = [];
    var i = 0;
    while(i < resolved.length) {
      var v = resolved[i];
      if(v == '--cwd') i++; // skip
      else if(v == '-cp') out.push(resolved[++i].addTrailingSlash());
      else if(v.charCodeAt(0) == '-'.code) out.push('$v ${resolved[++i]}');
      i++;
    }
    Sys.println(out.join('\n'));
    Sys.exit(0);
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
          try return Success((haxe.Json.parse(s).mainClass :Null<String>))
          catch (e:Dynamic) return Failure(Error.withData('failed to parse haxelib.json', e))
      )
      .next(
        function (mainClass) return switch mainClass {
          case null: 
            Exec.sync('neko', path, ['$path/run.n'].concat(args).concat([Sys.getCwd().removeTrailingSlashes() + '/']), { HAXELIB_RUN: '1', HAXELIB_LIBNAME: name });
          case v: 
            new Error('mainClass support not implemented yet');
        }
      ).handle(exitWithCode);
  }

  public function dispatch(args:Array<String>) {
    switch args[0] {
      case 'run-dir':
        if (args.length < 3)
          Exec.die(402, 'Not enough arguments. Syntax is `haxelib run-dir <name> <path> <...args>');
        args = args.slice(1).map(scope.interpolate);
        var name = args.shift();
        var path = args.shift();
        runDir(name, path, args);
      case 'run':
        run(args.slice(1));
      case 'path':
        path(args.slice(1));
      default:
        callHaxelib(args);
    }
  }

  static function main() 
    new HaxelibCli(Scope.seek()).dispatch(Sys.args());
  
}
