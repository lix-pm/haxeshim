package haxeshim;

import haxeshim.scope.Scope;
import haxeshim.sys.Exec;
import js.Node.*;
import js.node.Buffer;
import js.node.child_process.ChildProcess;
import js.node.net.Server;
import js.node.net.Socket;

using tink.CoreApi;

enum ServerKind {
  Port(num:Int);
  Stdio;
  Connect(hostPort:String);
}

enum FrameState {
  AwaitingHeader(buf:Buffer);
  AwaitingData(buf:Buffer, total:Int);
}

typedef HostPort = {
  var host(default, null):String;
  var port(default, null):Int;
}

/**
 * This beauty exists because we may need to hotswap the running haxe version.
 */
class CompilerServer {

  var scope:Scope;
  var waiting:Promise<Waiting>;
  var lastVersion:String;
  var args:Array<String>;

  var freePort:Promise<Int> = Future.irreversible(function (cb) {
    var test = js.node.Net.createServer();
    test.listen(0, function () {
      var port = test.address().port;
      test.close(function () {
        cb(Success(port));
      });
    });
  });

  public static function extractMode(args:Array<String>):Null<{kind:ServerKind, args:Array<String>}> {
    for (flag in ['--server-listen', '--wait']) {
      var idx = args.indexOf(flag);
      if (idx >= 0 && idx < args.length - 1) {
        var value = args.splice(idx, 2).pop();
        var kind:ServerKind = switch value {
          case 'stdio':
            Stdio;
          case v:
            switch Std.parseInt(v) {
              case null:
                Exec.die(422, 'invalid $flag argument: $value');
              case p:
                Port(p);
            }
        }
        return { kind: kind, args: args };
      }
    }

    var connectIdx = args.indexOf('--server-connect');
    if (connectIdx >= 0 && connectIdx < args.length - 1) {
      var target = args.splice(connectIdx, 2).pop();
      return { kind: Connect(target), args: args };
    }

    return null;
  }

  public function new(kind:ServerKind, scope, args) {
    this.args = args;
    this.scope = scope;

    switch kind {
      case Port(port):
        waitOnPort(port);
      case Stdio:
        stdio();
      case Connect(hostPort):
        serverConnect(hostPort);
    }
  }

  static function parseHostPort(s:String):HostPort {
    var colon = s.lastIndexOf(':');
    if (colon == -1) {
      var port = Std.parseInt(s);
      if (port == null) Exec.die(422, 'Invalid port: $s');
      return { host: '127.0.0.1', port: port };
    }
    var port = Std.parseInt(s.substr(colon + 1));
    if (port == null) Exec.die(422, 'Invalid port in: $s');
    return { host: s.substr(0, colon), port: port };
  }

  static function frame(payload:Buffer):Buffer {
    var ret = Buffer.alloc(4 + payload.length);
    ret.writeInt32LE(payload.length, 0);
    payload.copy(ret, 4);
    return ret;
  }

  function readFrame(socket:Socket):Promise<Buffer> {
    return Promise.irreversible(function (resolve:Buffer->Void, reject:Dynamic->Void) {
      var state = AwaitingHeader(Buffer.alloc(0));
      var onData:Buffer->Void;
      var onError:Dynamic->Void;
      var onClose:Void->Void;

      function cleanupListeners() {
        socket.removeListener('data', onData);
        socket.removeListener('error', onError);
        socket.removeListener('close', onClose);
      }

      onError = function (e:Dynamic) {
        cleanupListeners();
        reject(e);
      };

      onClose = function () onError('socket closed');

      onData = function (chunk:Buffer) {
        state = switch state {
          case AwaitingHeader(buf):
            AwaitingHeader(Buffer.concat([buf, chunk]));
          case AwaitingData(buf, left):
            AwaitingData(Buffer.concat([buf, chunk]), left);
        }

        while (true)
          switch state {
            case AwaitingHeader(buf) if (buf.length >= 4):
              state = AwaitingData(buf.slice(4), buf.readInt32LE(0));
            case AwaitingData(buf, total) if (buf.length >= total):
              cleanupListeners();
              var extra = buf.slice(total);
              if (extra.length > 0)
                @:privateAccess socket.unshift(extra);
              resolve(buf.slice(0, total));
              return;
            default:
              return;
          }
      };

      socket.on('data', onData);
      socket.on('error', onError);
      socket.on('close', onClose);
    });
  }

  function handleIntSignals() {
    //See http://stackoverflow.com/a/31562361/111466

    function cleanExit() process.exit();

    process.on('SIGINT', cleanExit); // catch ctrl-c
    process.on('SIGTERM', cleanExit); // catch kill
  }

  function watchConfig() {
    js.node.Fs.watch(scope.configFile, { persistent: false }, function (_, _) {
      var max = 10;
      function attempt(count = 0) {
        try scope.reload()
        catch (e:Dynamic) {
          if (count >= max) {
            Logger.get().error('Reloading .haxerc after change detected failed $max times!');
            Sys.exit(500);
          }
          else haxe.Timer.delay(attempt.bind(count + 1), 100);
        }
      }
      attempt();
    });
  }

  function connectToHost(host:String, port:Int):Promise<Socket> {
    return Promise.irreversible(function (resolve:Socket->Void, reject:Dynamic->Void) {
      var max = 10;
      function attempt(n:Int) {
        var cnx = js.node.Net.createConnection(port, host);
        cnx
          .on('connect', function () resolve(cnx))
          .on('error', function (e)
            if (n >= max)
              reject('Failed to connect to $host:$port after $max attempts because $e');
            else
              haxe.Timer.delay(attempt.bind(n + 1), 100)
          );
      }
      attempt(1);
    });
  }

