package haxeshim.exify;

#if macro
import haxe.macro.Context;
using haxe.io.Path;
#end

class Embed {
  macro static public function binary() {
    var file = Context.getPosInfos((macro null).pos).file.directory() + '/exify';
    return macro $v{haxe.crypto.Base64.encode(sys.io.File.getBytes(file))};
  }
}