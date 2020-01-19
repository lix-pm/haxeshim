package haxeshim;

class NekoCli {

  static function main() {

    Neko.setEnv();

    var binary =
      if (Os.IS_WINDOWS) 'neko.exe';
      else 'neko';

    var args = Sys.args(),
        cwd = cwd = Sys.getCwd();
    #if false
    switch args[0] {
      case '-i':
        args = [for (i in 1...args.length) Scope.seek().interpolate(args[i])];
      default:
    }

    var env = new Map(),
        pos = 0;

    function bisect(s:String, sep:String)
      return
        if (s == null) null;
        else switch s.indexOf(sep) {
          case -1: [s];
          case v: [s.substr(0, v), s.substr(v + sep.length)];
        }

    while (pos < args.length)
      switch args[pos++] {
        case '--env':
          switch bisect(args[pos++], '=') {
            case null:
              Sys.println('--env requires an argument');
              Sys.exit(422);
            case [k, v]: env[k] = v;
            case [k]: env[k] = '1';
          }
        case '--cwd':
          switch args[pos++] {
            case null:
                Sys.println('--cwd requires an argument');
                Sys.exit(422);
              case v:
              cwd = v;
          }
        default:
          pos--;
          break;
      }

    args = args.slice(pos);
    #end

    Sys.exit(
      switch Exec.sync(Neko.PATH + '/$binary', cwd, args, Neko.ENV.mergeInto(env)) {
        case Success(c):
          c;
        case Failure(e):
          e.code;
      }
    );
  }

}