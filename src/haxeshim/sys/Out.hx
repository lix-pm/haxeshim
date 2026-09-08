package haxeshim.sys;

/**
  Writes to stdout, synchronously.

  On nodejs `Sys.print` compiles to `process.stdout.write`, which is asynchronous whenever
  stdout happens to be a pipe on macOS. Because the shims print their result and then
  immediately call `Sys.exit` - i.e. `process.exit` - whatever is still sitting in the
  stream's buffer is simply discarded, so that e.g. `haxelib path` would emit a silently
  truncated class path, which in turn makes the compiler fail with rather cryptic errors.

  Writing to the file descriptor is synchronous on every platform, so by the time we return
  the data is out the door.

  See https://github.com/lix-pm/haxeshim/issues/80
**/
class Out {

  static public inline function println(s:String)
    print(s + '\n');

  #if nodejs
  static public function print(s:String) {
    var buf = js.node.Buffer.from(s, 'utf8'),
        pos = 0;

    while (pos < buf.length)
      try pos += js.node.Fs.writeSync(1, buf, pos, buf.length - pos)
      catch (e:Dynamic) switch (e.code : String) {
        case 'EAGAIN':
          // stdout is a non-blocking pipe that is currently full - retry until the reader catches up
        case 'EPIPE' | 'EBADF':
          return;// whoever was reading is gone (or closed stdout on us), so there's no point in going on
        default:
          throw e;
      }
  }
  #else
  static public inline function print(s:String)
    Sys.print(s);
  #end

}
