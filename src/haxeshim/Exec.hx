package haxeshim;

import haxe.DynamicAccess;
import js.node.Buffer;
using tink.CoreApi;

class Exec {
  static public function mergeEnv(add:DynamicAccess<String>) {
    var normalize = 
      if (Os.IS_WINDOWS) 
        function (s:String) return s.toUpperCase();
      else 
        function (s) return s;
    
    var env = js.Node.process.env;
    var ret = new DynamicAccess();

    for (m in [env, add])
      for (key in m.keys())
        ret[normalize(key)] = m[key];
    trace(ret);
    return ret;
  }  
  
  static public function async(cmd:String, cwd:String, args:Array<String>, ?env:DynamicAccess<String>) 
    return js.node.ChildProcess.spawn(cmd, args, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) }); 
  
  static public function shell(cmd:String, cwd:String, ?env:DynamicAccess<String>) 
    return 
      try 
        Success((js.node.ChildProcess.execSync(cmd, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) } ):Buffer))
      catch (e:Dynamic) 
        Failure(new Error(e.status, 'Failed to invoke `$cmd` because $e'));
    
  static public function sync(cmd:String, cwd:String, args:Array<String>, ?env:DynamicAccess<String>) 
    return switch js.node.ChildProcess.spawnSync(cmd, args, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) } ) {
      case x if (x.error == null):
        Success(x.status);
      case { error: e }:
        Failure(new Error('Failed to call $cmd because $e'));
    }
    
  static public function eval(cmd:String, cwd:String, args:Array<String>, ?env:DynamicAccess<String>) 
    return switch js.node.ChildProcess.spawnSync(cmd, args, { cwd: cwd, env: mergeEnv(env) } ) {
      case x if (x.error == null):
        Success({
          status: x.status,
          stdout: (x.stdout:Buffer).toString(),
          stderr: (x.stderr:Buffer).toString(),
        });
      case { error: e }:
        Failure(new Error('Failed to call $cmd because $e'));
    }
    
}