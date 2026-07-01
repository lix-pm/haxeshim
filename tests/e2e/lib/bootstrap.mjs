import { spawnSync } from 'node:child_process';
import { accessSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '../../..');

export function getRepoRoot() {
  return repoRoot;
}

export function getShimPath() {
  return join(repoRoot, 'bin/haxeshim.js');
}

export function getHaxeVersion() {
  return process.env.HAXE_VERSION || '4.3.7';
}

export function ensureShimBuilt() {
  const shim = getShimPath();
  try {
    accessSync(shim);
  } catch {
    throw new Error(`haxeshim.js not found at ${shim}. Run: haxe haxeshim.hxml`);
  }
}

export function installHaxe(version = getHaxeVersion()) {
  const result = spawnSync('lix', ['install', 'haxe', version], {
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });

  if (result.error) {
    throw new Error(`Failed to run lix install haxe ${version}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`lix install haxe ${version} exited with code ${result.status}`);
  }
}

export function bootstrap() {
  ensureShimBuilt();
  installHaxe();
}
