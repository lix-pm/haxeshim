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
    
    if (!'$dir/CHANGES.txt'.exists())
      '$dir/CHANGES.txt'.saveContent("0: 0\nI'm only here to please FlashDevelop ... which I seem to fail at");
  }
  
  static function main() 
    switch Sys.systemName() {
      case 'Windows' if (!!(untyped process.env["npm_config_global"])): //wohooo \o/
        for (path in Std.string(ChildProcess.spawnSync('where', ['haxe']).stdout).split('\n').map(StringTools.trim).map(Path.new)) {
          switch path {
            case { ext: 'cmd', dir: npm }:
              
              exify(npm);
              
            case { ext: 'exe', dir: std } if (Lambda.foreach(['CHANGES.txt', 'CONTRIB.txt', 'LICENSE.txt'], function (file) return '$std/$file'.exists())):
              
              exify(std);
              
            default: 
          }
        }
      default:
    }
  
}