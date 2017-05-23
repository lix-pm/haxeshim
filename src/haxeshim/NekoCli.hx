package haxeshim;

class NekoCli {

  static function main() {
    
    Neko.setEnv();

    var binary = 
      if (Os.IS_WINDOWS) 'neko.exe';
      else 'neko';
      
    Sys.exit(
      switch Exec.sync(Neko.PATH + '/$binary', Sys.getCwd(), Sys.args(), Neko.ENV) {
        case Success(c):
          c;
        case Failure(e):
          e.code;
      }
    );
  }
  
}