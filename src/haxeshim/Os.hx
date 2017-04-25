package haxeshim;

class Os {
  static public var IS_WINDOWS(default, null):Bool = Sys.systemName() == 'Windows';
}