package haxeshim;

@:enum abstract LibResolution(String) {
  var Scoped = null;
  var Mixed = 'mixed';
  var Haxelib = 'haxelib';
}