package ;

class RunTests {

  static function main() {
    var runner = new haxe.unit.TestRunner();

    runner.add(new TestResolution());

    travix.Logger.exit(
      if (runner.run()) 0
      else 500
    );
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