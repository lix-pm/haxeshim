package haxeshim;

using tink.CoreApi;

class HaxeCli {
    
  static function die(code, reason):Dynamic {
    Sys.stderr().writeString('$reason\n');
    Sys.exit(code);    
    return throw 'unreachable';
  }
  static function gracefully<T>(f:Void->T) 
    return 
      try f()
      catch (e:Error) 
        die(e.code, e.message)
      catch (e:Dynamic) 
        die(500, Std.string(e));
    
  static function main() 
    switch Sys.args() {
      case ['--wait', 'stdio']:
        
        new CompilerServer(Stdio, Scope.seek());
        
      case ['--wait', Std.parseInt(_) => port]:
        
        new CompilerServer(Port(port), Scope.seek());
      
      case ['--run', 'install-libs']:
        
        var scope = gracefully(Scope.seek.bind());
        
        var i = scope.getInstallationInstructions();
        
        var code = 0;
        
        switch i.missing {
          case []:
          case v:
            code = 404;
            for (m in v)
              Sys.stderr().writeString('${m.lib} has no install instruction for missing classpath ${m.cp}\n');
        }
        
        for (cmd in i.instructions) 
          switch Exec.shell(cmd, Sys.getCwd()) {
            case Failure(e):
              code = e.code;
            default:
          }
        
        Sys.exit(code);
        
      case args:
        
        var scope = gracefully(Scope.seek.bind());
        
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
        Sys.exit(gracefully(Exec.sync(scope.haxeInstallation.compiler, scope.cwd, gracefully(scope.resolve.bind(args)), scope.haxeInstallation.env()).sure));
    }
  
  
}

