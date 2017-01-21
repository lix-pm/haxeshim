package haxeshim;

import js.node.Buffer;
import js.node.net.Socket;
import js.node.stream.Readable;
import js.node.stream.Writable;

using tink.CoreApi;

enum ServerKind {
  Port(num:Int);
  Stdio;
}

/**
 * This beauty exists because we may need to hotswap the running haxe version.
 */
class CompilerServer {
  
  var scope:Scope;
  var waiting:Promise<Waiting>;
  var lastVersion:String;
  
  var freePort:Promise<Int> = Future.async(function (cb) {
    var test = js.node.Net.createServer();
    test.listen(0, function () {
      var port = test.address().port;
      test.close(function () {
        cb(Success(port));
      });
    });          
  });  
  
  function forward(input:IReadable, output:IWritable, options) {
    var buf = [];
      
    input.on('data', function (chunk:Buffer) {
      switch chunk.indexOf(0) {
        case -1:
          trace(chunk);
          buf.push(chunk);
        case v:
          
          buf.push(chunk.slice(0, v));
          input.unshift(chunk.slice(v + 1));
          
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
              compiler.pipe(output, options);
              
            case Failure(e): 
              
              output.end(e.message + '\n' + String.fromCharCode(2) + '\n', 'utf8');
          });
          
      }
    });
    
    input.on('error', function () {});
    
    input.on('end', function () {});    
  }
  
  public function new(kind:ServerKind, scope) {
    this.scope = scope;
    
    switch kind {
      case Port(port):
        var server = js.node.Net.createServer(function (cnx:Socket) {
          forward(cnx, cnx, { end: true } );
        });
        
        server.listen(port);      
      case Stdio:
        forward(js.Node.process.stdin, js.Node.process.stderr, { end: false });
    }
  }
  
  function disconnect():Promise<Noise>
    return 
      if (waiting == null) 
        Future.sync(Success(Noise));
      else 
        waiting.next(function (w) return w.kill());
  
  function connect(version:String):Surprise<Socket, Error> {          
    
    if (version != lastVersion || waiting == null) {
      lastVersion = version;
      var nu = waiting = disconnect().next(function (_) {
        return freePort.next(function (port):Waiting {
          var installation = scope.getInstallation(version);
          
          var proc = Exec.async(installation.compiler, scope.cwd, ['--wait', Std.string(port)], installation.env());
          
          return {
            died: Future.async(function (cb) {
              proc.on("exit", cb.bind(Noise));
              proc.on("error", cb.bind(Noise));
              proc.on("disconnect", cb.bind(Noise));
            }),
            version: version,
            socket: function () 
              return js.node.Net.createConnection(port, '127.0.0.1'),
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
  function socket():Socket;
  function kill():Future<Noise>;
}