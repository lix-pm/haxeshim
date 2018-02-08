package haxeshim;

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

  static function exify(dir, source, mayFail) {    
    
    for (name in ['haxe', 'haxelib', 'neko']) {
      var exe = '$dir/$name.exe';
      if (exe.exists() && !'$exe.bak'.exists())
        exe.rename('$exe.bak');
      try {
        exe.saveBytes(makeExe('node "$source/${name}shim.js"'));
      }
      catch (e:Dynamic) 
        if (!mayFail(name)) {
          Sys.println('failed to shim $name');
          Sys.exit(500);
        }
    }

  }
  
  static var GLOBAL:Bool = !!(untyped process.env["npm_config_global"]); //wohooo \o/

  static var WINDOWS = Sys.systemName() == 'Windows';

  static function which(name) {
    return 
      Std.string(ChildProcess.spawnSync(if (WINDOWS) 'where' else 'which', [name]).stdout).split('\n').map(StringTools.trim);
  }

  static function main() 
    if (GLOBAL) {

      if (WINDOWS) {
        var sources = js.Node.__dirname.replace('\\', '/'),
            mayFail = 
              switch Sys.command('haxe', ['--run', 'show-version']) {
                case 0: function (c) return c == 'haxe';
                default: function (_) return false; 
              }

        inline function process(dir)
          exify(dir, sources, mayFail);

        // trace('file: ' + js.Node.__dirname);
        for (p in which('haxe')) 
          switch new Path(p) {
            case { ext: 'cmd', dir: npm }:
              
              process(npm);
              
            case { ext: 'exe', dir: std } if (Lambda.foreach(['CHANGES.txt', 'CONTRIB.txt', 'LICENSE.txt'], function (file) return '$std/$file'.exists())):
              
              process(std);

            default:            
          }
      }

  }
}