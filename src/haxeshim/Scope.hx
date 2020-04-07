package haxeshim;

import haxeshim.Args;
import haxeshim.Errors;
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

  var logger = Logger.get(false);

  public function withLogger<T>(logger:Logger, f:Void->T):T {
    var old = this.logger;
    this.logger = logger;
    return Error.tryFinally(
      f,
      () -> this.logger = old
    );
  }

  public function installLibs():Promise<Noise>
    return Attempt.to('install libraries', function () {
      var i = getInstallationInstructions();

      var code = 0;

      switch i.missing {
        case []:
        case v:
          code = 404;
          for (m in v)
            logger.error('${m.lib} has no install instruction for missing classpath ${m.cp}\n');
      }

      var total = i.instructions.install.length + i.instructions.postInstall.length,
          cur = 0,
          installed = 0;

      for (cmds in [i.instructions.install, i.instructions.postInstall])
        for (cmd in cmds) {
          logger.progress('[${++cur}/${total}] $cmd');

          switch Exec.shell(cmd, Sys.getCwd()) {
            case Failure(e):
              code = e.code;
            default:
              installed++;
          }
        }

      var libs =
        if (total == 1) 'library'
        else 'libraries';

      if (code != 0)
        throw new Error(code, 'Failed to install ${total - installed}/$total $libs.');
      else if (total > 0)
        logger.success('Installed $total $libs.');
      return Noise;
    });

  function new(haxeshimRoot, isGlobal, scopeDir, cwd) {

    this.haxeshimRoot = haxeshimRoot;
    this.isGlobal = isGlobal;
    this.scopeDir = scopeDir;
    this.scopeLibDir = '$scopeDir/haxe_libraries';
    this.cwd = cwd;

    configFile = '$scopeDir/$CONFIG_FILE';

    this.versionDir = '$haxeshimRoot/versions';
    this.haxelibRepo = '$haxeshimRoot/haxelib';
    this.libCache = switch [Sys.getEnv('HAXESHIM_LIBCACHE'), Sys.getEnv(LIBCACHE)] {
      case [null, null]: '$haxeshimRoot/haxe_libraries';
      case [null, v] | [v, _]: v;
    }
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
  }

  public function getVar(variable:String)
    return switch Sys.getEnv(variable) {
      case null | '': getDefault(variable);
      case v: v;
    }

  public function getDefault(variable:String)
    return switch variable {
      case 'HAXESHIM_LIBCACHE' | LIBCACHE: libCache;
      case 'SCOPE_DIR': scopeDir;
      case 'CWD': cwd;
      default: null;
    }

  public function delete()
    this.configFile.deleteFile();

  static public function create(at:String, config:Config)
    return Fs.save('$at/$CONFIG_FILE', config.stringify('  '));

  static public function exists(at:String)
    return '$at/$CONFIG_FILE'.exists();

  public function reconfigure(changed:Config)
    return
      Fs.save(configFile, changed.stringify('  '))
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

  function resolveThroughHaxelib(libs:Array<Arg>)
    return
      switch Exec.eval(haxeInstallation.haxelib, cwd, ['path'].concat([for (l in libs) l.val]), haxeInstallation.env()) {
        case Success({ status: 0, stdout: stdout }):
          Args.fromMultilineString(stdout, 'haxelib path', getVar, true);
        case Success(new Error(_.status, _.stdout + _.stderr) => e) | Failure(e):
          var r = new Errors();
          r.fail(e.message, Custom('haxelib path'), e.code);
          r.produce([]);// perhaps return the libs again?
      }

  public function interpolate(value:String, ?extra:String->Null<String>)
    return Args.interpolate(value, switch extra {
      case null: getVar;
      case fn: s -> switch fn(s) {
        case null: getVar(s);
        case v: v;
      }
    }).sure();

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
              }).push(interpolate(content.substr(v + 1).ltrim()));
          }
      }
    return ret;
  }

  public function libHxml(lib:String)
    return '$scopeLibDir/$lib.hxml';

  public function getDirectives(lib:String):Promise<Map<String, Array<String>>>
    return Fs.get(libHxml(lib))
      .next(parseDirectives);

  public function getLibCommand(args:Array<String>) {
    args = [for (a in args) interpolate(a)];
    var lib = args.shift();
    return
      getDirectives(lib)
        .next(function (d) return switch d['run'] {
          case null | []: new Error('no @run directive found for library $lib');
          case [cmd]:
            return Exec.shell.bind([interpolate(cmd)].concat(
              args.map(if (Os.IS_WINDOWS) haxe.SysTools.quoteWinArg.bind(_, true) else haxe.SysTools.quoteUnixArg)
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
          var args =
            switch Args.fromMultilineString(hxml, path, getVar) {
              case Success(args) | Failure({ result: args }):
                [for (a in args) a.val];
            }
          var pos = 0,
              max = args.length;
          while (pos < max)
            switch args[pos++] {
              case '-cp' | '-p' | '--class-path':
                var cp = args[pos++];

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
                            instructions.postInstall.push(i);
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

  public function resolveArgs(build:Args) {
    var cwd = this.cwd;

    function resolvePath(p:String)
      return
        if (p.isAbsolute()) p;
        else Path.join([cwd, p]);

    cwd = resolvePath(build.cwd);

    var out = [],
        haxelibs = [],
        errors = new Errors(),
        args = [],
        special = [],
        runArgs = [];

    {
      var i = 0;
      while (i < build.args.length) {
        var arg = build.args[i++];
        switch arg.val {
          case '--wait':
            special.push(arg);
          case '--connect' | '--display' | '--server-listen' | '--server-connect':
            special.push(arg);
            switch build.args[i++] {
              case null: errors.fail('${arg.val} requires argument', arg.pos);
              case v: special.push(v);
            }
          case '--run':
            runArgs = build.args.slice(i - 1);
            break;
          default:
            args.push(arg);
        }
      }
    }

    var libs = new Map();

    while (args.length > 0) {
      var arg = args.shift();

      function fail(msg:String)
        errors.fail(msg, arg.pos);

      switch arg.val {
        case '-lib', '--lib', '-L':
          switch args.shift() {
            case null:
              fail('-lib requires argument');
            case lib:
              if (!libs[lib.val]) {
                libs[lib.val] = true;
                switch config.resolveLibs {
                  case Haxelib: haxelibs.push(lib);
                  case _ == Mixed => mixed:
                    var file = libHxml(lib.val);
                    var content =
                      try Success(file.getContent())
                      catch (e:Dynamic) Failure('could not get contents of $file because $e');

                    switch content {
                      case Success(raw):
                        args = errors.getResult(Args.fromMultilineString(raw, file, getVar)).concat(args);
                      case Failure(e):
                        if (file.exists()) fail(e);
                        else if (mixed) haxelibs.push(lib);
                        else fail('-lib ${lib.val} is missing $file');
                    }
                }
              }
          }
        case forbidden = '--next' | '--each' | '--connect' | '--wait' | '--cwd' | '-C' | '--run':
          fail('$forbidden not allowed here');
          break;
        default:
          out.push(arg);
      }
    }

    out = special
      .concat(out)
      .concat(errors.getResult(resolveThroughHaxelib(haxelibs)))
      .concat(runArgs);

    return errors.produce(@:privateAccess new ResolvedArgs(cwd, out));
  }

  static final fs = {
    isDirectory: function (path:String) return try FileSystem.isDirectory(path) catch (e:Dynamic) false,
    readFile: function (path:String) return try Success(path.getContent()) catch (e:Dynamic) Failure('Cannot read $path because $e'),
  }

  public function getBuilds(args:Array<String>) {

    var errors = new Errors();

    return
      errors.produce([
        for (build in errors.getResult(Args.split(args, cwd, fs, getVar)))
          if (build.args.length > 0)
            resolveArgs(build)
      ]);
  }

  @:deprecated public function resolve(args:Array<String>) {

    var ret = [],
        errors = new Errors();

    for (build in errors.getResult(Args.split(args, cwd, fs, getVar)))
      if (build.args.length > 0) {
        if (ret.length != 0)
          ret.push('--next');

        if (build.cwd != cwd) {
          ret.push('--cwd');
          ret.push(build.cwd);
        }

        for (arg in errors.getResult(resolveArgs(build)).args)
          ret.push(arg.val);
      }

    switch errors.produce(42) {
      case Failure(_.errors[0] => e):
        Sys.println(e.message);
        Sys.exit(switch e.code { case null: 500; case v: v; });
      default:
    }

    return ret;
  }

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

class ResolvedArgs extends Args {

  function resolve(path:String)
    return
      if (path.isAbsolute()) path
      else Path.join([cwd, path]);

  public function checkClassPaths() {

    var errors = new Errors();

    for (i in 0...args.length) switch args[i].val {
      case '-cp' | '-p' | '--class-path' if (i + 1 < args.length):
        var cp = args[i + 1];
        try
          cp.val.readDirectory()
        catch (e:Dynamic)
          errors.fail('classpath ${cp.val} is not a directory or cannot be read from', cp.pos);
      default:
    }

    return errors.produce(Noise);
  }
}