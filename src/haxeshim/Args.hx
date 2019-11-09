package haxeshim;

using tink.CoreApi;
using StringTools;

class Args {
  static public function interpolate(s:String, getVar:String->Null<String>) {
    if (s.indexOf("${") == -1)
      return Success(s);
      
    var ret = new StringBuf(),
        pos = 0;
        
    while (pos < s.length)
      switch s.indexOf("${", pos) {
        case -1:
          ret.addSub(s, pos);
          break;
        case v:
          ret.addSub(s, pos, v - pos);
          var start = v + 2;
          var end = switch s.indexOf('}', start) {
            case -1:
              throw 'unclosed interpolation in $s';
            case v: v;
          }
          
          var name = s.substr(start, end - start);
          
          ret.add(
            switch getVar(name) {
              case null:
                return Failure('unknown variable $name');
              case v: v;
            }
          );
          
          pos = end + 1;
      }
    
    return Success(ret.toString());
  }

  static public function fromMultilineString(
    source:String, 
    filename:String, 
    getVar:String->Null<String>,
    liftClassPaths:Bool = false // haxelib allows to pass classpaths without -cp
  ) {
      
    var ret = [],
        errors = [],
        getVar = 
          s -> 
            if (s == '__dirname') haxe.io.Path.directory(filename) 
            else getVar(s);

    function add(s:String, line:Int)
      if (s.charAt(0) == '-')
        ret.push(s);
      else switch interpolate(s, getVar) {
        case Success(v):
          ret.push(v);
        case Failure(e):
          errors.push('$filename:$line: $e');
      }

    var lines = source.split('\n').map(StringTools.trim);
    for (number in 0...lines.length) {
      var line = lines[number],
          add = add.bind(_, number);
      switch line.charAt(0) {
        case null:
        case '-':
          switch line.indexOf(' ') {
            case -1:
              add(line);
            case v:
              add(line.substr(0, v));
              add(line.substr(v).trim());
          }
        case '#':
        default:
          switch line.trim() {
            case '':
            case v:
              if (liftClassPaths) ret.push('-cp');
              add(v);
          }
      }
    }

    return switch errors {
      case []: Success(ret);
      default: Failure({ errors: errors, args: ret });
    }
  }
}