package haxeshim;

using tink.CoreApi;

class HaxeCli {
  static public function defaultScope()
    return Scope.seek({
      startLookingIn: Sys.getCwd(),
      haxeshimRoot: switch Sys.getEnv('HAXESHIM_ROOT') {
        case null | '':
          Sys.getEnv('APPDATA') + '/haxe';
        case v:
          v;
      }
    });
    
  static function die(code, reason):Dynamic {
    Sys.stderr().writeString(reason);
    Sys.exit(code);    
    return throw 'unreachable';
  }
  static function gracefully<T>(f:Void->T) 
    return 
      try f()
      catch (e:Error) 
        die(e.code, e.message)
      catch (e:String) 
        die(500, e);
    
  static function main() 
    switch Sys.args() {
      case ['--wait', Std.parseInt(_) => port]:
        new CompilerServer(port, defaultScope());
      case args:
        
        var scope = gracefully(defaultScope);
        
        switch [args.indexOf('--connect'), args.indexOf('--haxe-version')] {
          case [ -1, -1]:
          case [ _, -1]: 
            /**
             * TODO: in this case there are two possible optimizations:
             * 
             * 1. Connect to the server directly (protocol seems easy enough)
             * 2. Leave the version determination to the server side, because it is already running
             */
            args.push('--haxe-version');
            args.push(scope.haxeInstallation.version);
          default:
        }
        
        Sys.exit(gracefully(Exec.sync(scope.haxeInstallation.compiler, scope.cwd, gracefully(scope.resolve.bind(args)), scope.haxeInstallation.env()).sure));
    }
  
  
}

