# Haxe Shim - a simple wrapper around Haxe

Haxe is great. Greater than unicorns. Unfortunately decent solutions for handling different Haxe versions are like unicorns too: would be awesome but don't exist. Haxeshim tries to fill that gap. It does exactly two things:
	
1. Allow having different haxe versions.
2. Manage `-lib` params without haxelib.

## Haxe version management

Haxeshim has a "root" directory, depending on platform:
	
- on Windows it is `%APPDATA%/haxe`
- elsewhere it is `~/haxe`

It can always be overwritten with the `HAXESHIM_ROOT` environment variable.

When running the `haxe` command, we scan from the CWD up for a `.haxerc` and if non is found we look in the "root" directory. Every `.haxerc` defines what we consider a "scope" for all subdirectories (except those which contain `.haxerc` files to define new scopes).

The contents of this file are stored as JSON and defined like so:
	
```haxe
typedef Config = {
  var version(default, null):String;
  var resolveLibs(default, null):LibResolution;
}

@:enum abstract LibResolution(String) {
  var Scoped = null;
  var Mixed = 'mixed';
  var Haxelib = 'haxelib';
}
```

We'll cover library resultion below. As for execution of the haxe compiler itself, the binary in `<HAXESHIM_ROOT>/version/<version>` is picked, with `HAXE_STD_PATH` set to the accompanying std lib.

## Library resolution

Currently `haxe` depends on `haxelib` to resolve `-lib` parameters. Haxeshim breaks this dependency apart, because it's the only sensible thing to do really. Haxelib was an excellent tool when it was released over a decade ago, but it's a bit dusty and improving it is extremely hard because of this strong dependency. Compare this to nodejs, where `require` follows a set of very specific rules where to look for modules and thus looks in the appropriate `node_modules`. NPM simply leverages this behavior to install packages where they are expected.

Haxeshim builds on the idea that every scope has a single version of a library. Normally you will want scopes to coincide with projects. There are three different resolution strategies:
	
### Scoped (the default)

Any parameters that are passed to haxeshim are parsed, including hxmls and the `-lib` parameters are "intercepted". To resolve these, we look for a `.haxelib/<libName>.hxml` and parse the parameters therein. If they are `-lib` parameters we process them accordingly. Note that in this case, specifying library versions as with `-lib name:version` is not allowed.

### Haxelib

Parameters are still parsed and then passed to `haxelib path` for resolution. In this case `-lib name:version` syntax is allowed.

### Mixed

This is a mix of both approaches. Libraries that are not found using scoped resolution or that use `-lib name:version` format are process with `haxelib path`.

## Security implications

It is true that haxeshim kinda bypasses access control, allowing users to accidentally have their haxe command hijacked in some malicious way. Given though that anything running with the current user's privileges can tamper with the installed haxelibs and every haxelib using extraParams.hxml can execute arbitrary code, we're not making it any worse.