package ;

class RunTests {

  static function main() {
    var runner = new haxe.unit.TestRunner();

    runner.add(new TestResolution());

    var server = new haxeshim.CompilerServer(Port(6000), haxeshim.Scope.seek(), []);
    js.node.ChildProcess.exec('haxe --connect 6000 -version', function (error, stdout, stderr) {
      if (error == null) {
        travix.Logger.exit(
          if (runner.run()) 0
          else 500
        );        
      }
      else {
        trace(error);
        Sys.exit(500);
      }
    });
  }
  
}

class TestResolution extends haxe.unit.TestCase {
  function testNext() {
    var r = new haxeshim.Resolver(Sys.getCwd(), null, Haxelib, function (v) throw 'assert');
    assertEquals(
      ["--macro", "Sys.println('before')", "--run", "Main1", "--next", "-lib", "tink_core", "--run", "Main2", "-lib", "foo"].join('\n')
      ,r.resolve(['tests/build.hxml'], function (libs) {
        var ret = [];
        for (l in libs) {
          ret.push('-lib');
          ret.push(l);
        }
        return ret;
      }).join('\n'));

  }
}