package haxeshim.scope;

import haxeshim.sys.*;

class NekoInstallation {
  public final path:String;
  public final executable:String;
  public final env:Env;

  public function new(path) {
    this.path = path;
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
    final nekoVersion = '2.4.0';// TODO: may have to depend on haxe version
    return new NekoInstallation('$root/neko/$nekoVersion-$platform');
  }
}