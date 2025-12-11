package haxeshim.cli;

import haxeshim.sys.*;

class NekoCli {

  static function main() {
    final scope = Exec.gracefully(() -> haxeshim.scope.Scope.seek());
    final neko = scope.haxeInstallation.neko;
    
    switch Exec.sync(neko.executable, Sys.getCwd(), Sys.args(), neko.env) {
      case Success(c):
        Sys.exit(c);
      case Failure(e):
        Exec.die(e.code, e.message);
    }
  }

}