package haxeshim;

using tink.CoreApi;

@:enum abstract LibResolution(String) to String {
  var Scoped = 'scoped';
  var Mixed = 'mixed';
  var Haxelib = 'haxelib';

  static public function parse(s:String)
    return switch s {
      case 'scoped': Success(Scoped);
      case 'mixed': Success(Mixed);
      case 'haxelib': Success(Haxelib);
      default: Failure(new Error(UnprocessableEntity, 'Invalid lib resolution strategy `$s`'));
    }
}