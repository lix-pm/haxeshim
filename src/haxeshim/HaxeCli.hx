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
        var scope = defaultScope();
        Exec.sync(scope.haxeInstallation.compiler, scope.cwd, scope.resolve(args), scope.haxeInstallation.env());
    }
  
  
}