  function spawnConnectChild(version:String, port:Int):Promise<{child:ChildProcess, socket:Socket}> {
    return Promise.irreversible(function (resolve, reject) {
      var installation = scope.getInstallation(version);
      var server:Server = null;
      var child:ChildProcess = null;

      function fail(e:Dynamic) {
        if (server != null) server.close();
        if (child != null) child.kill();
        reject(e);
      }

      server = js.node.Net.createServer(function (sock:Socket) {
        server.close();
        resolve({ child: child, socket: sock });
      });

      server.on('error', fail);
      server.listen(port, '127.0.0.1', function () {
        child = js.node.ChildProcess.spawn(
          installation.compiler,
          args.concat(['--server-connect', Std.string(port)]),
          {
            cwd: scope.cwd,
            env: Exec.mergeEnv(installation.env),
            stdio: 'inherit',
          }
        );

        child.on('exit', function (_) fail('haxe exited before connecting'));
        child.on('error', fail);
      });
    });
  }

  function serverConnect(hostPort:String) {
    watchConfig();

    var target = parseHostPort(hostPort);
    var child:ChildProcess = null;
    var haxeSocket:Socket = null;
    var ideSocket:Socket = null;

    function cleanup() {
      if (child != null) child.kill();
      if (haxeSocket != null) haxeSocket.destroy();
      if (ideSocket != null) ideSocket.destroy();
    }

    process.on('exit', cleanup);
    handleIntSignals();

    function ensureHaxe(version:String):Promise<{child:ChildProcess, socket:Socket}> {
      if (child != null && haxeSocket != null && version == lastVersion)
        return Future.sync(Success({ child: child, socket: haxeSocket }));

      if (child != null) child.kill();
      if (haxeSocket != null) haxeSocket.destroy();

      lastVersion = version;

      return freePort.next(function (port) {
        return spawnConnectChild(version, port).next(function (session) {
          child = session.child;
          haxeSocket = session.socket;
          return session;
        });
      });
    }

    function bridge() {
      readFrame(ideSocket).next(function (data):Promise<Noise> {
        var postfix = Buffer.alloc(0);

        var ctx = parseArgs(
          switch data.indexOf(0x01) {
            case -1: data;
            case v:
              postfix = data.slice(v);
              data.slice(0, v);
          }
        );

        return ensureHaxe(ctx.version).next(function (_):Promise<Noise> {
          switch scope.resolve.bind(ctx.args).catchExceptions() {
            case Failure(e):
              Exec.die(e.code, e.message);
              return Future.sync(Success(Noise));
            case Success(resolved):
              var payload = Buffer.concat([Buffer.from(resolved.join('\n')), postfix]);
              haxeSocket.write(frame(payload));
              return readFrame(haxeSocket).next(function (response):Noise {
                ideSocket.write(frame(response));
                bridge();
                return Noise;
              });
          }
        });
      }).handle(function (o) switch o {
        case Failure(_):
          cleanup();
        case Success(_):
      });
    }

    ensureHaxe(scope.haxeInstallation.version).next(function (_) {
      return connectToHost(target.host, target.port);
    }).next(function (sock):Noise {
      ideSocket = sock;
      ideSocket.on('close', cleanup);
      ideSocket.on('end', cleanup);
      bridge();
      return Noise;
    }).handle(function (o) switch o {
      case Failure(e):
        Exec.die(500, Std.string(e));
      case Success(_):
    });
  }

  function stdio() {
    watchConfig();

    var child:ChildProcess = null;

    function quit() {
      if (child != null) child.kill();
    }

    process.on('exit', quit);
    handleIntSignals();

    process.stdin.on('end', quit);
    process.stdin.on('close', quit);

    var state = AwaitingHeader(Buffer.alloc(0));

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

        var hx = scope.getInstallation(ctx.version);
        child = js.node.ChildProcess.spawn(hx.compiler, this.args.concat(['--server-listen', 'stdio']), {
          cwd: scope.cwd,
          env: Exec.mergeEnv(hx.env),
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
          var first = Buffer.from(args.join('\n'));
          child.stdin.write(frame(Buffer.concat([first, postfix])));
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

          var proc = Exec.async(installation.compiler, scope.cwd, this.args.concat(['--server-listen', Std.string(port)]), installation.env);

          return {
            died: Future.irreversible(function (cb) {
              proc.on("exit", cb.bind(Noise));
              proc.on("error", cb.bind(Noise));
              proc.on("disconnect", cb.bind(Noise));
            }),
            version: version,
            socket: () -> Promise.irreversible((resolve, reject) -> {
              var max = 10;
              function connect(attempt:Int) {
                var cnx = js.node.Net.createConnection(port, '127.0.0.1');
                cnx
                  .on('error', function (e)
                    if (attempt >= max)
                      reject(new Error('Failed to connect to 127.0.0.1:$port after $max attempts because $e'));
                    else
                      haxe.Timer.delay(connect.bind(attempt+1), 100)
                  )
                  .on('connect', function () resolve(cnx));
              }
              connect(1);
            }),
            kill: function () {
              proc.kill();
              return Future.delay(500, Noise);
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