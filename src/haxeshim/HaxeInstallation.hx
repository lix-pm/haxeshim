package haxeshim;

class HaxeInstallation {
  static var EXT = if (Scope.IS_WINDOWS) '.exe' else '';  
  
  public var path(default, null):String;
  public var stdLib(default, null):String;
  public var compiler(default, null):String;
  public var haxelib(default, null):String;
  public var version(default, null):String;
  public var libs(default, null):String;
  
  
  public function new(path:String, version:String, libs:String) {
    this.path = path;
    this.version = version;
    this.compiler = '$path/haxe$EXT';
    this.haxelib = '$path/haxelib$EXT';
    this.stdLib = '$path/std';
    this.libs = libs;
  }
  
  public function env() 
    return {
      HAXE_STD_PATH: stdLib,
      HAXEPATH: path,
      HAXELIB_PATH: libs,
      HAXE_VERSION: version,
    }
  
}