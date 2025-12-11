package haxeshim.scope;

import haxeshim.sys.*;

using sys.io.File;
using sys.FileSystem;

class HaxeInstallation {
  static var EXT = if (Os.IS_WINDOWS) '.exe' else '';  
  
  public final path:String;
  public final stdLib:String;
  public final compiler:String;
  public final haxelib:String;
  public final version:String;
  public final haxelibRepo:String;
  public final platform:Platform;
  
  public function new(path:String, version:String, haxelibRepo:String, platform:Platform) {
    this.path = path;
    this.version = version;
    this.compiler = '$path/haxe$EXT';
    this.haxelib = '$path/haxelib$EXT';
    this.stdLib = '$path/std';
    this.haxelibRepo = haxelibRepo;
    this.platform = platform;
  }

  static public function at(path:String, version:String, haxelibRepo:String):HaxeInstallation {
    final info = '$path/platform.txt';
    final platform = 
      if (info.exists()) info.getContent();
      else {
        final file = '$path/haxe$EXT'.read();
        final b = file.read(1024);
        final p = Platform.detect(b);
        info.saveContent(p);
        p;
      }
    return new HaxeInstallation(path, version, haxelibRepo, cast platform);
  }
  
  public function env():Env {
    var ret:Env = {
      HAXE_STD_PATH: stdLib,
      HAXEPATH: path,
      HAXELIB_PATH: haxelibRepo,
      HAXE_VERSION: version,
    }

    return ret.mergeInto(Neko.ENV);
  }
  
}