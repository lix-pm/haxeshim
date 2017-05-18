package haxeshim;

class HaxelibCli {

  static function main() {
    var installation = Scope.seek().haxeInstallation;
    var env = installation.env();
    trace(env);
    if (Os.IS_WINDOWS)
      Sys.putEnv('PATH', env['PATH']);
      
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