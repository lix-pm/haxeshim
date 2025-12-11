package haxeshim.sys;

class Os {
  
  static public var IS_WINDOWS(default, null):Bool = Sys.systemName() == 'Windows';
  
  static public var DELIMITER(default, null):String = if (IS_WINDOWS) ';' else ':';

  static public function slashes(path:String)
    return
      if (IS_WINDOWS) path.replace('/', '\\');
      else path;
}