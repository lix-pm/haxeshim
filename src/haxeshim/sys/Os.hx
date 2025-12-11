package haxeshim.sys;

#if nodejs
import js.Node.process;
#end

class Os {
  
  static public var IS_WINDOWS(default, null):Bool = Sys.systemName() == 'Windows';
  
  static public var DELIMITER(default, null):String = if (IS_WINDOWS) ';' else ':';

  static public var EXECUTABLE_EXTENSION(default, null):String = if (IS_WINDOWS) '.exe' else '';

  static public function slashes(path:String)
    return
      if (IS_WINDOWS) path.replace('/', '\\');
      else path;

  static public var platform(get, null):Platform;
    static function get_platform() {
      return platform ??= {
        #if nodejs
          switch [process.platform, process.arch] {
            case ["linux", "x64"]:   Linux64;
            case ["linux", "ia32"]:  Linux32;
            case ["linux", "arm"]:   LinuxArm;
            case ["linux", "arm64"]: LinuxArm64;
            case ["linux", "riscv64"]: LinuxRiscV;
            case ["win32", "x64"]:   Win64;
            case ["win32", "ia32"]:  Win32;
            case ["darwin", "x64"]:  Mac64;
            case ["darwin", "arm64"]: MacArm;
            default: Unknown;
          }
        #else
          var file = sys.io.File.read(Sys.programPath);
          var b = file.read(1024);
          file.close();
          Platform.detect(b);
        #end
      }
    }  
}