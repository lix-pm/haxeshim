package haxeshim;

import haxeshim.sys.*;

class HaxeInstallation {
  static var EXT = if (Os.IS_WINDOWS) '.exe' else '';  
  
  public var path(default, null):String;
  public var stdLib(default, null):String;
  public var compiler(default, null):String;
  public var haxelib(default, null):String;
  public var version(default, null):String;
  public var haxelibRepo(default, null):String;
  
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