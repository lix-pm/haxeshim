package haxeshim;

typedef Config = {
  /**
    Which Haxe version to use. Allowed values are:
      - SemVer version numbers such as `3.4.7` and `4.0.0-rc.2`
      - several convenience "constants":
        - `"latest"`: the latest release of Haxe (including preview releases)
        - `"stable"`: the latest _stable_ release of Haxe
        - `"nightly"` / `"edge"`: the latest nightly build of Haxe
      - commit hashes for nightly builds such as `2341805`
      - a path to a directory with the Haxe installation
  **/
  var version(default, null):String;

  /**
    In what manner libraries should be resolved.
  **/
  var resolveLibs(default, null):LibResolution;
}
