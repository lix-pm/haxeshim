package haxeshim;

using tink.CoreApi;

@:enum abstract LibResolution(String) to String {
  /**
    Any parameters that are passed to haxeshim are parsed, including hxmls and the `-lib` parameters are "intercepted".
    To resolve these, we look for a `haxe_libraries/<libName>.hxml` and parse the parameters therein.
    If they are `-lib` parameters we process them accordingly.
    Note that in this case, specifying library versions as with `-lib name:version` is not allowed.
  **/
  var Scoped = 'scoped';

  /**
    Parameters are still parsed and then passed to `haxelib path` for resolution.
    In this case `-lib name:version` syntax is allowed.
  **/
  var Haxelib = 'haxelib';

  /**
    This is a mix of both approaches. Libraries that are not found using scoped
    resolutio nor that use `-lib name:version` format are process with `haxelib path`.
  **/
  var Mixed = 'mixed';

  static public function parse(s:String)
    return switch s {
      case 'scoped': Success(Scoped);
      case 'haxelib': Success(Haxelib);
      case 'mixed': Success(Mixed);
      default: Failure(new Error(UnprocessableEntity, 'Invalid lib resolution strategy `$s`'));
    }
}
