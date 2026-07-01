package ;

import haxeshim.*;
import haxeshim.sys.Env;
import haxeshim.sys.Os;
using haxe.io.Path;
using tink.CoreApi;

class RunTests {

  static function main() {
    var runner = new haxe.unit.TestRunner();

    runner.add(new TestArgs());
    runner.add(new TestEnv());

    Sys.exit(if (runner.run()) 0 else 1);
  }

}

class Base extends haxe.unit.TestCase {
  function structEq<T>(a:T, b:T, ?pos:haxe.PosInfos) {
    assertEquals(haxe.Json.stringify(a), haxe.Json.stringify(b), pos);
  }
}

class TestArgs extends Base {
  function testInterpolation() {
    var foo = 'FOO-VAL',
        bar = 'BAR-VAL',
        baz = 'BAZ-VAL',
        bop = 'BOP-VAL';

    var vars = ['foo' => foo, 'bar' => bar, 'baz' => baz, 'bop' => bop];
    var getVar = function (s) return vars[s];

    function assertSuccess(expected:String, raw:String, ?pos:haxe.PosInfos)
      switch Args.interpolate(raw, getVar) {
        case Success(v): assertEquals(expected, v, pos);
        case Failure(e):
          trace('expected Success($expected) but got Failure($e)');
          assertTrue(false, pos);
      }

    function assertFailure(expected:String, raw:String, ?pos:haxe.PosInfos)
      switch Args.interpolate(raw, getVar) {
        case Success(v):
          trace('expected Failure($expected) but got Success($v)');
          assertTrue(false, pos);
        case Failure(e): assertEquals(expected, e, pos);
      }

    assertSuccess('foo', 'foo');
    assertSuccess('foo${foo}foo', "foo${foo}foo");
    assertSuccess('foo${bar}foo', "foo${bar}foo");
    assertFailure("unknown variable boop", "foo${boop}foo");
    assertFailure("unclosed interpolation in foo${boop", "foo${boop");
  }
}

class TestEnv extends Base {
  function test() {
    var a:Env = {
      'one': 'a',
      'two': 'a',
    }
    var b:Env = {
      'two': 'b',
      'three': 'b',
    }

    var aIntoB = a.mergeInto(b),
        bIntoA = b.mergeInto(a);

    assertEquals('a', aIntoB['one']);
    assertEquals('a', bIntoA['one']);

    assertEquals('a', aIntoB['two']);
    assertEquals('b', bIntoA['two']);

    assertEquals('b', aIntoB['three']);
    assertEquals('b', bIntoA['three']);

    if (Os.IS_WINDOWS) {
      assertEquals('a', aIntoB['oNe']);
    }
  }
}
