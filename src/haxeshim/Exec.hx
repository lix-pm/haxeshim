package haxeshim;

import js.node.Buffer;
import js.node.ChildProcess.*;
import haxe.ds.*;
import haxeshim.Errors;
using tink.CoreApi;

class Exec {

  static public function die(code, ?reason):Dynamic {
    if (reason != null)
      Logger.get().error(reason);
    Sys.exit(code);
    return throw 'unreachable';
  }

  static public function dieFromErrors(errors:ReadOnlyArray<ErrorMessage>):Dynamic {
    var code = null,
        logger = Logger.get();

    for (e in errors)
      logger.error(e.pos.toString() + ': ${e.message}');

    Sys.exit(Errors.getCode(errors));
    return throw 'unreachable';
  }
  static public function gracefully<T>(f:Void->T)
    return
      try f()
      catch (e:Error)
        die(e.code, e.message)
      catch (e:Dynamic)
        die(500, Std.string(e));

  static public function mergeEnv(env:Env)
    return env.mergeInto(js.Node.process.env);

  static public function async(cmd:String, cwd:String, args:Array<String>, ?env:Env)
    return spawn(cmd, args, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) });

  static public function shell(cmd:String, cwd:String, ?env:Env)
    return
      try
        Success((execSync(cmd, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) } ):Buffer))
      catch (e:Dynamic)
        Failure(new Error(e.status, 'Failed to invoke `$cmd` because $e'));

  static public function sync(cmd:String, cwd:String, args:Array<String>, ?env:Env)
    return switch spawnSync(cmd, args, { cwd: cwd, stdio: 'inherit', env: mergeEnv(env) } ) {
      case { error: null, status: code }:
        Success(code);
      case { error: e, status: code }:
        Failure(new Error(code, 'Failed to call $cmd because $e'));
    }

  static public function eval(cmd:String, cwd:String, ?args:Array<String>, ?env:Env)
    return switch spawnSync(cmd, args, { cwd: cwd, env: mergeEnv(env) } ) {
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