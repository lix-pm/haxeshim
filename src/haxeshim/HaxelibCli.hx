package haxeshim;

using StringTools;

class HaxelibCli {

  static function main() {
    Neko.setEnv();
    var installation = Scope.seek().haxeInstallation;
      
    Sys.exit(
      switch Exec.sync(installation.haxelib, Sys.getCwd(), Sys.args(), installation.env()) {
        case Success(c):
          c;
        case Failure(e):
          e.code;
      }
    );
  }
  
}
