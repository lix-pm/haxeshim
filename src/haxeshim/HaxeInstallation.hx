package haxeshim;

class HaxeInstallation {
  static var EXT = if (Scope.IS_WINDOWS) '.exe' else '';  
  
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
    this.nekoPath = nekoPath;
  }
  
  public function env() {
    var ret:haxe.DynamicAccess<String> = {
      HAXE_STD_PATH: stdLib,
      HAXEPATH: path,
      HAXELIB_PATH: haxelibRepo,
      HAXE_VERSION: version,
    }

    function addNeko(varName:String, sep:String = ':')
      switch Sys.getEnv(varName) {
        case v if (v.indexOf(nekoPath) == -1):
          ret[varName] = [
            Sys.getEnv(varName),
            nekoPath
          ].join(sep);
        default:
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