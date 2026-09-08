class Run {
  static function main() {
    // a run script is invoked with the library's own directory as its working directory, which is
    // outside the scope it was invoked from - see https://github.com/lix-pm/haxeshim/issues/30
    Sys.println('INHERITED_SCOPE_RUN');
    Sys.println(
      if (Sys.command(Sys.getEnv('E2E_NODE'), [Sys.getEnv('E2E_HAXELIB_SHIM'), 'path', 'toolib']) == 0) '\nEXIT_OK'
      else '\nEXIT_FAILED'
    );
  }
}
