package haxeshim.exify;

import haxe.Resource;
import js.node.ChildProcess;
import js.Node.*;
import haxe.io.*;

using sys.io.File;
using sys.FileSystem;
using haxe.io.Path;
using StringTools;

class PostInstall {

  static var placeholder = Bytes.ofString("abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789abcdefghijklmnopqrstufvwxyzABCDEFGHIJKLMNOPQRSTUFVWXYZ0123456789");
  static var exifier = haxe.crypto.Base64.decode(haxeshim.exify.Embed.binary());
  static var offset = {
    var ret = -1;
    for (i in 0...exifier.length - placeholder.length)
      if (exifier.sub(i, placeholder.length).compare(placeholder) == 0) {
        ret = i;
        break;
      }
    if (ret == -1)
      throw 'no placeholder found';
    ret;
  }

  static function makeExe(call:String) {
    var call = Bytes.ofString(call),
        replacer = Bytes.alloc(placeholder.length);

    replacer.fill(0, replacer.length, 0);
    replacer.blit(0, call, 0, call.length);

    var buf = Bytes.alloc(exifier.length);

    buf.blit(0, exifier, 0, buf.length);
    buf.blit(offset, replacer, 0, replacer.length);

    return buf;
  }

  static function exify(dir, source) {

    for (name in ['haxe', 'haxelib', 'neko']) {
      var exe = '$dir/$name.exe';
      try {
        exe.saveBytes(makeExe('node "$source/${name}shim.js"'));
        var code = try Sys.command(exe, [if (name == 'haxelib') 'version' else '-version']) catch (e:Dynamic) 500;
        if (code != 0) {
          Sys.println('Warning: Windows will not allow executing shimmed $name.exe. It will be removed.');
          try exe.deleteFile()
          catch (e:Dynamic) {
            Sys.println('ERROR: Removing $name.exe has also failed.');
            Sys.println('At this point, things are probably badly broken.');
            Sys.println('Please open $dir and see if you can clean it up.');
            Sys.println('Good luck ...');
            Sys.exit(500);
          }
          break;
        }
      }
      catch (e:Dynamic) {
        Sys.println('failed to shim $name');
        Sys.exit(500);
      }
    }

  }

  static var GLOBAL:Bool = !!(untyped process.env["npm_config_global"]); //wohooo \o/

  static var WINDOWS = Sys.systemName() == 'Windows';

  static function which(name) {
    return
      Std.string(ChildProcess.spawnSync(if (WINDOWS) 'where' else 'which', [name]).stdout)
        .split('\n').map(StringTools.trim).filter(f -> f != '');
  }

  static function main()
    if (GLOBAL) {

      if (WINDOWS) {
        function isNpm(dir)
          return '$dir/lix.cmd'.exists();

        var found = [];
        for (p in which('haxe'))
          switch new Path(p) {
            case { ext: 'cmd', dir: npm } if (isNpm(npm)):

              exify(npm, js.Node.__dirname.replace('\\', '/'));

              if (found.length > 0 && '$npm/lix.cmd'.exists())
                Sys.println(['Warning: the haxe executable bundled with lix is shadowed by:'].concat(found).join('\n  '));

              break;

            case { dir: other } if (!isNpm(other)):
              found.push(p);
            default:
          }
      }

  }
}