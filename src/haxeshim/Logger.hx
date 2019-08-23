package haxeshim;

import ANSI;

class Logger {
  function new() {}
  public function error(s:String) {}
  public function warning(s:String) {}
  public function info(s:String) {}
  public function success(s:String) {}
  public function progress(s:String) {}
  static var SILENT:Logger;
  static var DEFAULT:Logger;
  static public function get(silent:Bool = false):Logger
    return 
      if (silent) {
        if (SILENT == null) SILENT = new Logger();
        SILENT;
      }
      else {
        if (DEFAULT == null) DEFAULT = new SysLogger();
        DEFAULT;
      }
       
}

private class SysLogger extends Logger {
  static var isTTY = 
    #if nodejs 
      js.Node.process.stderr.isTTY; 
    #else
      false;
    #end
  static var out = {
    ANSI.available = isTTY;
    Sys.stderr();
  }
  public function new() super();
  function log(level:Level, msg) {
    progress('');
    out.writeString(ANSI.aset(switch level {
      case Error: [Red];
      case Warning: [Yellow];
      case Info: [DefaultForeground];
      case Success: [Green];
    }) + msg + ANSI.aset([Off]) + '\n');
    #if !nodejs
    out.flush();
    #end
  }

  override public function error(s:String) log(Error, s);
  override public function warning(s:String) log(Warning, s);
  override public function info(s:String) log(Info, s);
  override public function success(s:String) log(Success, s);
  override public function progress(s:String) if (isTTY) {
    if (s.length > 80)
      s = s.substr(0, 77) + '...';
    out.writeString(
      ANSI.eraseLine() + ANSI.setX() + s
    );
    #if !nodejs
    out.flush();
    #end
  }

}

private enum Level {
  Error;
  Warning;
  Info;
  Success;
}