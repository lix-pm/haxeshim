package haxeshim;

import haxe.ds.ReadOnlyArray;
using tink.CoreApi;

class Errors {
  var errors:Array<ErrorMessage> = [];
  public function new() {}
  public function fail(message:String, pos:Pos, ?code:Int)
    this.errors.push({ message: message, pos: pos, code: code });

  public function produce<T>(result:T):Result<T>
    return switch errors {
      case []: Success(result);
      default: Failure({ result: result, errors: errors });
    }

  public function getResult<T>(r:Result<T>):T
    return switch r {
      case Success(r): r;
      case Failure(r):
        for (e in r.errors)
          errors.push(e);
        r.result;
    }
}

typedef Result<T> = Outcome<T, {
  final result:T;
  final errors:ReadOnlyArray<ErrorMessage>;
}>;

typedef ErrorMessage = {
  final message:String;
  final pos:Pos;
  final ?code:Int;
}

@:using(haxeshim.Errors.PosTools)
enum Pos {
  File(path:String, line:Int);
  Cmd(index:Int);
  Custom(source:String);
}

class PosTools {
  static public function toString(p:Pos)
    return switch p {
      case File(path, line): '$path:$line';
      case Cmd(index): 'CLI arg#$index';
      case Custom(source): source;
    }
}