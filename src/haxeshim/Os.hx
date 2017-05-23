package haxeshim;

using StringTools;

class Os {
  
  static public var IS_WINDOWS(default, null):Bool = Sys.systemName() == 'Windows';

  static public function slashes(path:String)
    return
      if (IS_WINDOWS) path.replace('/', '\\');
      else path;
}