package haxeshim;

class NekoCli {

  static function main() {
    var installation = Scope.seek().haxeInstallation;
    var env = installation.env();
    
    if (Os.IS_WINDOWS)
      Sys.putEnv('PATH', env['PATH']);
    var binary = 
      if (Os.IS_WINDOWS) 'neko.exe';
      else 'neko';
    Sys.exit(
      switch Exec.sync(installation.nekoPath + '/$binary', Sys.getCwd(), Sys.args(), env) {
        case Success(c):
          c;
        case Failure(e):
          e.code;
      }
    );
  }
  
}