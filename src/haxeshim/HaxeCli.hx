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

  static public function exec<T>(fn:Array<String>->T) {
    var args = Sys.args();
    if (args[0] == '--cwd') {
      args.shift();
      switch args.shift() {
        case null: die(500, '--cwd requires argument');
        case v: Sys.setCwd(v);
      }
    }
    return fn(args);
  }

  static function main() {
    Neko.setEnv();
    exec(new HaxeCli(gracefully(Scope.seek.bind())).dispatch);
  }

  public function installLibs(silent:Bool)
    return scope.withLogger(Logger.get(silent), scope.installLibs)
      .handle(
        function (o) switch o {
          case Failure(e):
            Logger.get().error(e.message);
            Sys.exit(e.code);
          default:
        }
      );

  function dispatch(args:Array<String>) {

    function getScope()
      return gracefully(Scope.seek.bind({ cwd: null }));

    switch args {
      case _.indexOf('--wait') => wait if (wait >=0 && wait < args.length - 1):

        new CompilerServer(
          switch args.splice(wait, 2).pop() {
            case 'stdio': Stdio;
            case Std.parseInt(_) => port: Port(port);
          },
          getScope(),
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

        switch scope.haxeInstallation.compiler {
          case haxe if (haxe.exists()):

            function get<A>(r:haxeshim.Errors.Result<A>)
              return
                switch r {
                  case Success(ret): ret;
                  case Failure({ errors: errors }):
                    dieFromErrors(errors);
                }

            function callHaxe(args, cwd)
              switch Exec.sync(haxe, cwd, args, scope.haxeInstallation.env()) {
                case Success(0):
                case Success(c):
                  die(c);
                case Failure(e):
                  die(e.code, e.message);
              }

            if (args.length == 0)
              callHaxe(args, scope.cwd);
            else
              for (result in get(scope.getBuilds(args))) {
                var build = get(result);

                get(build.checkClassPaths());
                callHaxe([for (a in build.args) a.val], build.cwd);
              }
          case path:
            die(404, 'haxe compiler not found at the expected location "$path"');
        }
    }
  }

}

