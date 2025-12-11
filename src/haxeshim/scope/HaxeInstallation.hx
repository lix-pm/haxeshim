package haxeshim.scope;

import haxeshim.sys.*;
import haxeshim.sys.Os.EXECUTABLE_EXTENSION as EXT;

using sys.io.File;
using sys.FileSystem;

class HaxeInstallation {  
  public final path:String;
  public final stdLib:String;
  public final compiler:String;
  public final haxelib:String;
  public final version:String;
  public final haxelibRepo:String;
  public final neko:NekoInstallation;
  public final env:Env;
  
  public function new(path:String, version:String, haxelibRepo:String, neko:NekoInstallation) {
    this.path = path;
    this.version = version;
    this.compiler = '$path/haxe$EXT';
    this.haxelib = '$path/haxelib$EXT';
    this.stdLib = '$path/std';
    this.haxelibRepo = haxelibRepo;
    this.neko = neko;
    this.env = neko.env.mergeInto({
      HAXE_STD_PATH: stdLib,
      HAXEPATH: path,
      HAXELIB_PATH: haxelibRepo,
      HAXE_VERSION: version,
    });
  }

  static public function at(options:{ root:String, version:String, haxelibRepo:String, path:String }):HaxeInstallation {
    final path = options.path,
        version = options.version;

    final info = '$path/platform.txt';

    final platform:Platform = cast
      if (info.exists()) info.getContent();
      else {
        final file = '$path/haxe$EXT'.read();
        final b = file.read(1024);
        final p = Platform.detect(b);
        try info.saveContent(p) catch (e:Dynamic) Logger.get().error('Failed to cache platform in info: $e');
        p;
      }

    return new HaxeInstallation(
      path, 
      version, 
      options.haxelibRepo, 
      NekoInstallation.get(options.root, platform, version)
    );
  }  
}