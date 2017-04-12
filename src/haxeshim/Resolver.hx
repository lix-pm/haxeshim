package haxeshim;

using haxe.io.Path;
using sys.io.File;
using sys.FileSystem;
using StringTools;
using tink.CoreApi;

class Resolver {
  
  var cwd:String;
  var libDir:String;
  var mode:LibResolution;
  var ret:Array<String>;
  var resolved:Map<String, Bool>;
  var defaults:String->Null<String>;
  var errors:Array<Error>;
  
  public function new(cwd, libDir, mode, defaults) {
    this.cwd = cwd;
    this.libDir = libDir;
    this.mode = mode;
    this.defaults = defaults;
  }
  
  static public function interpolate(s:String, defaults:String->Null<String>) {
    if (s.indexOf("${") == -1)
      return s;
      
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
            switch Sys.getEnv(name) {
              case '' | null:
                switch defaults(name) {
                  case null:
                    throw 'unknown variable $name';
                  case v: v;
                }
              case v: v;
            }
          );
          
          pos = end + 1;
      }
    
    return ret.toString();
  }
  
  public function resolve(args:Array<String>, haxelib:Array<String>->Array<String>):Array<String> {
    this.ret = [];
    this.errors = [];
    this.resolved = new Map();
    
    process(args);
    
    switch errors {
      case []:
      case v:
        throw v.map(function (e) return e.message).join('\n');
    }    

    var start = 0,
        pos = 0, 
        final = []; 
    
    function libs(args:Array<String>) {
      var ret = [],
          libs = [], 
          i = 0, 
          max = switch args.indexOf('--run') {
            case -1: args.length;
            case v: v;
          }

      while (i < max) 
        switch args[i++] {
          case '-lib':
            libs.push(args[i++]);
          case v:
            ret.push(v);
        }

      ret = ret.concat(args.slice(max));
      
      return switch libs {
        case []: ret;
        default: haxelib(libs).concat(ret);
      }    
    }
    
    function flush() {
      final = final.concat(libs(ret.slice(start, pos)));
      start = pos;
    }
        
    while (pos < ret.length) 
      switch ret[pos++] {
        case '--next' | '--each':
          flush();
        default:
      }
      
    flush();
    
    return final;
  }
  
  static public function libHxml(libDir:String, libName:String)
    return '$libDir/$libName.hxml';
  
  function resolveInScope(lib:String) 
    return 
      if (resolved[lib]) Success(Noise);
      else
        switch libHxml(libDir, lib) {
          case notFound if (!notFound.exists()):
            Failure(new Error(NotFound, 'Cannot resolve `-lib $lib` because file $notFound is missing'));
          case f: 
            resolved[lib] = true;
            processHxml(f);
            Success(Noise);
        }
    
  function processHxml(file:String) {
    process(parseLines(file.getContent()));
  }
  
  static public function parseLines(source:String, ?normalize:String->Array<String>) {
    if (normalize == null)
      normalize = function (x) return [x];
      
    var ret = [];
    
    for (line in source.split('\n').map(StringTools.trim))
      switch line.charAt(0) {
        case null:
        case '-':
          switch line.indexOf(' ') {
            case -1:
              ret.push(line);
            case v:
              ret.push(line.substr(0, v));
              ret.push(line.substr(v).trim());
          }
        case '#':
        default:
          switch line.trim() {
            case '':
            case v:
              for (a in normalize(v))
                ret.push(a);
          }
      }
    
    return ret;
  }
  
  function process(args:Array<String>) {
    var i = 0,
        max = args.length,
        interpolate = interpolate.bind(_, defaults);
          
    while (i < max)
      switch args[i++].trim() {
        case '':
        case '-cp':
          
          ret.push('-cp');
          ret.push(absolute(interpolate(args[i++])));
          
        case '-resource':
          
          ret.push('-resource');
          
          var res = args[i++];
          
          ret.push(
            switch res.lastIndexOf('@') {
              case -1: 
                res;
              case v:
                absolute(res.substr(0, v)) + '@' + res.substr(v + 1);
            }
          );
          
        case '-lib':
          
          var lib = args[i++];
          function add() {
            ret.push('-lib');
            ret.push(lib);
          }
          switch mode {
            case Haxelib:
              add();              
            case Scoped:
              
              if (lib.indexOf(':') == -1)
                switch resolveInScope(lib) {
                  case Failure(e): errors.push(e);
                  default:
                }
              else
                throw 'Invalid `-lib $lib`. Version specification not supported in scoped mode';
                
            case Mixed:
              if (lib.indexOf(':') != -1 || !resolveInScope(lib).isSuccess())
                add();
          }
        case '-scoped-hxml':
          var target = absolute(interpolate(args[i++]));
          var parts = Scope.seek({ cwd: target.directory() }).resolve([target]);
          
          for (arg in parts)
            ret.push(arg);
          
        case hxml if (hxml.endsWith('.hxml')):
          
          processHxml(absolute(hxml));
          
        case v:
          ret.push(v);
      }
  }
  
  function absolute(path:String)
    return 
      if (path.isAbsolute()) path;
      else Path.join([cwd, path]);
  
  static function removeComments(line:String)
    return 
      switch line.indexOf('#') {
        case -1: line;
        case v: line.substr(0, v);
      }
  
}