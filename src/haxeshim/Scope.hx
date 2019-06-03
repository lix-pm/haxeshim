package haxeshim;

using sys.io.File;
using sys.FileSystem;
using StringTools;
using tink.CoreApi;
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
    setConfig(
      try src.parse()
      catch (e:Dynamic) {
        Sys.stderr().writeString('Invalid JSON in file $configFile:\n\n$src\n\n');
        throw e;
      }
    );
  }

  function setConfig(config:Config) {
    if (config.version == null)
      throw 'No version set in $configFile';

    if (config.resolveLibs == null)
      @:privateAccess config.resolveLibs = if (isGlobal) Mixed else Scoped;

    switch config.resolveLibs {
      case Scoped | Mixed | Haxelib:
      case v:
        throw 'invalid value $v for `resolveLibs` in $configFile';
    }

    this.config = config;
    this.haxeInstallation = getInstallation(config.version);
    this.resolver = new Resolver(cwd, scopeLibDir, config.resolveLibs, getDefault);
  }

  public function getDefault(variable:String)
    return switch variable {
      case 'HAXESHIM_LIBCACHE' | LIBCACHE: libCache;
      case 'SCOPE_DIR': scopeDir;
      default: null;
    }
  
  public function delete() 
    this.configFile.deleteFile();
  
  static public function create(at:String, config:Config) 
    return Fs.save('$at/$CONFIG_FILE', config.stringify());
  
  static public function exists(at:String)
    return '$at/$CONFIG_FILE'.exists();
  
  public function reconfigure(changed:Config)     
    return 
      Fs.save(configFile, config.stringify('  '))
        .next(function (n) {
          setConfig(changed);
          return n;
        });

  public function withResolution(r:LibResolution) 
    return 
      if (config.resolveLibs == r) this;
      else {
        var ret = new Scope(haxeshimRoot, isGlobal, scopeDir, cwd);
        ret.setConfig({ version: config.version, resolveLibs: r });
        ret;
      }
  
  function path(v:String)
    return 
      if (v.isAbsolute()) Some(v);
      else if (v.startsWith('./') || v.startsWith('../')) Some('$cwd/$v');
      else None;

  public function getInstallation(version:String) 
    return 
      switch path(version) {
        case Some(path):
          new HaxeInstallation(path, version, haxelibRepo);
        case None:
          new HaxeInstallation('$versionDir/$version', version, haxelibRepo);
      }
  
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

  public function interpolate(value:String)
    return Resolver.interpolate(value, getDefault);

  function parseDirectives(raw:String) {
    var ret = new Map();
    for (line in raw.split('\n').map(StringTools.trim))
      if (line.startsWith('#')) {
        var content = line.substr(1).ltrim();
        if (content.startsWith('@'))
          switch content.indexOf(':') {
            case -1:
            case v:
              var name = content.substring(1, v);
              (switch ret[name] {
                case null: ret[name] = [];
                case v: v;
              }).push(content.substr(v + 1).ltrim());
          }
      }
    return ret;
  }

  public function getDirectives(lib:String)
    return Fs.get(Resolver.libHxml(scopeLibDir, lib))
      .next(parseDirectives);

  public function getLibCommand(args:Array<String>) {
    args = args.map(interpolate);
    var lib = args.shift();    
    return 
      getDirectives(lib)
        .next(function (d) return switch d['run'] {
          case null | []: new Error('no @run directive found for library $lib');
          case [cmd]: 
            return Exec.shell.bind([interpolate(cmd)].concat(
              args.map(if (Os.IS_WINDOWS) StringTools.quoteWinArg.bind(_, true) else StringTools.quoteUnixArg)
            ).join(' '), Sys.getCwd(), haxeInstallation.env());
          default: new Error('more than one @run directive for library $lib'); 
        });
  }
  
  public function getInstallationInstructions() {
    
    var missing = [],
        instructions = {
          install: [],
          postInstall: [],
        }
    
    if(scopeLibDir.exists())
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
                var cp = interpolate(args[pos++]);
                
                if (!cp.exists()) {
                  var dir = parseDirectives(hxml);
                  switch dir[INSTALL] {
                    case null | []:
                      missing.push({
                        lib: child,
                        cp: cp,
                      });
                    case v:
                      for (i in v) 
                        instructions.install.push(i);
                      switch dir[POST_INSTALL] {
                        case null:
                        case v:
                          for (i in v)
                            instructions.postInstall.push(interpolate(i));
                      }
                  }
                  pos = max;//at this point either the classpath is missing or all install directives are already added to results
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

  static public inline var INSTALL = 'install';
  static public inline var POST_INSTALL = 'post-install';
  
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
        
    var ret = switch Fs.findNearest(CONFIG_FILE, startLookingIn.absolutePath()) {
      case Some(v): make(false, v.directory());
      case None: make(true, haxeshimRoot);
    }
    ret.reload();
    return ret;
  }

  static function env(s:String)
    return switch Sys.getEnv(s) {
      case null | '': None;
      case v: Some(v);
    }

  static public inline var LIBCACHE = 'HAXE_LIBCACHE';
  
  static public var DEFAULT_ROOT(default, null):String =  
    env('HAXE_ROOT').or(
      env('HAXESHIM_ROOT').or(
        Sys.getEnv(
          if (Os.IS_WINDOWS) 'APPDATA'
          else 'HOME'
        ) + '/haxe'//relying on env variables is always rather brave, but let's try this for now
      )
    );
  
}