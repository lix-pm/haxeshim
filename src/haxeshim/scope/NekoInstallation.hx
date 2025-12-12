package haxeshim.scope;

import haxeshim.sys.*;

class NekoInstallation {
  public final path:String;
  public final executable:String;
  public final env:Env;
  public final platform:Platform;
  public final version:String;

  public function new(options) {
    
    this.path = options.path;
    this.platform = options.platform;
    this.version = options.version;

    this.executable = '$path/neko${Os.EXECUTABLE_EXTENSION}';

    var varName = switch Sys.systemName() {
      case 'Windows': 'PATH';
      case 'Mac': 'DYLD_LIBRARY_PATH';
      default: 'LD_LIBRARY_PATH';      
    }

    this.env = switch Sys.getEnv(varName) {
      case null: [varName => path];
      case withNeko if (withNeko.indexOf(path) != -1): {};
      case v: [varName => v + Os.DELIMITER + path];
    }
  }

  static public function get(root:String, platform:Platform, haxeVersion:String) {
    final version = '2.4.0';// TODO: may have to depend on haxe version
    
    return new NekoInstallation({ 
      platform: platform, 
      version: version,
      path: '$root/neko/versions/$version-$platform' 
    });
  }
}