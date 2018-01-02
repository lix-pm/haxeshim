package haxeshim;

import haxeshim.Exec.*;
using StringTools;
using sys.FileSystem;
using tink.CoreApi;

class HaxeCli {

  var scope:Scope;
        
  public function new(scope) {
    this.scope = scope;    
  }
  
  static function main() {
    Neko.setEnv();
    new HaxeCli(gracefully(Scope.seek.bind())).dispatch(Sys.args()); 
  }
  
  public function installLibs(silent:Bool) {
    var i = scope.getInstallationInstructions();
        
    var code = 0;
    
    switch i.missing {
      case []:
      case v:
        code = 404;
        for (m in v)
          Sys.stderr().writeString('${m.lib} has no install instruction for missing classpath ${m.cp}\n');
    }
    
    for (cmds in [i.instructions.install, i.instructions.postInstall])
      for (cmd in cmds) {
        if (!silent)
          Sys.println(cmd);
        switch Exec.shell(cmd, Sys.getCwd()) {
          case Failure(e):
            code = e.code;
          default:
        }
      }
    
    Sys.exit(code);    
  }
  
  
  static public function checkClassPaths(args:Array<String>) {
    var i = 0;
    var invalid = [];
    while (i < args.length)
      switch args[i++] {
        case '-cp':
          var cp = args[i++];
          try cp.readDirectory()
          catch (e:Dynamic) invalid.push('classpath $cp is not a directory or cannot be read from');
        default:
      }
      
    switch invalid {
      case []:
      case v:
        die(404, invalid.join('\n'));
    }
    return args;
  }
  
  function dispatch(args:Array<String>) {
    
    var cwd = 
      switch args.indexOf('--cwd') {
        case -1:
          null;
        case v:
          args[v+1] = js.node.Path.resolve(args[v+1]);
      }

    function getScope()
      return gracefully(Scope.seek.bind({ cwd: cwd }));

    switch args {
      case _.indexOf('--wait') => wait if (wait >=0 && wait < args.length - 1):

        new CompilerServer(
          switch args.splice(wait, 2).pop() {
            case 'stdio': Stdio;
            case Std.parseInt(_) => port: Port(port);
          },
          Scope.seek(),
          args
        );
        
      case _.slice(0, 2) => ['--run', haxeShimExtension] if (haxeShimExtension.indexOf('-') != -1 && haxeShimExtension.toLowerCase() == haxeShimExtension):
        
        var args = args.slice(2);
        var scope = getScope();
        
        switch haxeShimExtension {
          case 'install-libs':
            
            installLibs(switch args {
              case ['--silent']: true;
              case []: false;
              default: die(422, 'unexpected arguments $args');
            });
            
          case 'resolve-args':
            
            Sys.println(gracefully(scope.resolve.bind(args)).join('\n'));
            Sys.exit(0);
            
          case 'show-version':
            
            if (args.length > 0)
              die(422, 'too many arguments');
            
            var version = 
              switch Exec.eval(scope.haxeInstallation.compiler, scope.cwd, ['-version']) {
                case Success(v):
                  (v.stdout.toString() + v.stderr.toString()).trim();
                case Failure(e):
                  die(e.code, e.message);
              }
            
            Sys.println('-D haxe-ver=$version');
            Sys.println('-cp ${scope.haxeInstallation.stdLib}');
            
          case v:
            die(404, 'Unknown extension $v');
        }
        
      case args:

        var scope = getScope();
        
        switch [args.indexOf('--connect'), args.indexOf('--haxe-version')] {
          case [ -1, -1]:
          case [ _, -1]: 
            /**
             * TODO: in this case there are two possible optimizations:
             * 
             * 1. Connect to the server directly (protocol seems easy enough)
             * 2. Leave the version determination to the server side, because it is already running
             */
            args.push('--haxe-version');
            args.push(scope.haxeInstallation.version);
          default:
        }
        Sys.exit(gracefully(Exec.sync(scope.haxeInstallation.compiler, scope.cwd, checkClassPaths(gracefully(scope.resolve.bind(args))), scope.haxeInstallation.env()).sure));
    }
  }
  
}

