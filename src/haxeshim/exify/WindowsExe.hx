package haxeshim.exify;

import haxe.io.Bytes;
import haxeshim.sys.Os;

using sys.io.File;
using sys.FileSystem;
using haxe.io.Path;
using StringTools;

/**
 * On Windows, CreateProcess looks in the application directory before PATH.
 * The Haxe compiler (`haxe.exe`) therefore finds the stock `haxelib.exe` next to
 * itself and never reaches the npm/lix shim — scoped libs then look "not installed".
 *
 * We rename the bundled binary to `haxelib-bundled.exe` (kept for Mixed-mode
 * fallback) and write an exify shim as `haxelib.exe` that launches haxelibshim.js.
 */
class WindowsExe {
  static final BUNDLED_NAME = 'haxelib-bundled.exe';
  static final PLACEHOLDER = Bytes.ofString("abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789");
  static final EXIFIER = haxe.crypto.Base64.decode(Embed.binary());
  static final OFFSET = {
    var ret = -1;
    for (i in 0...EXIFIER.length - PLACEHOLDER.length)
      if (EXIFIER.sub(i, PLACEHOLDER.length).compare(PLACEHOLDER) == 0) {
        ret = i;
        break;
      }
    if (ret == -1)
      throw 'no exify placeholder found';
    ret;
  };

  static public function makeExe(call:String):Bytes {
    final callBytes = Bytes.ofString(call);
    final replacer = Bytes.alloc(PLACEHOLDER.length);
    replacer.fill(0, replacer.length, 0);
    replacer.blit(0, callBytes, 0, callBytes.length);

    final buf = Bytes.alloc(EXIFIER.length);
    buf.blit(0, EXIFIER, 0, buf.length);
    buf.blit(OFFSET, replacer, 0, replacer.length);
    return buf;
  }

  /**
   * @return path to the stock/bundled haxelib binary for resolveThroughHaxelib,
   *         or the normal `haxelib.exe` path when no wrapping is needed.
   */
  static public function ensureVersionHaxelib(versionPath:String):String {
    final normal = '$versionPath/haxelib${Os.EXECUTABLE_EXTENSION}';
    if (!Os.IS_WINDOWS)
      return normal;

    final bundled = '$versionPath/$BUNDLED_NAME';
    if (bundled.exists())
      return bundled;

    if (!normal.exists())
      return normal;

    // Exify shims are tiny; stock haxelib.exe is hundreds of KB.
    if (normal.stat().size < 10000)
      return normal;

    #if nodejs
    final shimJs = Path.join([js.Node.__dirname, 'haxelibshim.js']).replace('\\', '/');
    if (!shimJs.exists())
      return normal;

    try {
      normal.rename(bundled);
      normal.saveBytes(makeExe('node "$shimJs"'));
      #if nodejs
      js.Node.console.error('[haxeshim] Windows: wrapped ' + normal + ' to invoke scoped haxelibshim (stock kept as ' + BUNDLED_NAME + ')');
      #end
      return bundled;
    } catch (e:Dynamic) {
      if (bundled.exists() && !normal.exists())
        try bundled.rename(normal) catch (_:Dynamic) {}
      return normal.exists() ? normal : bundled;
    }
    #else
    return normal;
    #end
  }
}
