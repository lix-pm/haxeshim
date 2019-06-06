package haxeshim;

using tink.CoreApi;

class Attempt {
  static public function to<T>(what:String, how:Void->T, ?pos):Promise<T>
    return 
      Future.lazy(function () return how.catchExceptions(function (data) {
        return Error.withData('Failed to $what', data, pos);
      }));
}