package haxeshim;
import haxe.DynamicAccess;

using sys.io.File;
using sys.FileSystem;
using haxe.io.Path;

typedef SeekingOptions = {
  var startLookingIn(default, null):String;
  var homeDir(default, null):String;
}

class Scope {
  
  static var IS_WINDOWS = Sys.systemName() == 'Windows';
  static var EXT = if (IS_WINDOWS) '.exe' else '';
  
  public var haxeShimRoot(default, null):String;
  public var isGlobal(default, null):Bool;
  public var file(default, null):String;
  public var workingDir(default, null):String;
  public var config(default, null):HaxeConfig;
  
  //public var haxeBinary(get, never):String;
    //function get_haxeBinary()
      //return '$haxeRoot/versions/${config.version}/
  
  var resolver:HaxeArgs;
  
  function new(isGlobal, file, haxeShimRoot) {
    this.isGlobal = isGlobal;
    this.file = file;
    this.workingDir = file.directory();
    this.haxeShimRoot = haxeShimRoot;
    //trace(file);
    var src = 
      try {
        file.getContent();
      }
      catch (e:Dynamic) {
        throw 'Unable to open file $file because $e';
      }
    
    this.config =
      try {
        haxe.Json.parse(src);
      }
      catch (e:Dynamic) {
        Sys.stderr().writeString('Invalid JSON in file $file:\n\n$src\n\n');
        throw e;
      }
      
    if (config.version == null)
      throw 'No version set in $file';
      
    switch config.resolveLibs {
      case Scoped | Mixed | Haxelib:
      case v:
        throw 'invalid value $v for `resolveLibs` in $file';
    }
    
    this.resolver = new HaxeArgs(workingDir, config.resolveLibs);
    
  }
  
  function resolveThroughHaxelib(libs:Array<String>) {
    //TODO: this is currently a dummy implementation
    var ret = [];
    
    for (l in libs) {
      ret.push('-lib');
      ret.push(l);
    }
    
    return ret;
  }
  
  public function resolve(args:Array<String>) 
    return resolver.resolve(args, resolveThroughHaxelib);
    
  public function runHaxe(args:Array<String>) {
    //return Exec.run('$haxeRoot/versions/${config.version}/', workingDir, 
  }  
  
  static public function seek(options:SeekingOptions) {
    
    function global()
      return new Scope(true, options.homeDir + '/.haxerc', options.homeDir);
      
    function dig(cur:String) 
      return
        switch cur {
          case '$_/.haxerc' => found if (found.exists()):
            new Scope(false, found, options.homeDir);
          case '/' | '':
            global();
          case _.split(':') => [drive, ''] if (IS_WINDOWS && drive.length == 1):
            global();
          default:
            dig(cur.directory().removeTrailingSlashes());
        }
        
    return dig(options.startLookingIn.absolutePath().removeTrailingSlashes());
  }
  
  static public var DEFAULT_HOME(default, null):String =
    if (IS_WINDOWS) 
      Sys.getEnv('APPDATA') + '/haxe';
    else 
      '~/haxe';//no idea if this will ever work
}

typedef HaxeConfig = {
  var version(default, null):String;
  var resolveLibs(default, null):LibResolution;
}

@:enum abstract LibResolution(String) {
  var Scoped = null;
  var Mixed = 'mixed';
  var Haxelib = 'haxelib';
}