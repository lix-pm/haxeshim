import { spawnSync } from 'node:child_process';
import { accessSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '../../..');
const shell = process.platform === 'win32';

export function getRepoRoot() {
  return repoRoot;
}

export function getShimPath() {
  return join(repoRoot, 'bin/haxeshim.js');
}

export function ensureShimBuilt() {
  const shim = getShimPath();
  try {
    accessSync(shim);
  } catch {
    throw new Error(`haxeshim.js not found at ${shim}. Run: haxe haxeshim.hxml`);
  }
}

/**
 * @param {string[]} args
 * @param {string} cwd
 */
function runLix(args, cwd) {
  const label = `lix ${args.join(' ')}`;
  const result = spawnSync('lix', args, {
    cwd,
    stdio: 'inherit',
    shell,
  });

  if (result.error) {
    throw new Error(`Failed to run ${label} in ${cwd}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`${label} in ${cwd} exited with code ${result.status}`);
  }
}

/**
 * @param {string} projectDir
 * @param {{ haxeVersion?: string }} options
 */
export function prepareFixture(projectDir, { haxeVersion } = {}) {
  if (haxeVersion) {
    runLix(['install', 'haxe', haxeVersion], projectDir);
    runLix(['use', 'haxe', haxeVersion], projectDir);
  }
  runLix(['download'], projectDir);
}

export function bootstrap() {
  ensureShimBuilt();
}
