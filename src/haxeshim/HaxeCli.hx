package haxeshim;

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
    
  static function main() 
    switch Sys.args() {
      case ['--wait', Std.parseInt(_) => port]:
        new CompilerServer(port, defaultScope());
      case args:
        
        var scope = 
          try defaultScope()
          catch (e:String) {
            Sys.stderr().writeString(e);
            Sys.exit(500);
            null;
          }
        
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
        
        Exec.sync(scope.haxeInstallation.compiler, scope.cwd, scope.resolve(args), scope.haxeInstallation.env());
    }
  
  
}

