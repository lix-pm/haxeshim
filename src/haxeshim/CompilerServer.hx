package haxeshim;

import js.Node.*;
import js.node.Buffer;
import js.node.child_process.ChildProcess;
import js.node.net.Socket;
import js.node.stream.Readable;
import js.node.stream.Writable;

using tink.CoreApi;

enum ServerKind {
  Port(num:Int);
  Stdio;
}

enum StdioState {
  AwaitingHeader(buf:Buffer);
  AwaitingData(buf:Buffer, total:Int);
}

/**
 * This beauty exists because we may need to hotswap the running haxe version.
 */
class CompilerServer {

  var scope:Scope;
  var waiting:Promise<Waiting>;
  var lastVersion:String;
  var args:Array<String>;

  var freePort:Promise<Int> = Future.async(function (cb) {
    var test = js.node.Net.createServer();
    test.listen(0, function () {
      var port = test.address().port;
      test.close(function () {
        cb(Success(port));
      });
    });
  }, true);

  public function new(kind:ServerKind, scope, args) {
    this.args = args;
    this.scope = scope;

    switch kind {
      case Port(port):
        waitOnPort(port);
      case Stdio:
        stdio();
    }
  }

  function handleIntSignals() {
    //See http://stackoverflow.com/a/31562361/111466

    function cleanExit() process.exit();

    process.on('SIGINT', cleanExit); // catch ctrl-c
    process.on('SIGTERM', cleanExit); // catch kill
  }

  function stdio() {

    js.node.Fs.watch(scope.configFile, { persistent: false }, function (_, _) {
      scope.reload();
    });

    var child:ChildProcess = null;

    function quit() {
      if (child != null) child.kill();
    }

    process.on('exit', quit);
    handleIntSignals();

    process.stdin.on('end', quit);
    process.stdin.on('close', quit);

    var state = AwaitingHeader(Buffer.alloc(0));

    function frame(payload:Buffer) {
      var ret = Buffer.alloc(4 + payload.length);
      ret.writeInt32LE(payload.length, 0);
      payload.copy(ret, 4);
      return ret;
    }

    function processData(data:Buffer) {

      var postfix = Buffer.alloc(0);

      var ctx =
        parseArgs(
          switch data.indexOf(0x01) {
            case -1:
              data;
            case v:
              postfix = data.slice(v);
              data.slice(0, v);
          }
        );


      if (child == null || ctx.version != lastVersion) {
        if (child != null) {
          child.kill();
          child.stdout.unpipe(process.stdout);
          child.stderr.unpipe(process.stderr);
        }

        lastVersion = ctx.version;

        var hx = scope.haxeInstallation;
        child = js.node.ChildProcess.spawn(hx.compiler, this.args.concat(['--wait', 'stdio']), {
          cwd: scope.cwd,
          env: Exec.mergeEnv(hx.env()),
          stdio: 'pipe',
        });

        var old = child;
        child.on(ChildProcessEvent.Exit, function (code, _) {
          if (child == old) child = null;
        });

        child.stdout.pipe(process.stdout);
        child.stderr.pipe(process.stderr);
      }

      switch scope.resolve.bind(ctx.args).catchExceptions() {
        case Failure(e):
          Exec.die(e.code, e.message);
        case Success(args):
          // var first = Buffer.from(HaxeCli.checkClassPaths(args).join('\n'));
          // child.stdin.write(frame(Buffer.concat([first, postfix])));
      }

    }

    function reduce() {
      while (true) {
        var next =
          switch state {
            case AwaitingHeader(buf) if (buf.length >= 4):
              AwaitingData(buf.slice(4), buf.readInt32LE(0));
            case AwaitingData(buf, total) if (buf.length >= total):
              processData(buf.slice(0, total));
              AwaitingHeader(buf.slice(total));
            default:
              state;
          }

        if (state == next) break;
        state = next;
      }
    }

    process.stdin.on('data', function (chunk:Buffer) {
      state = switch state {
        case AwaitingHeader(buf):
          AwaitingHeader(Buffer.concat([buf, chunk]));
        case AwaitingData(buf, left):
          AwaitingData(Buffer.concat([buf, chunk]), left);
      }
      reduce();
    });
  }

