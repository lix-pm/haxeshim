package haxeshim;

using tink.CoreApi;

@:forward
abstract Args(Array<String>) from Array<String> to Array<String> {

  @:op(a + b) static function raddString(a:Args, b:String):Args
    return a + [b];

  @:op(a + b) static function laddString(a:String, b:Args):Args
    return [a] + b;

  @:op(a + b) static function raddArray(a:Args, b:Array<String>):Args
    return a.concat(b);

  @:op(a + b) static function laddArray(a:Array<String>, b:Args):Args
    return a.concat(b);

  @:op(a + b) static function add(a:Args, b:Args):Args
    return laddArray(a, b);

  public function interpolate(resolve:String->Option<String>):{ args:Args, errors:Array<String> } {
    var errors = [],
        ret = [];

    for (a in this) {
      var single = interpolateString(a, resolve);
      errors = errors.concat(single.errors);
      ret.push(single.result);
    }

    return { args: ret, errors: errors };
  }
  static public function interpolateString(s:String, resolve:String->Option<String>):{ result:String, errors:Array<String> } {
    if (s.indexOf("${") == -1)
      return { result: s, errors: [] };
      
    var ret = new StringBuf(),
        pos = 0,
        errors = [];
        
    function result()
      return { result: ret.toString(), errors: errors };

    while (pos < s.length)
      switch s.indexOf("${", pos) {
        case -1:
          ret.addSub(s, pos);
          break;
        case v:
          var start = v + 2;
          var end = switch s.indexOf('}', start) {
            case -1:
              errors.push('unclosed interpolation in $s');
              ret.addSub(s, pos);
              return result();
              -1;//unreachable
            case v: v;
          }
          ret.addSub(s, pos, v - pos);
          
          var name = s.substr(start, end - start);
          
          ret.add(
            switch resolve(name) {
              case None:
                errors.push('Unresolved variable $name');
                name;
              case Some(v):
                v;
            }
          );
          
          pos = end + 1;
      }
    
    return result();
  }  
}