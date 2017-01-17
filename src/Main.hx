package;
import haxeshim.Exec;


class Main {
	
	static function main() {
		
    var scope = haxeshim.Scope.seek({
      startLookingIn: Sys.getCwd(),
      haxeshimRoot: switch Sys.getEnv('HAXESHIM_ROOT') {
        case null | '':
          Sys.getEnv('APPDATA') + '/haxe';
        case v:
          v;
      }
    });
    
    //trace(scope.resolve(['-lib', 'bar', '-lib', 'tink_core']));
    
    Exec.sync(scope.haxeInstallation.compiler, scope.cwd, scope.resolve(['-lib', 'bar', '-lib', 'tink_core', '-main', 'Test', '--interp']), scope.haxeInstallation.env());
    //scope.runHaxe(['-lib', 'bar', '-lib', 'tink_core']);
    //trace(scope.workingDir);
    
    //new HaxeArgs(scope.workingDir, Scoped).resolve([]);
	}
  
  
	
} 