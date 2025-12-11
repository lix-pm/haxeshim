package haxeshim;

typedef Vars = haxe.DynamicAccess<String>;

@:forward(keys)
abstract Env(Vars) {

  @:from static function ofObj(o:Dynamic<String>) return ofVars(o);
  @:from static function ofVars(vars:Vars) {
    var ret = new Vars();
    for (k in vars.keys())
      ret[normalize(k)] = vars[k];
    return new Env(ret);
  }

  public inline function keys()
    return 
      if (this == null) []
      else this.keys();

  @:from static function ofMap(map:Map<String, String>) {
    var ret = new Vars();
    for (k in map.keys())
      ret[normalize(k)] = map[k];
    return new Env(ret);
  }

  function vars() return this;

  @:to function toVars():Vars
    return Reflect.copy(this);

  inline function new(vars) 
    this = vars;

  @:arrayAccess public function get(s:String)
    return this[normalize(s)];

  static inline function normalize(s:String)
    return if (Os.IS_WINDOWS) s.toUpperCase() else s;

  public function mergeInto(that:Env):Env
    return switch [this, that.vars()] {
      case [null, v] | [v, null]: new Env(v);
      case [a, b]:
        var ret = new Vars();

        for (vars in [b, a])
        for (k in vars.keys())
            ret[k] = vars[k];

        return new Env(ret);
    }

  
}
