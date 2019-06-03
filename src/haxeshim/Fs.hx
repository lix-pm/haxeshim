package haxeshim;

import haxe.ds.Option;
import haxe.io.Bytes;

using sys.io.File;
using haxe.io.Path;
using sys.FileSystem;
using StringTools;
using tink.CoreApi;

private abstract Payload(Bytes) from Bytes to Bytes {
  @:from static function ofString(s:String):Payload
    return Bytes.ofString(s);
}

class Fs { 
  static function attempt<T>(what:String, how:Void->T, ?pos):Promise<T>
    return 
      Future.lazy(function () return how.catchExceptions(function (data) {
        return Error.withData('Failed to $what', data, pos);
      }));

  static public function get(path:String, ?pos):Promise<String>
    return attempt('get content of $path', path.getContent, pos);

  static public function save(path:String, payload:Payload, ?pos):Promise<Noise>
    return ensureDir(path).next(_ -> attempt('save to $path', path.saveBytes.bind(payload), pos));

  static public function exists(path:String)
    return attempt('check the existence of $path', path.exists);

  static public function ensureDir(dir:String):Promise<Noise> {
    var isDir = dir.endsWith('/') || dir.endsWith('\\');
    
    if (isDir)
      dir = dir.removeTrailingSlashes();
      
    var parent = dir.directory();

    return 
      if (parent.removeTrailingSlashes() == dir) Noise;
      else 
        exists(parent)
          .next(
            exists -> 
              if (exists) Noise
              else ensureDir(parent.addTrailingSlash())
          )
          .next(
            _ -> 
              if (isDir) 
                exists(dir).next(exists -> 
                  attempt('create directory $dir', () -> { 
                    if (!exists) dir.createDirectory();
                    Noise;
                  })
                )
              else
                Noise
          );
  }

  static function isDirectory(path:String)
    return attempt('check if $path is a directory', path.isDirectory);

  static public function ifNewer(files:{ src:String, dest:String }) 
    return files.src.stat().mtime.getTime() > files.dest.stat().mtime.getTime();

  static public function move(src:String, target:String):Promise<Noise>
    return 
      ensureDir(target).next(_ -> attempt('move $src to $target', src.rename.bind(target)));

  static public function copy(src:String, target:String, ?filter:String->Bool, ?overwrite:{ src:String, dest:String }->Bool) {

    function copy(src:String, target:String, ensure:Bool):Promise<Noise>
      return 
        if (filter == null || filter(src)) 
          isDirectory(src).next(isDir -> 
            if (isDir) 
              Fs.ensureDir(target.addTrailingSlash())
                .next(
                  _ -> Promise.inParallel([
                    for (entry in src.readDirectory()) copy('$src/$entry', '$target/$entry', false)
                  ]).noise()
                )
            else (
              if (ensure)
                Fs.ensureDir(target)
              else 
                Promise.NOISE
            ).next(_ ->
              if (overwrite == null || overwrite({ src: src, dest: target })) false
              else exists(target)
            ).next(skip ->
              if (skip) Noise
              else attempt('copy $src to $target', sys.io.File.copy.bind(src, target))
            )
          )
        else Noise;

    return copy(src, target, true);
  }
  
  static public function ls(dir:String, ?filter:String->Bool) {
    return [for (entry in dir.readDirectory()) switch '$dir/$entry' {
      case included if (filter == null || filter(included)): included;
      default: continue;
    }];
  }

  static public function delete(path:String) 
    return attempt('delete $path', () -> 
      if (path != null && path.exists()) 
        if (path.isDirectory()) {
          for (file in ls(path)) 
            delete(file);
          path.deleteDirectory();
        }
        else path.deleteFile()
    );
  
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
