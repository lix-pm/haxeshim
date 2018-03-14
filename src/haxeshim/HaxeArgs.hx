package haxeshim;

using haxe.io.Path;
using StringTools;

class HaxeArgs {
  static function honorRun<T>(args:Args, f:Args->Args->T):T {
    var max = switch args.indexOf('--run') {
      case -1: args.length;
      case v: v;
    }
    return f(args.slice(0, max), args.slice(max));
  }

  // /**
  //  * Normalizes `--cwd` arguments.
  //  */
  // static public function normalizeCwd(cwd:String, args:Args):Args {

  //   function relative(path:String) {
  //     return 
  //       if (path.startsWith(cwd)) { 
  //         path.substr(cwd.length).normalize();
  //       }
  //       else 
  //         path;
  //   }    
    
  //   var ret = [],
  //       max = args.length,
  //       i = 0;

  //   return ['--cwd', cwd].concat(ret.map(relative));
  // }

  /**
   * Splits a chunk of arguments potentially containing `--each` and `--next`
   * into potentially multiple builds without `--each` and `--next`.
   */
  static public function splitBuilds(args:Args):Array<Args> 
    return honorRun(args, function (args, rest) {
      var ret = [],
          buf = [],
          each = [];

      function add() {
        ret.push(each.concat(buf));
        buf = [];      
      }

      for (arg in args) 
        switch arg {
          case '--each': 
            each = buf; 
            buf = [];
          case '--next': 
            add();
          case v: 
            buf.push(v);
        }
      buf = buf.concat(rest);
      add();
      return ret;
    });  
  
}