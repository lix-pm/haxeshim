package ;

import haxeshim.*;
using haxe.io.Path;
using tink.CoreApi;

class RunTests {

  static function main() {
    var runner = new haxe.unit.TestRunner();

    runner.add(new TestArgs());
    runner.add(new TestResolution());
    runner.add(new TestEnv());

    new CompilerServer(Port(6000), Scope.seek(), []);

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

class TestArgs extends haxe.unit.TestCase {
  function testPlus() {
    function assert(expected:Args, found:Args, ?pos:haxe.PosInfos) {
      assertEquals(haxe.Json.stringify(expected), haxe.Json.stringify(found), pos);
    }
    var args:Args = ['foo', 'bar'];
    assert(['1', 'foo', 'bar'], '1' + args);
    assert(['foo', 'bar', '1'], args + '1');
    assert(['1', '2', 'foo', 'bar'], ['1', '2'] + args);
    assert(['foo', 'bar', '1', '2'], args + ['1', '2']);
    assert(['foo', 'bar', 'foo', 'bar'], args + args);
  }

  function testInterpolation() {
    var foo = 'FOO-VAL',
        bar = 'BAR-VAL',
        baz = 'BAZ-VAL',
        bop = 'BOP-VAL';

    var vars = ['foo' => foo, 'bar' => bar, 'baz' => baz, 'bop' => bop];
    var resolve = function (s) return switch vars[s] {
      case null: None;
      case v: Some(v);
    }

    function assert(expected:String, raw:String, ?errors:Array<String>, ?pos:haxe.PosInfos) {
      var found = Args.interpolateString(raw, resolve);
      assertEquals(expected, found.result, pos);
      if (errors == null) errors = [];
      assertEquals(haxe.Json.stringify(errors), haxe.Json.stringify(found.errors), pos);
    }

    assert('foo', 'foo');
    assert('foo${foo}foo', "foo${foo}foo");
    assert('foo${bar}foo', "foo${bar}foo");
    assert('fooboopfoo', "foo${boop}foo", ['unresolved variable `boop`']);
    assert('foo$${boop', "foo${boop", ['unclosed interpolation in "foo$${boop"']);
    
  }
}

class TestEnv extends haxe.unit.TestCase {
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

class TestResolution extends haxe.unit.TestCase {
  function testNext() {
    var r = new Resolver(Sys.getCwd(), null, Haxelib, function (v) throw 'assert');
    assertEquals(
      ["--macro", "Sys.println('before')", "--run", "Main1", "--next", "-lib", "tink_core", "--run", "Main2", "-lib", "foo"].join('\n')
      ,r.resolve(['tests/build.hxml'], function (libs) {
        var ret = [];
        for (l in libs) {
          ret.push('-lib');
          ret.push(l);
        }
        return ret;
      }).slice(2).join('\n'));

  }
}