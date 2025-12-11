package haxeshim;

#if macro
import haxe.macro.*;

using sys.io.File;
#end

class Build { 
  static macro function postprocess() {
    var prefix = '#!/usr/bin/env node\n';
    Context.onAfterGenerate(function () {
      
      var file = Compiler.getOutput();

      switch file.getContent() {
        case _.startsWith(prefix) => true:
        case v:
          file.saveContent(prefix + v);
      }
      
    });
    return null;
  }
  
}