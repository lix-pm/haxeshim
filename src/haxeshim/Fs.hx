package haxeshim;

import haxe.ds.Option;

using sys.io.File;
using haxe.io.Path;
using sys.FileSystem;
using StringTools;
using tink.CoreApi;

class Fs { 
  static public function get(path:String, ?pos):Promise<String>
    return 
      Future.sync(path.getContent.catchExceptions(function (data) {
        return Error.withData('failed to get content of $path', data, pos);
      }));

  static public function ensureDir(dir:String) {
    var isDir = dir.endsWith('/') || dir.endsWith('\\');
    
    if (isDir)
      dir = dir.removeTrailingSlashes();
      
    var parent = dir.directory();
    if (parent.removeTrailingSlashes() == dir) return;
    if (!parent.exists())
      ensureDir(parent.addTrailingSlash());
      
    if (isDir && !dir.exists()) 
      dir.createDirectory();
  }

  static public function ifNewer(files:{ src:String, dest:String }) 
    return files.src.stat().mtime.getTime() > files.dest.stat().mtime.getTime();

  static public function copy(src:String, target:String, ?filter:String->Bool, ?overwrite:{ src:String, dest:String }->Bool) {

    function copy(src:String, target:String, ensure:Bool) 
      if (filter == null || filter(src)) 
        if (src.isDirectory()) {
          
          Fs.ensureDir(target.addTrailingSlash());

          for (entry in src.readDirectory())
            copy('$src/$entry', '$target/$entry', false);

        }
        else {
          if (ensure)
            Fs.ensureDir(target);

          if (!target.exists() || overwrite == null || overwrite({ src: src, dest: target }))
            sys.io.File.copy(src, target);
        }
    
    copy(src, target, true);
  }
  
  static public function ls(dir:String, ?filter:String->Bool) {
    return [for (entry in dir.readDirectory()) switch '$dir/$entry' {
      case included if (filter == null || filter(included)): included;
      default: continue;
    }];
  }

  static public function delete(path:String) 
    if (path.isDirectory()) {
      for (file in ls(path)) 
        delete(file);
      path.deleteDirectory();
    }
    else path.deleteFile();
  
  static public function peel(file:String, depth:Int) {
    var start = 0;
    for (i in 0...depth)
      switch file.indexOf('/', start) {
        case -1: 
          return None;
        case v:
          start = v + 1;
      }
    return Some(file.substr(start));
  }
  
  static public function findNearest(name:String, dir:String) {
    
    while (true) 
      if ('$dir/$name'.exists())
        return Some('$dir/$name');
      else
        switch dir.directory() {
          case same if (dir == same): return None;
          case parent: dir = parent; 
        }
    
    return None;
  }
}
