import { spawn } from 'node:child_process';
import { getRepoRoot, getShimPath } from './bootstrap.mjs';

/**
 * @param {string} projectDir
 * @param {string[]} args
 * @returns {Promise<{ exitCode: number, stdout: string, stderr: string }>}
 */
export function runShim(projectDir, args) {
  const shim = getShimPath();

  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [shim, ...args], {
      cwd: projectDir,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', reject);
    child.on('close', (code) => {
      resolve({
        exitCode: code ?? 1,
        stdout,
        stderr,
      });
    });
  });
}

export { getRepoRoot };
