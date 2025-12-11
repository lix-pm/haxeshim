package haxeshim.scope;

import haxeshim.sys.*;

class HaxeInstallation {
  static var EXT = if (Os.IS_WINDOWS) '.exe' else '';  
  
  public final path:String;
  public final stdLib:String;
  public final compiler:String;
  public final haxelib:String;
  public final version:String;
  public final haxelibRepo:String;
  
  public function new(path:String, version:String, haxelibRepo:String) {
    this.path = path;
    this.version = version;
    this.compiler = '$path/haxe$EXT';
    this.haxelib = '$path/haxelib$EXT';
    this.stdLib = '$path/std';
    this.haxelibRepo = haxelibRepo;
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