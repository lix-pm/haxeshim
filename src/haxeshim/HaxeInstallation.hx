package haxeshim;

class HaxeInstallation {
  static var EXT = if (Os.IS_WINDOWS) '.exe' else '';  
  
  public var path(default, null):String;
  public var scope(default, null):String;
  public var stdLib(default, null):String;
  public var compiler(default, null):String;
  public var haxelib(default, null):String;
  public var version(default, null):String;
  public var haxelibRepo(default, null):String;
  
  public function new(path:String, version:String, haxelibRepo:String, scope:String) {
    this.path = path;
    this.version = version;
    this.compiler = '$path/haxe$EXT';
    this.haxelib = '$path/haxelib$EXT';
    this.stdLib = '$path/std';
    this.haxelibRepo = haxelibRepo;
    this.scope = scope;
  }
  
  public function env():Env {
    var ret:Env = {
      HAXE_STD_PATH: stdLib,
      HAXEPATH: path,
      HAXELIB_PATH: haxelibRepo,
      HAXE_VERSION: version,
      SCOPE_PATH: scope
    }

    return ret.mergeInto(Neko.ENV);
  }
  
}