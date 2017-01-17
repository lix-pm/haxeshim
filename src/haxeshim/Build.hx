package haxeshim;

import haxe.macro.*;
using sys.io.File;

class Build { 

  static macro function postprocess() {
    Context.onAfterGenerate(function () {
      var file = Compiler.getOutput();
      file.saveContent('#!/usr/bin/env node\n\n'+file.getContent());
    });
    return null;
  }
  
}