package haxeshim;
import haxe.DynamicAccess;

using sys.io.File;
using sys.FileSystem;
using StringTools;
using haxe.io.Path;

typedef SeekingOptions = {
  @:optional var cwd(default, null):String;
  @:optional var startLookingIn(default, null):String;
  @:optional var haxeshimRoot(default, null):String;
}

class Scope {
 
  static public var IS_WINDOWS(default, null):Bool = Sys.systemName() == 'Windows';
  
  static var CONFIG_FILE = '.haxerc';
  /**
   * The root directory for haxeshim as configured when the scope was creates
   */
  public var haxeshimRoot(default, null):String;
  /**
   * Indicates whether the scope is global
   */
  public var isGlobal(default, null):Bool;
  /**
   * The directory of the scope, where the `.haxerc` file was found and also where the `.scopedHaxeLibs` directory is expected
   */
  public var scopeDir(default, null):String;
  /**
   * Indicates the path the the scope's config file. This is likely to be `'$scopeDir/.haxerc'`, 
   * but you should rely on this field to avoid hardcoding assumptions that may break in the future.
   */
  public var configFile(default, null):String;
  /**
   * The working directory that the scope was created with.
   * If the scope is not global, this is almost certainly a subdirectory of `scopeDir`.
   */
  public var cwd(default, null):String;
  
  public var haxeInstallation(default, null):HaxeInstallation;
  /**
   * The data read from the config file.
   */
  public var config(default, null):Config;
  
  var resolver:Resolver;
  
  function new(haxeshimRoot, isGlobal, scopeDir, cwd) {
    
    this.haxeshimRoot = haxeshimRoot;
    this.isGlobal = isGlobal;
    this.scopeDir = scopeDir;
    this.cwd = cwd;
    
    configFile = '$scopeDir/$CONFIG_FILE';

    //trace(file);
    var src = 
      try {
        configFile.getContent();
      }
      catch (e:Dynamic) 
        throw 
          if (isGlobal)
            'Global config file $configFile does not exist or cannot be opened';
          else
            'Unable to open file $configFile because $e';
      
    
    this.config =
      try {
        haxe.Json.parse(src);
      }
      catch (e:Dynamic) {
        Sys.stderr().writeString('Invalid JSON in file $configFile:\n\n$src\n\n');
        throw e;
      }
      
    if (config.version == null)
      throw 'No version set in $configFile';
      
    switch config.resolveLibs {
      case Scoped | Mixed | Haxelib:
      case v:
        throw 'invalid value $v for `resolveLibs` in $configFile';
    }
    
    this.resolver = new Resolver(cwd, scopeDir, config.resolveLibs, ['HAXESHIM_LIBCACHE' => '$haxeshimRoot/libs']);
    this.haxeInstallation = getInstallation(config.version);
  }
  
  public function getInstallation(version:String) 
    return new HaxeInstallation('$haxeshimRoot/versions/$version', version, '$haxeshimRoot/libs');
  
  function resolveThroughHaxelib(libs:Array<String>) 
    return 
      switch Exec.eval(haxeInstallation.haxelib, cwd, ['path'].concat(libs), haxeInstallation.env()) {
        case Success({ status: 0, stdout: stdout }):           
          Resolver.parseLines(stdout, function (cp) return ['-cp', cp]);
        case Success({ status: v, stdout: stdout, stderr: stderr }):
          Sys.stderr().writeString(stdout + stderr);//fun fact: haxelib prints errors to stdout
          Sys.exit(v);
          null;
        case Failure(e):
          e.throwSelf();
      }
  
  public function resolve(args:Array<String>) 
    return resolver.resolve(args, resolveThroughHaxelib);
  
  static public function seek(?options:SeekingOptions) {
    if (options == null)
      options = {};
      
    var cwd = switch options.cwd {
      case null: Sys.getCwd();
      case v: v;
    }
    
    var startLookingIn = switch options.startLookingIn {
      case null: cwd;
      case v: v;
    }
    
    var haxeshimRoot = switch options.haxeshimRoot {
      case null: DEFAULT_ROOT;
      case v: v;
    }
    
    var make = Scope.new.bind(haxeshimRoot, _, _, cwd);
      
    function global()
      return make(true, haxeshimRoot);
      
    function dig(cur:String) 
      return
        switch cur {
          case '$_/$CONFIG_FILE'.exists() => true:
            make(false, cur);
          case '/' | '':
            global();
          case _.split(':') => [drive, ''] if (IS_WINDOWS && drive.length == 1):
            global();
          default:
            dig(cur.directory().removeTrailingSlashes());
        }
        
    return dig(startLookingIn.absolutePath().removeTrailingSlashes());
  }
  
  static public var DEFAULT_ROOT(default, null):String =  
    switch Sys.getEnv('HAXESHIM_ROOT') {
      case null | '':
        if (IS_WINDOWS) 
          Sys.getEnv('APPDATA') + '/haxe';
        else 
          '~/haxe';//no idea if this will actually work
      case v:
        v;
    };
  
}