package haxeshim;
import haxeshim.Scope.LibResolution;

using haxe.io.Path;
using sys.io.File;
using sys.FileSystem;
using StringTools;
using tink.CoreApi;

class HaxeArgs {
  
  var cwd:String;
  var mode:LibResolution;
  var ret:Array<String>;
  var libs:Array<String>;
  
  public function new(cwd, mode) {
    this.cwd = cwd;
    this.mode = mode;
  }
  
  public function resolve(args:Array<String>, haxelib:Array<String>->Array<String>) {
    
    this.ret = [];
    this.libs = [];
    
    process(args);
    
    return ret.concat(haxelib(libs));
  }
  
  function resolveInScope(lib:String) 
    return switch absolute('.haxelib/$lib.hxml') {
      case notFound if (!notFound.exists()):
        Failure('Cannot resolve `-lib $lib` because file $notFound is missing');
      case f: 
        processHxml(f);
        Success(Noise);
    }
    
  function processHxml(file:String) {
    process(file.getContent().split('\n').map(removeComments));
  }
  
  function process(args:Array<String>) {
    var i = 0,
    max = args.length;
          
    while (i < max)
      switch args[i++].trim() {
        case '':
        case '-cp':
          
          ret.push('-cp');
          ret.push(absolute(args[i++]));
          
        case '-lib':
          
          var lib = args[i++];
          
          switch mode {
            case Haxelib:
              
              libs.push(lib);
              
            case Scoped:
              
              if (lib.indexOf(':') == -1)
                resolveInScope(lib).sure();
              else
                throw 'Invalid `-lib $lib`. Version specification not supported in scoped mode';
                
            case Mixed:
              if (lib.indexOf(':') != -1 || !resolveInScope(lib).isSuccess())
                libs.push(lib);
          }
          
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