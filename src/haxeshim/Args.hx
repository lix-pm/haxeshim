package haxeshim;

import haxe.ds.ReadOnlyArray;
using haxe.io.Path;
using tink.CoreApi;
using StringTools;

typedef Arg = {
  final val:String;
  final pos:Pos;
}

enum Pos {
  File(path:String, line:Int);
  Cmd(index:Int);
}
class Args {
  
  public final cwd:String;
  public final args:ReadOnlyArray<Arg>;

  function new(cwd, args) {
    this.cwd = cwd;
    this.args = args;
  }
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
              return Failure('unclosed interpolation in $s');
            case v: v;
          }
          
          var name = s.substr(start, end - start);
          
          ret.add(
            switch getVar(name) {
              case null:
                return Failure('unknown variable $name');
              case v: 
                switch interpolate(v, getVar) {
                  case Success(v): v;
                  case ret: return ret;
                }
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
      
    var ret:Array<Arg> = [],
        errors = [],
        getVar = 
          s -> 
            if (s == '__dirname') haxe.io.Path.directory(filename) 
            else getVar(s);

    function add(s:String, line:Int) {
      function add(s)
        ret.push({ pos: File(filename, line), val: s });
      if (s.charAt(0) == '-')
        add(s);
      else switch interpolate(s, getVar) {
        case Success(v): add(v);
        case Failure(e):
          errors.push({ message: e, pos: File(filename, line) });
      }
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
              if (liftClassPaths) add('-cp');
              add(v);
          }
      }
    }

    return switch errors {
      case []: Success(ret);
      default: Failure({ errors: errors, args: ret });
    }
  }

  static public function split(args:Array<String>, cwd:String, fs:Fs, getVar:String->Null<String>) {

    var args:Array<Arg> = [for (i in 0...args.length) { val: args[i], pos: Cmd(i) }],
        each_params:Array<Arg> = [],
        acc:Array<Arg> = [],
        ret = [],
        errors = [];

    function resolvePath(s:String)
      return 
        if (s.isAbsolute()) s;
        else Path.join([cwd, s]);

    function flush() 
      if (acc.length > 0) {
        var build = new Args(cwd, each_params.concat(acc));
        acc = [];
        ret.push(build);
      }

    while (true)
      switch args.shift() {
        case null: flush(); break;
        case arg:
          function next(step:Arg->Void)
            switch args.shift() {
              case null: 
                errors.push({ pos: arg.pos, message: '${arg.val} without argument' });
              case v:
                step(v);
            }
          switch arg.val {
            case '--next': flush();
            case '--each': each_params = acc; acc = [];
            case '--connect': 
              acc.push(arg);
              next(acc.push);
            case '--run' | '-x': 
              acc = [arg].concat(args);
              args = [];
              flush();
            case '--cwd' | '-C':
              next(v -> {
                cwd = resolvePath(args.shift().val);
                if (!fs.isDirectory(cwd)) {
                  errors.push({ pos: v.pos, message: 'Cannot use $cwd as working directory' });//not sure the error is 100% accurate
                  args = [];//no point in continuing from here on
                }
              });
            case hxml if (hxml.extension() == 'hxml'):
              switch fs.readFile(hxml) {
                case Failure(e):
                  errors.push({ pos: arg.pos, message: e });
                case Success(raw):
                  args = (switch fromMultilineString(raw, hxml, getVar) {
                    case Success(args):
                      args;
                    case Failure({ args: args, errors: e }):
                      errors = errors.concat(e);
                      args;
                  }).concat(args);
              }
            default:
              acc.push(arg);
          }
      }

    return ret;
  }
}

private typedef Fs = {
  function readFile(path:String):Outcome<String, String>;
  function isDirectory(path:String):Bool;
}