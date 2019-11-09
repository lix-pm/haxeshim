package haxeshim;

import haxe.io.Path.*;
using tink.CoreApi;
using StringTools;

class HaxeArgs {
  static function toArray<T>(c:Cons<T>) {
    var ret = [];

    while (true)
      switch c {
        case N: break;
        case P(h, t):
          c = t;
          ret.push(h);
      }

    ret.reverse();
      
    return ret;
  }

  static function ofArray<T>(a:Array<T>):Cons<T> {
    var ret = N;
    for (i in 0...a.length)
      ret = P(a[a.length - i - 1], ret);
    return ret;
  }

  static public function parse(args:Array<String>, cwd:String, readFile:String->Outcome<String, String>) {

    var each_params = [],
        ret = [];

    function flush(args) {
      ret.push(each_params.concat(args));
    }

    function loop(acc:Cons<String>, args:Cons<String>) switch args {
      case N:
        flush(toArray(acc));
      case P('--next', l) if (acc == N):
        loop(N, l);
      case P('--next', l):
        flush(toArray(acc));
        loop(N, l);
      case P("--each", l):
        each_params = toArray(acc);
        loop(N, l);
      case P("--cwd" | '-C', P(dir, l)):
        cwd = 
          if (isAbsolute(dir)) dir;
          else join([cwd, dir]);
        loop(acc, l);
      case P('--connect', P(hp, l)):
        // loop(acc, l);
        throw 'not implemented';
        // (match CompilationServer.get() with
        // | None ->
        //   let host, port = (try ExtString.String.split hp ":" with _ -> "127.0.0.1", hp) in
        //   do_connect host (try int_of_string port with _ -> raise (Arg.Bad "Invalid port")) ((List.rev acc) @ l)
        // | Some _ ->
        //   (* already connected : skip *)
        //   loop acc l)
      case P("--run", P(cl, args)):
        
        flush(toArray(acc).concat(['--run', cl]).concat(toArray(args)));

      case P(arg, l):
        if (extension(arg) == 'hxml')
          throw 'not implemented';
        else
          loop(P(arg, acc), l);
    }

    loop(N, ofArray(args));

    return ret;
  }
}

enum Cons<T> {
  N;
  P(head:T, tail:Cons<T>);
}