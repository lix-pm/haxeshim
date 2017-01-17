package haxeshim;

class HaxeInstallation {
  static var EXT = if (Scope.IS_WINDOWS) '.exe' else '';  
  
  public var path(default, null):String;
  public var stdLib(default, null):String;
  public var compiler(default, null):String;
  public var version(default, null):String;
  
  public function new(path:String, version:String) {
    this.path = path;
    this.version = version;
    this.compiler = '$path/haxe$EXT';
    this.stdLib = '$path/std';
  }
  
}