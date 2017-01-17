package;

import haxeshim.HaxeArgs;
import haxeshim.Scope;

class Main {
	
	static function main() {
		
    var scope = Scope.seek({
      startLookingIn: Sys.getCwd(),
      homeDir: switch Sys.getEnv('HAXESHIM_ROOT') {
        case null | '':
          Sys.getEnv('APPDATA') + '/haxe';
        case v:
          v;
      }
    });
    
    //trace(scope.resolve(['-lib', 'bar', '-lib', 'tink_core']));
    scope.runHaxe(['-lib', 'bar', '-lib', 'tink_core']);
    //trace(scope.workingDir);
    
    //new HaxeArgs(scope.workingDir, Scoped).resolve([]);
	}
  
  
	
} 