package haxeshim;

import haxe.macro.*;
using sys.io.File;
using StringTools;

class Build { 

  static macro function postprocess() {
    var prefix = '#!/usr/bin/env node\n\n';
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