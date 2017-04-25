package haxeshim;
import haxe.DynamicAccess;

using sys.io.File;
using sys.FileSystem;
using StringTools;
using haxe.io.Path;
using haxe.Json;

typedef SeekingOptions = {
  @:optional var cwd(default, null):String;
  @:optional var startLookingIn(default, null):String;
  @:optional var haxeshimRoot(default, null):String;
}

class Scope {
  
  static var CONFIG_FILE = '.haxerc';
  /**
   * The root directory for haxeshim as configured when the scope was created
   */
  public var haxeshimRoot(default, null):String;
  
  /**
   * Directory where libraries can be cached.
   */
  public var libCache(default, null):String;
  /**
   * The directory that contains the different Haxe versions
   */
  public var versionDir(default, null):String;
  /**
   * Indicates whether the scope is global
   */
  public var isGlobal(default, null):Bool;
  
  /**
   * The directory of the scope, where the `.haxerc` file was found and also where the `.scopedHaxeLibs` directory is expected
   */
  public var scopeDir(default, null):String;
  /**
   * The directory where metadata about the scoped directories is to be found.
   */
  public var scopeLibDir(default, null):String;
  
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
  
  /**
   * The global haxelib repo on which haxelib operates.
   */
  public var haxelibRepo(default, null):String;
  
  /**
   * The data read from the config file.
   */
  public var config(default, null):Config;
  
  public var haxeInstallation(default, null):HaxeInstallation;
      
  var resolver:Resolver;
  
  function new(haxeshimRoot, isGlobal, scopeDir, cwd) {
    
    this.haxeshimRoot = haxeshimRoot;
    this.isGlobal = isGlobal;
    this.scopeDir = scopeDir;
    this.scopeLibDir = '$scopeDir/haxe_libraries';
    this.cwd = cwd;
    
    configFile = '$scopeDir/$CONFIG_FILE';
      
    this.versionDir = '$haxeshimRoot/versions';
    this.haxelibRepo = '$haxeshimRoot/haxelib';
    this.libCache = '$haxeshimRoot/haxe_libraries';
    reload();
  }
  
  public function reload() {
    var src = 
      try configFile.getContent()
      catch (e:Dynamic) 
        throw 
          if (isGlobal)
            'Global config file $configFile does not exist or cannot be opened';
          else
            'Unable to open file $configFile because $e';
    this.config =
      try src.parse()
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
    
    this.haxeInstallation = getInstallation(config.version);
    this.resolver = new Resolver(cwd, scopeLibDir, config.resolveLibs, getDefault);
    
  }

  public function getDefault(variable:String)
    return switch variable {
      case 'HAXESHIM_LIBCACHE': libCache;
      default: null;
    }
  
  public function delete() 
    this.configFile.deleteFile();
  
  static public function create(at:String, config:Config) 
    '$at/$CONFIG_FILE'.saveContent(config.stringify());
  
  static public function exists(at:String)
    return '$at/$CONFIG_FILE'.exists();
  
  public function reconfigure(changed:Config) {
    
    for (f in Reflect.fields(changed))
      Reflect.setField(config, f, Reflect.field(changed, f));
    
    configFile.saveContent(config.stringify('  '));
  }
  
  public function getInstallation(version:String) 
    return new HaxeInstallation('$versionDir/$version', version, haxelibRepo, '$haxeshimRoot/neko');//TODO: the neko path probably should not be hardcoded
  
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
      
  public function getInstallationInstructions() {
    
    var missing = [],
        instructions = [];
        
    for (child in scopeLibDir.readDirectory()) {
      var path = '$scopeLibDir/$child';
      if (!path.isDirectory() && path.endsWith('.hxml')) {
        var hxml = path.getContent();
        var args = Resolver.parseLines(hxml);
        var pos = 0,
            max = args.length;
        while (pos < max)
          switch args[pos++] {
            case '-cp':
              var cp = Resolver.interpolate(args[pos++], getDefault);
              
              if (!cp.exists()) {
                switch hxml.split('@install:') {
                  case [v]:
                    missing.push({
                      lib: child,
                      cp: cp,
                    });
                  case _.slice(1) => a:
                    for (i in a)
                      instructions.push(i.split('\n')[0].trim());
                }
              }
            default:
          }
      }
    }
    
    return {
      missing: missing,
      instructions: instructions,
    }
  }
  
  public function resolve(args:Array<String>):Array<String>
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
          case _.split(':') => [drive, ''] if (Os.IS_WINDOWS && drive.length == 1):
            global();
          default:
            dig(cur.directory().removeTrailingSlashes());
        }
        
    return dig(startLookingIn.absolutePath().removeTrailingSlashes());
  }
  
  static public var DEFAULT_ROOT(default, null):String =  
    switch Sys.getEnv('HAXESHIM_ROOT') {
      case null | '':
        Sys.getEnv(
          if (Os.IS_WINDOWS) 'APPDATA'
          else 'HOME'
        ) + '/haxe';//relying on env variables is always rather brave, but let's try this for now
      case v:
        v;
    };
  
}