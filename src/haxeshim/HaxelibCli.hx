package haxeshim;

using StringTools;

class HaxelibCli {

  static function main() {
    var installation = Scope.seek().haxeInstallation;
    var env = installation.env();

    for (name in env.keys())
      if (!name.startsWith('HAXE')) {
        trace([name, env[name]]);
        Sys.putEnv(name, env[name]);
      }
      
    // if (Os.IS_WINDOWS)
      // Sys.putEnv('PATH', env['PATH']);
      
    Sys.exit(
      switch Exec.sync(installation.haxelib, Sys.getCwd(), Sys.args(), env) {
        case Success(c):
          c;
        case Failure(e):
          e.code;
      }
    );
  }
  
}