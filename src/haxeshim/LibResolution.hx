package haxeshim;

@:enum abstract LibResolution(String) {
  var Scoped = 'scoped';
  var Mixed = 'mixed';
  var Haxelib = 'haxelib';
}