  function parseArgs(raw:Buffer) {
    var args = raw.toString().split('\n');

    var version =
      switch args.indexOf('--haxe-version') {
        case -1:
          if (lastVersion == null)
            scope.haxeInstallation.version;
          else
            lastVersion;
        case v:
          args.splice(v, 2).pop();
      }

    return {
      version: version,
      args: args,
    }
  }

  function waitOnPort(port:Int) {
    function quit() {
        if (waiting != null) {
            waiting.handle(function (o) switch o {
                case Success(w): w.kill();
                case _:
            });
        }
    }

    process.on('exit', quit);
    handleIntSignals();

    var server = js.node.Net.createServer(function (cnx:Socket) {
      var buf = [];

      cnx.on('data', function (chunk:Buffer) {
        switch chunk.indexOf(0) {
          case -1:
            buf.push(chunk);
          case v:

            buf.push(chunk.slice(0, v));
            cnx.unshift(chunk.slice(v + 1));

            var args = Buffer.concat(buf).toString().split('\n');
            buf = [];
            var version =
              switch args.indexOf('--haxe-version') {
                case -1:
                  if (lastVersion == null)
                    scope.haxeInstallation.version;
                  else
                    lastVersion;
                case v:
                  args.splice(v, 2).pop();
              }

            connect(version).handle(function (o) switch o {
              case Success(compiler):

                compiler.write(args.join('\n') + String.fromCharCode(0));
                compiler.pipe(cnx, { end: true });

              case Failure(e):

                cnx.end(e.message + '\n' + String.fromCharCode(2) + '\n', 'utf8');
            });

        }
      });

      cnx.on('error', function () {});

      cnx.on('end', function () {});
    });
    server.listen(port);
  }

  function disconnect():Promise<Noise>
    return
      if (waiting == null)
        Future.sync(Success(Noise));
      else
        waiting.next(function (w) return w.kill());

  function connect(version:String):Promise<Socket> {

    if (version != lastVersion || waiting == null) {
      lastVersion = version;
      var nu = waiting = disconnect().next(function (_) {
        return freePort.next(function (port):Waiting {
          var installation = scope.getInstallation(version);

          var proc = Exec.async(installation.compiler, scope.cwd, this.args.concat(['--wait', Std.string(port)]), installation.env());

          return {
            died: Future.async(function (cb) {
              proc.on("exit", cb.bind(Noise));
              proc.on("error", cb.bind(Noise));
              proc.on("disconnect", cb.bind(Noise));
            }),
            version: version,
            socket: function () return Future.async(function (cb) {
              var max = 10;
              function connect(attempt:Int) {
                var cnx = js.node.Net.createConnection(port, '127.0.0.1');
                cnx
                  .on('error', function (e)
                    if (attempt >= max)
                      cb(Failure(new Error('Failed to connect to 127.0.0.1:$port after $max attempts because $e')))
                    else
                      haxe.Timer.delay(connect.bind(attempt+1), 100)
                  )
                  .on('connect', function () cb(Success(cnx)));
              }
              connect(1);
            }),
            kill: function () {
              proc.kill();
              return Future.async(function (cb) haxe.Timer.delay(cb.bind(Noise), 500));
            }
          }
        });
      });

      waiting.handle(function (o) switch o {
        case Success(w):
          w.died.handle(function () {
            if (waiting == nu)
              waiting = null;
          });
        case Failure(_):
          waiting = null;
      });
    }

    return waiting.next(function (w:Waiting) return w.socket());
  }
}

private typedef Waiting = {
  var died(default, null):Future<Noise>;
  var version(default, null):String;
  function socket():Promise<Socket>;
  function kill():Future<Noise>;
}