[![Build Status](https://travis-ci.org/lix-pm/haxeshim.svg?branch=master)](https://travis-ci.org/lix-pm/haxeshim)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/lix-pm/Lobby)

# Haxe Shim - a simple wrapper around Haxe

Haxe is great. Greater than unicorns. Unfortunately decent solutions for handling different Haxe versions are like unicorns too: would be awesome but don't exist. Haxeshim tries to fill that gap. It does the following things:
	
1. Allow having different haxe versions.
2. Manage `-lib` params without haxelib.
3. Add `-scoped-hxml <file>` to process hxml files while resolving paths relative to their location.
4. Adds a few "extensions" for easier IDE integration.
5. Interpolate compiler arguments.
6. Handle `--cwd` in an arguably more meaningful way.

At the bottom line this project merely decouples a number of things that are currently just mushed together in the standard Haxe distribution. The decomposition itself would be highly advisable to apply there too, but attempts to argue for that have shown no effect, so an independent effort would seem to be the only way forward.

The project is currently based on nodejs for execution and distributed through NPM, due to their ubiquity. The command line interfaces aside, much of the code is written against Haxe's sys APIs and should thus be portable to other targets, as it should be, because currently it adds quite an overhead to compilation time (~100ms). Some of it can be optimized away, but given that invoking nodejs alone comes with quite an overhead, a truly optimized solution will have to rely on a different runtime. 

## Haxe version management

Haxeshim has a "root" directory, depending on platform:
	
- on Windows it is `%APPDATA%/haxe`
- elsewhere it is `${HOME}/haxe`

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

We'll cover library resultion below. As for execution of the haxe compiler itself, the binary in `<HAXESHIM_ROOT>/versions/<version>` is picked, with `HAXE_STD_PATH` set to the accompanying std lib.

## Library resolution

Currently `haxe` depends on `haxelib` to resolve `-lib` parameters. Haxeshim breaks this dependency apart, because it's the only sensible thing to do really. Haxelib was an excellent tool when it was released over a decade ago, but it's a bit dusty and improving it is extremely hard because of this strong dependency. Compare this to nodejs, where `require` follows a set of very specific rules where to look for modules and thus looks in the appropriate `node_modules`. NPM simply leverages this behavior to install packages where they are expected.

Haxeshim builds on the idea that every scope has a single version of a library. Normally you will want scopes to coincide with projects. There are three different resolution strategies:
	
### Scoped (the default)

Any parameters that are passed to haxeshim are parsed, including hxmls and the `-lib` parameters are "intercepted". To resolve these, we look for a `haxe_libraries/<libName>.hxml` and parse the parameters therein. If they are `-lib` parameters we process them accordingly. Note that in this case, specifying library versions as with `-lib name:version` is not allowed.

### Haxelib

Parameters are still parsed and then passed to `haxelib path` for resolution. In this case `-lib name:version` syntax is allowed.

### Mixed

This is a mix of both approaches. Libraries that are not found using scoped resolution or that use `-lib name:version` format are process with `haxelib path`.

## Support for "scoped" hxml files

Suppose you have set up a project in `~/projects/piratepig/` and you want to use its build configuration defined in `arrrrr.hxml` from another project. If you use `-scoped-hxml ~/projects/piratepig/aye.hxml` then all the libraries referenced therein are resolved within the scope of the project. 

If a project has a specific build configuration that you wish to reuse, you can also add it as a git submodule and reuse its hxmls in such a manner.

There are two things to be aware of:

1. because your project may be configured to use a different Haxe version, the build configuration may be incompatible
2. `--next` and `--each` are not properly supported in scoped hxmls. Also, if both the scoped and the calling `hxml` have the same `-lib depenency` then *both* results are added to the build and class path shaddowing determines the result of that.

## Extensions

You can run haxeshim extensions through `haxe --run <extension-name> [...args]`. Any `extension-name` must be lower case and contain at least one `-` sign to avoid collisions with `haxe --run <some.path.ClassName>`.

Currently, the following extensions are implemented:
  
- `install-libs`: this will go through all library hxmls in `haxe_libraries` and in case of missing class paths will pick up `@install:` and `@post-install` directives and execute them or report an error if none are present. Note that first all `@install` directives are run, and then all `@post-install` directives are run. Beyond that, consider the order strictly undefined.
- `resolve-args`: will resolve all the following arguments based on haxeshim's rules and prints each resulting argument on a single line.
- `show-version`: will report the current haxe version like so:
  
  ```
  -D haxe-ver=<theVersion>
  -cp <pathToStdLib>
  ```

## Interpolation of arguments

All arguments are interpolated, using environment variables. The interpolation syntax is `${name}` and `$name` will not be interpreted as a variable. If interpolation leads to an empty argument, the argument is simply skipped.

## Treatment of `--cwd`

With standard haxe, `--cwd` will simply switch the current working directory. Consider the following arguments:

```
--cwd /path/to/foo
-cp src1
--cwd /path/to/bar
-cp src2
--cwd /path/to/baz
-cp src3
```

In standard haxe, all relative class paths are looked up within the final cwd, i.e. `/path/to/baz` in this case. Arguably, this is not what was intended.

Haxeshim makes all class paths absolute during resolution, then uses the final cwd as basis and makes all class paths relative to that one if possible. The above arguments are thus interpreted as follows:

```
--cwd /path/to/baz
-cp /path/to/foo/src1
-cp /path/to/bar/src2
-cp src3
```

## Security implications

It is true that haxeshim kinda bypasses access control, allowing users to accidentally have their haxe command hijacked in some malicious way. Given though that anything running with the current user's privileges can tamper with the installed haxelibs and every haxelib using extraParams.hxml can execute arbitrary code with whatever privileges `haxe` was invoked with, we're not making it any worse.

## Building

To build, you will obviously need a Haxe version (haxe 3.4.0-rc.2 is known to work). Clone the repo recursively and then you can build.

## OS support

### Windows

Windows support seems ok on Windows 8.1 and 10.

The tool does the following nasty things:
  
1. Places `.exe` files near the `haxe.cmd` and `haxelib.cmd` files that NPM creates. The `.exe` files to nothing but call the `.cmd` file of the same name. This is because calling `.cmd` in batch stops execution. Try running this from a batch file to observe the behavior:
  
  ```
  haxe -version
  haxe -version
  haxe.cmd -version
  haxe.cmd -version
  ```
  
  It also places a fake `CHANGES.txt` into the npm command directory in a rather futile attempt to please FlashDevelop/HaxeDevelop.
  
2. Replaces the `haxe.exe` and `haxelib.exe` of the standard distribution, in case that one has precedence. The original files are backed up, just in case you wanna go back.

### Linux

Tested on the Ubuntu. Because it is nodejs based, chances are it works on other distros too, but if not, please report an issue.

### MacOS

According to feedback so far, haxeshim works on MacOS.