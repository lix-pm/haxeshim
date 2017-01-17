package haxeshim;

import haxe.DynamicAccess;
using tink.CoreApi;

class Exec {
  
  static function mergeEnv(add:DynamicAccess<String>) {
    var ret = Reflect.copy(js.Node.process.env);
    
    for (name in add.keys())
      ret[name] = add[name];
      
    return ret;
  }  
  
  static public function async(cmd:String, cwd:String, args:Array<String>, ?env:DynamicAccess<String>) 
    return js.node.ChildProcess.spawn(cmd, args, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) }); 
  
  static public function sync(cmd:String, cwd:String, args:Array<String>, ?env:DynamicAccess<String>) 
    return switch js.node.ChildProcess.spawnSync(cmd, args, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) } ) {
      case x if (x.error == null):
        Success(x.status);
      case { error: e }:
        Failure(new Error('Failed to call $cmd because $e'));
    }
}