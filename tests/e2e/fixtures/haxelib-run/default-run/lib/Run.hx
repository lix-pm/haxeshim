class Run {
  static function main() {
    Sys.println('DEFAULT_RUN_OK');
    Sys.println(Sys.getEnv('HAXELIB_RUN_NAME'));
    Sys.println(Sys.getEnv('HAXELIB_LIBNAME'));
  }
}
