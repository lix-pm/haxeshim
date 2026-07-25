/**
 * Repro: on Windows, CreateProcess searches the directory of haxe.exe before PATH.
 * Nightly/stable Windows Haxe zips ship stock haxelib.exe next to haxe.exe, so
 * gencpp's `haxelib path hxcpp` hits stock haxelib and misses scoped libs:
 *   "Library hxcpp is not installed" / End_of_file
 *
 * This check expects scoped resolution to win (via the PATH/npm shim). Without
 * wrapping the version-dir haxelib.exe, it fails on windows-latest.
 *
 * Non-Windows platforms skip (CreateProcess sibling search is Windows-only).
 */
import { readFileSync } from 'node:fs';
import { access, readdir, stat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { bootstrap, prepareFixture } from './lib/bootstrap.mjs';
import { runShim } from './lib/shim.mjs';
import { bold, boldRed, green } from './lib/colors.mjs';

const e2eRoot = dirname(fileURLToPath(import.meta.url));
const projectDir = join(e2eRoot, 'fixtures/windows-sibling-haxelib');

function parseArgs() {
  const argv = process.argv.slice(2);
  let haxeVersion;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--haxe-version') {
      haxeVersion = argv[++i];
      if (!haxeVersion) throw new Error('--haxe-version requires a version argument');
      continue;
    }
    throw new Error(`Unknown argument: ${argv[i]}`);
  }
  return { haxeVersion };
}

function getConfiguredVersion(dir) {
  return JSON.parse(readFileSync(join(dir, '.haxerc'), 'utf8')).version;
}

/** Same default as Scope.DEFAULT_ROOT. */
function getHaxeRoot() {
  return (
    process.env.HAXE_ROOT ||
    process.env.HAXESHIM_ROOT ||
    join(
      process.platform === 'win32'
        ? process.env.APPDATA || join(process.env.USERPROFILE || '', 'AppData', 'Roaming')
        : process.env.HOME || '',
      'haxe'
    )
  );
}

/**
 * Locate downloaded Windows haxe.exe + sibling haxelib.exe.
 * @param {string} version
 */
async function findWindowsHaxePair(version) {
  const versionsRoot = join(getHaxeRoot(), 'versions');
  let entries;
  try {
    entries = await readdir(versionsRoot, { withFileTypes: true });
  } catch {
    return null;
  }

  const candidates = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const path = join(versionsRoot, entry.name);
    const haxeExe = join(path, 'haxe.exe');
    const haxelibExe = join(path, 'haxelib.exe');
    try {
      await access(haxeExe);
      await access(haxelibExe);
      candidates.push({ path, haxeExe, haxelibExe, name: entry.name });
    } catch {
      // not a Windows layout
    }
  }

  if (candidates.length === 0) return null;

  const exact = candidates.find((c) => c.name === version || c.name.startsWith(version));
  return exact ?? candidates[candidates.length - 1];
}

async function main() {
  if (process.platform !== 'win32') {
    console.log('Skipping windows-sibling-haxelib (not Windows)');
    return;
  }

  const { haxeVersion } = parseArgs();
  console.log(bold('Windows sibling-haxelib repro'));
  bootstrap();
  prepareFixture(projectDir, { haxeVersion });

  const configured = getConfiguredVersion(projectDir);
  const haxeRoot = getHaxeRoot();
  console.log(`  Haxe version (.haxerc): ${configured}`);
  console.log(`  Haxe root: ${haxeRoot}`);

  const pair = await findWindowsHaxePair(configured);
  if (pair) {
    const haxelibStat = await stat(pair.haxelibExe);
    console.log(`  Haxe dir: ${pair.path}`);
    console.log(`  Sibling haxelib.exe size: ${haxelibStat.size} bytes`);
    if (haxelibStat.size < 10000) {
      console.log(
        '  Note: haxelib.exe looks like an exify shim already; repro may not trigger.'
      );
    }
  } else {
    console.log(
      '  Warning: could not locate sibling haxe.exe/haxelib.exe; continuing with compile repro'
    );
  }

  // Trigger gencpp → CreateProcess("haxelib") → sibling stock haxelib.exe
  const args = ['-cp', 'src', '-main', 'Main', '-cpp', 'out_cpp'];
  console.log(`  invoke: runShim(${JSON.stringify(args)})`);
  const result = await runShim(projectDir, args);
  const output = `${result.stdout}\n${result.stderr}`;
  console.log('  stdout:', result.stdout);
  console.log('  stderr:', result.stderr);
  console.log('  exit:', result.exitCode);

  const missingLib =
    /Library hxcpp is not installed/i.test(output) ||
    (/End_of_file/i.test(output) && /hxcpp/i.test(output));

  if (missingLib) {
    throw new Error(
      'Windows sibling-haxelib bug: haxe.exe resolved stock sibling haxelib.exe ' +
        'instead of the scoped haxeshim (gencpp `haxelib path hxcpp` failed).\n' +
        (pair ? `  haxe dir: ${pair.path}\n` : '') +
        `  output:\n${output}`
    );
  }

  // Scoped path resolution worked. Full native link may still fail without a
  // C++ toolchain; that is outside this repro.
  console.log(green('ok  scoped haxelib won over sibling stock haxelib.exe'));
}

main().catch((e) => {
  console.error(boldRed(e instanceof Error ? e.message : String(e)));
  process.exit(1);
});
