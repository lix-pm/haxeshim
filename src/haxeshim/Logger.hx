package haxeshim;

import ANSI;

class Logger {
  public function new() {}
  public function error(s:String) {}
  public function warning(s:String) {}
  public function info(s:String) {}
  public function success(s:String) {}
  public function progress(s:String) {}
}

class SysLogger {
  static var out = {
    ANSI.available = true;
    Sys.stderr();
  }
  public function new() {}
  function log(level:Level, msg) {
    progress('');
    out.writeString(ANSI.aset(switch level {
      case Error: [Red, ReverseVideo, Blue];
      case Warning: [Yellow];
      case Info: [DefaultForeground];
      case Success: [Green];
    }) + msg + ANSI.aset([Off]) + '\n');
  }
  public function error(s:String) log(Error, s);
  public function warning(s:String) log(Warning, s);
  public function info(s:String) log(Info, s);
  public function success(s:String) log(Success, s);
  public function progress(s:String) {
    out.writeString(
      ANSI.eraseLine() + ANSI.setX() + s
    );
    out.flush();
  }

}

private enum Level {
  Error;
  Warning;
  Info;
  Success;
}