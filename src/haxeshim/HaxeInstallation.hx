package haxeshim;

class HaxeInstallation {
  static var EXT = if (Os.IS_WINDOWS) '.exe' else '';  
  
  public var path(default, null):String;
  public var stdLib(default, null):String;
  public var compiler(default, null):String;
  public var haxelib(default, null):String;
  public var version(default, null):String;
  public var haxelibRepo(default, null):String;
  public var nekoPath(default, null):String;
  
  
  public function new(path:String, version:String, haxelibRepo:String, nekoPath:String) {
    this.path = path;
    this.version = version;
    this.compiler = '$path/haxe$EXT';
    this.haxelib = '$path/haxelib$EXT';
    this.stdLib = '$path/std';
    this.haxelibRepo = haxelibRepo;
    this.nekoPath = 
      if (Os.IS_WINDOWS) StringTools.replace(nekoPath, '/', '\\');
      else nekoPath;
  }
  
  public function env() {
    var ret:haxe.DynamicAccess<String> = {
      HAXE_STD_PATH: stdLib,
      HAXEPATH: path,
      HAXELIB_PATH: haxelibRepo,
      HAXE_VERSION: version,
    }

    function addNeko(varName:String, sep:String = ':')
      ret[varName] =
        switch Sys.getEnv(varName) {
          case null: nekoPath;
          case withNeko if (withNeko.indexOf(nekoPath) != -1):
            withNeko;
          case v:
            '$v$sep$nekoPath';
        }

    switch Sys.systemName() {
      case 'Windows':
        addNeko('PATH', ';');
      case 'Mac':
        addNeko('DYLD_LIBRARY_PATH');
      default:
        addNeko('LD_LIBRARY_PATH');
    }

    return ret;
  }
  
}