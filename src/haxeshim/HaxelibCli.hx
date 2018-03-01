package haxeshim;

using tink.CoreApi;

class HaxelibCli {
  static function exit<T>(o:Outcome<T, Error>)
    switch o {
      case Success(_): Sys.exit(0);
      case Failure(e): Exec.die(e.code, e.message);
    };

  static function main() {
    Neko.setEnv();
    
    var scope = Scope.seek(),
        args = Sys.args();
    
    var installation = scope.haxeInstallation;

    function callHaxelib()
      Sys.exit(switch Exec.sync(installation.haxelib, Sys.getCwd(), Sys.args(), installation.env()) {
        case Success(c):
          c;
        case Failure(e):
          e.code;
      });    
    switch args[0] {
      case 'run-dir':
        if (args.length < 3)
          Exec.die(402, 'Not enough arguments. Syntax is `haxelib run-dir <name> <path> <...args>');
        args = args.slice(1).map(scope.interpolate);
        var name = args.shift();
        var path = args.shift();
        Fs.get('$path/haxelib.json')
          .next(
            function (s) 
              return 
                try Success((haxe.Json.parse(s).mainClass :Null<String>))
                catch (e:Dynamic) Failure(Error.withData('failed to parse haxelib.json', e))
          )
          .next(
            function (mainClass) return switch mainClass {
              case null: 
                Exec.sync('neko', path, ['$path/run.n'].concat(args).concat([Sys.getCwd()]), { HAXELIB_RUN: '1', HAXELIB_LIBNAME: name });
              case v: 
                new Error('mainClass support not implemented yet');
            }
          ).handle(function (o) switch o {//this is a little awkward
            case Success(code): Sys.exit(code);
            case Failure(e): Exec.die(e.code, e.message);
          });
      case 'run':
        scope.getLibCommand(args.slice(1))
          .handle(function (o) switch o {
            case Success(cmd):
              exit(cmd());
            case Failure(e):
              callHaxelib();
          });
      default:
        callHaxelib();
    }
  }
  
}
