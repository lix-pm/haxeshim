package haxeshim;

import haxe.macro.*;

using sys.io.File;
using StringTools;

class Build { 
  static var NODE_PREFIX = '#!/usr/bin/env node\n\n';
  static macro function postprocess() {
    Context.onAfterGenerate(function () {
      var file = Compiler.getOutput();
      var old = file.getContent();
      if (!old.startsWith(NODE_PREFIX))
        file.saveContent(NODE_PREFIX + old);
    });
    return null;
  }
  
}