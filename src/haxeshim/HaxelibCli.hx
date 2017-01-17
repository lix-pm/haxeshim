package haxeshim;

using tink.CoreApi;

class HaxelibCli {

  static function main() {
    var installation = HaxeCli.defaultScope().haxeInstallation;
    
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