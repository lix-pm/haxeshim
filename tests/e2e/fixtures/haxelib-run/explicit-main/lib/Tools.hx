class Tools {
  static function main() {
    Sys.println('EXPLICIT_MAIN_OK');
    Sys.println(Sys.getEnv('HAXELIB_RUN_NAME'));
    Sys.println(Sys.getEnv('HAXELIB_LIBNAME'));
  }
}
