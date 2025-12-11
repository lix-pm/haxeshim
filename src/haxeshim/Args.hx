package haxeshim;

import haxe.ds.ReadOnlyArray;
import haxeshim.Errors;
using haxe.io.Path;
using tink.CoreApi;
using StringTools;

typedef Arg = {
  final val:String;
  final pos:Pos;
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
                if (v == '$${$name}') v;
                else switch interpolate(v, getVar) {
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
        errors = new Errors(),
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
          errors.fail(e, File(filename, line));
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

    return errors.produce(ret);
  }

  static public function getNdll(s:String)
    return
      if (s.startsWith('ndll:')) Some(s.substr(5));
      else None;

  static public function makeNdll(s:String)
    return 'ndll:$s';

  static public function split(args:Array<String>, cwd:String, fs:Fs, getVar:String->Null<String>) {
    var args:Array<Arg> = [for (i in 0...args.length) { val: args[i], pos: Cmd(i) }],
        each_params:Array<Arg> = [],
        acc:Array<Arg> = [],
        ret = [],
        errors = new Errors();

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
          switch arg.val {
            case '--next': flush();
            case '--each': each_params = acc; acc = [];
            case '--run' | '-x':
              acc = acc.concat([arg].concat(args));
              args = [];
              flush();
            case '--cwd' | '-C':
              switch args.shift() {
                case null:
                  errors.fail('${arg.val} without argument', arg.pos);
                case v:
                  cwd = resolvePath(v.val);
                  if (!fs.isDirectory(cwd)) {
                    errors.fail('Cannot use $cwd as working directory', v.pos);//not sure the error is 100% accurate
                    args = [];//no point in continuing from here on
                  }
              }
            case hxml if (hxml.extension() == 'hxml'):
              args = readHxml(resolvePath(hxml), fs, getVar, errors, arg.pos).concat(args);
            case v if (v.startsWith("${")):
              switch interpolate(v, getVar) {
                case Success(v): acc.push({ val: v, pos: arg.pos });
                case Failure(e):
                  errors.fail(e, arg.pos);
              }
            default:
              acc.push(arg);
          }
      }

    return errors.produce(ret);
  }

  static public function readHxml(hxml, fs:Fs, getVar, errors:Errors, pos)
    return
      switch fs.readFile(hxml) {
        case Failure(e):
          errors.fail(e, pos);
          [];
        case Success(raw):
          errors.getResult(fromMultilineString(raw, hxml, getVar));
      }
}

private typedef Fs = {
  function readFile(path:String):Outcome<String, String>;
  function isDirectory(path:String):Bool;
}