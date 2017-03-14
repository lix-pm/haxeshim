package haxeshim;

import haxe.Resource;
import js.node.ChildProcess;
import js.Node.*;

using sys.io.File;
using sys.FileSystem;
using haxe.io.Path;
using StringTools;

class PostInstall { 
  
  static var exifier = Resource.getBytes('exify');
  
  static function exify(dir) {    

    for (name in ['haxe', 'haxelib']) {
      var exe = '$dir/$name.exe';
      if (exe.exists() && !'$exe.bak'.exists())
        exe.rename('$exe.bak');
      exe.saveBytes(exifier);
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
        for (p in which('haxe')) 
          switch new Path(p) {
            case { ext: 'cmd', dir: npm }:
              
              exify(npm);
              
            case { ext: 'exe', dir: std } if (Lambda.foreach(['CHANGES.txt', 'CONTRIB.txt', 'LICENSE.txt'], function (file) return '$std/$file'.exists())):
              
              exify(std);

            default:            
          }
      }

  }
}