class Run {
  static function main() {
    Sys.println('PREFER_RUN_N_OK');
    Sys.println(Sys.getEnv('HAXELIB_RUN_NAME'));
    Sys.println(Sys.getEnv('HAXELIB_LIBNAME'));
  }
}
