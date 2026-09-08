import { readdir, readFile, unlink, access } from 'node:fs/promises';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { bootstrap, prepareFixture, getHaxelibShimPath } from './lib/bootstrap.mjs';
import {
  getFreePort,
  spawnWaitServer,
  spawnConnectClient,
  createMockIdeServer,
  waitForPort,
  sendWaitCompileRequest,
  sendConnectCompileRequest,
} from './lib/compile-server.mjs';
import { bold, boldGreen, boldRed, green, setColorEnabled } from './lib/colors.mjs';
import { log, setVerbose } from './lib/log.mjs';
import { runShim, runHaxelibShim } from './lib/shim.mjs';
import { parseLines, assertExpected, assertResolveArgsCheck, exitCodesMatch } from './lib/assert.mjs';

const SERVER_TIMEOUT_MS = 10_000;

const e2eRoot = dirname(fileURLToPath(import.meta.url));
const fixturesRoot = join(e2eRoot, 'fixtures');

/**
 * @returns {{ haxeVersion?: string, verbose: boolean, noColor: boolean }}
 */
function parseArgs() {
  const argv = process.argv.slice(2);
  let haxeVersion;
  let verbose = false;
  let noColor = false;

  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--haxe-version') {
      haxeVersion = argv[++i];
      if (!haxeVersion) {
        throw new Error('--haxe-version requires a version argument');
      }
      continue;
    }
    if (argv[i] === '--verbose') {
      verbose = true;
      continue;
    }
    if (argv[i] === '--no-color') {
      noColor = true;
      continue;
    }
    throw new Error(`Unknown argument: ${argv[i]}`);
  }

  return { haxeVersion, verbose, noColor };
}

/**
 * @param {string} category
 */
async function discoverCases(category) {
  const categoryDir = join(fixturesRoot, category);
  const entries = await readdir(categoryDir, { withFileTypes: true });
  const cases = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const projectDir = join(categoryDir, entry.name);
    const casePath = join(projectDir, 'case.json');
    try {
      await access(casePath);
    } catch {
      continue;
    }
    cases.push({
      name: `${category}/${entry.name}`,
      projectDir,
      definition: JSON.parse(await readFile(casePath, 'utf8')),
    });
  }

  return cases.sort((a, b) => a.name.localeCompare(b.name));
}

/** @type {Set<string>} */
const preparedFixtures = new Set();

/**
 * @param {{ name: string, projectDir: string, definition: any }} testCase
 * @param {{ haxeVersion?: string }} options
 */
async function ensureFixturePrepared(testCase, { haxeVersion }) {
  const { projectDir } = testCase;
  if (preparedFixtures.has(projectDir)) return;

  prepareFixture(projectDir, { haxeVersion });
  preparedFixtures.add(projectDir);
}

/**
 * @param {{ name: string, projectDir: string, definition: any }} testCase
 */
async function runResolveArgsCase(testCase) {
  const { name, projectDir, definition } = testCase;
  const shimArgs = ['--run', 'resolve-args', ...definition.args];
  log(name, `invoke: runShim(${JSON.stringify(shimArgs)})`);

  const result = await runShim(projectDir, shimArgs);
  log(name, 'stdout:', result.stdout);
  log(name, 'stderr:', result.stderr);

  const output = result.stdout + result.stderr;

  if (!exitCodesMatch(result.exitCode, definition.exitCode)) {
    throw new Error(
      `${name}: expected exit code ${definition.exitCode}, got ${result.exitCode}\n` +
        `  stdout: ${result.stdout}\n` +
        `  stderr: ${result.stderr}`
    );
  }

  if (definition.expectedError) {
    if (!output.includes(definition.expectedError)) {
      throw new Error(
        `${name}: expected error containing ${JSON.stringify(definition.expectedError)}\n` +
          `  output: ${output}`
      );
    }
    return;
  }

  if (definition.expected) {
    const lines = parseLines(result.stdout, projectDir);
    assertExpected(lines, definition.expected, name);
  }
}

/**
 * Substitutes the placeholders that let a fixture refer to its own location and to the
 * things it needs to invoke the shims again from within a `haxelib run` script.
 * @param {string} value
 * @param {string} projectDir
 */
function substitutePlaceholders(value, projectDir) {
  return value
    .replaceAll('__PROJECT_DIR__', projectDir)
    .replaceAll('__HAXELIB_SHIM__', getHaxelibShimPath())
    .replaceAll('__NODE__', process.execPath);
}

/**
 * @param {{ name: string, projectDir: string, definition: any }} testCase
 */
async function runHaxelibFlagsCase(testCase) {
  const { name, projectDir, definition } = testCase;
  const args = definition.args.map((arg) => substitutePlaceholders(arg, projectDir));
  const env = Object.fromEntries(
    Object.entries(definition.env ?? {}).map(([key, value]) => [
      key,
      substitutePlaceholders(String(value), projectDir),
    ])
  );
  const spawnCwd = definition.spawnCwd
    ? resolve(projectDir, definition.spawnCwd)
    : projectDir;
  log(name, `invoke: runHaxelibShim(cwd=${spawnCwd}, ${JSON.stringify(args)})`);

  const result = await runHaxelibShim(spawnCwd, args, env);
  log(name, 'stdout:', result.stdout);
  log(name, 'stderr:', result.stderr);

  const output = result.stdout + result.stderr;
  const exitCode = definition.exitCode ?? 0;

  if (!exitCodesMatch(result.exitCode, exitCode)) {
    throw new Error(
      `${name}: expected exit code ${exitCode}, got ${result.exitCode}\n` +
        `  stdout: ${result.stdout}\n` +
        `  stderr: ${result.stderr}`
    );
  }

  if (definition.expectedError) {
    if (!output.includes(definition.expectedError)) {
      throw new Error(
        `${name}: expected error containing ${JSON.stringify(definition.expectedError)}\n` +
          `  output: ${output}`
      );
    }
    return;
  }

  for (const token of definition.mustNotContain ?? []) {
    if (output.includes(token)) {
      throw new Error(
        `${name}: output must not contain ${JSON.stringify(token)}\n` +
          `  output: ${output}`
      );
    }
  }

  if (definition.expected) {
    const lines = parseLines(result.stdout, projectDir);
    assertExpected(lines, definition.expected, name);
  }
}

/**
 * @param {{ name: string, projectDir: string, definition: any }} testCase
 */
async function runCompileCase(testCase) {
  const { name, projectDir, definition } = testCase;

  if (definition.resolveArgsCheck) {
    const resolved = await runShim(projectDir, ['--run', 'resolve-args', ...definition.args]);
    log(name, 'resolve-args cross-check stdout:', resolved.stdout);
    log(name, 'resolve-args cross-check stderr:', resolved.stderr);
    if (resolved.exitCode !== 0) {
      throw new Error(
        `${name} resolve-args cross-check: expected exit 0, got ${resolved.exitCode}\n` +
          `  stdout: ${resolved.stdout}\n` +
          `  stderr: ${resolved.stderr}`
      );
    }
    assertResolveArgsCheck(resolved.stdout, projectDir, definition.resolveArgsCheck);
  }

  const outputPath = join(projectDir, definition.output);
  await unlink(outputPath).catch(() => {});

  log(name, `invoke: runShim(${JSON.stringify(definition.args)})`);
  const result = await runShim(projectDir, definition.args);
  log(name, 'stdout:', result.stdout);
  log(name, 'stderr:', result.stderr);

  if (!exitCodesMatch(result.exitCode, definition.exitCode)) {
    throw new Error(
      `${name}: expected exit code ${definition.exitCode}, got ${result.exitCode}\n` +
        `  stdout: ${result.stdout}\n` +
        `  stderr: ${result.stderr}`
    );
  }

  try {
    await access(outputPath);
  } catch {
    throw new Error(`${name}: expected output file ${definition.output} to exist`);
  }

  if (definition.outputContains) {
    const content = await readFile(outputPath, 'utf8');
    if (!content.includes(definition.outputContains)) {
      throw new Error(
        `${name}: expected output to contain ${JSON.stringify(definition.outputContains)}\n` +
          `  file: ${definition.output}`
      );
    }
  }
}

/**
 * @param {string} name
 * @param {string} projectDir
 * @param {any} definition
 * @param {string} mode
 */
async function runServerMode(name, projectDir, definition, mode) {
  if (definition.resolveArgsCheck) {
    const resolved = await runShim(projectDir, ['--run', 'resolve-args', ...definition.args]);
    log(name, 'resolve-args cross-check stdout:', resolved.stdout);
    log(name, 'resolve-args cross-check stderr:', resolved.stderr);
    if (resolved.exitCode !== 0) {
      throw new Error(
        `${name} resolve-args cross-check: expected exit 0, got ${resolved.exitCode}\n` +
          `  stdout: ${resolved.stdout}\n` +
          `  stderr: ${resolved.stderr}`
      );
    }
    assertResolveArgsCheck(resolved.stdout, projectDir, definition.resolveArgsCheck);
  }

  const outputPath = join(projectDir, definition.output);
  await unlink(outputPath).catch(() => {});

  if (mode === 'wait') {
    const port = await getFreePort();
    const server = spawnWaitServer(projectDir, port, { caseName: name });

    try {
      await waitForPort(port, SERVER_TIMEOUT_MS);

      const { response } = await sendWaitCompileRequest(port, definition.args, {
        timeoutMs: SERVER_TIMEOUT_MS,
        caseName: name,
      });

      if (response.length === 0 && !definition.output) {
        throw new Error(
          `${name}: expected non-empty TCP response\n` + `  stderr: ${server.getStderr()}`
        );
      }

      await assertServerOutput(name, projectDir, definition, outputPath, response, server.getStderr());
    } finally {
      server.kill();
    }
    return;
  }

  if (mode === 'connect') {
    const mock = await createMockIdeServer(SERVER_TIMEOUT_MS);
    const client = spawnConnectClient(projectDir, mock.port, { caseName: name });

    try {
      await mock.waitForConnection();

      const { response } = await sendConnectCompileRequest(mock, definition.args, { caseName: name });

      if (response.length === 0 && !definition.output) {
        throw new Error(
          `${name}: expected non-empty framed response\n` + `  stderr: ${client.getStderr()}`
        );
      }

      await assertServerOutput(name, projectDir, definition, outputPath, response, client.getStderr());
    } finally {
      client.kill();
      mock.close();
    }
    return;
  }

  throw new Error(`${name}: unknown server mode ${JSON.stringify(mode)}`);
}

/**
 * @param {string} name
 * @param {string} projectDir
 * @param {any} definition
 * @param {string} outputPath
 * @param {string} response
 * @param {string} stderr
 */
async function assertServerOutput(name, projectDir, definition, outputPath, response, stderr) {
  try {
    await access(outputPath);
  } catch {
    throw new Error(
      `${name}: expected output file ${definition.output} to exist\n` +
        `  response: ${response}\n` +
        `  stderr: ${stderr}`
    );
  }

  if (definition.outputContains) {
    const content = await readFile(outputPath, 'utf8');
    if (!content.includes(definition.outputContains)) {
      throw new Error(
        `${name}: expected output to contain ${JSON.stringify(definition.outputContains)}\n` +
          `  file: ${definition.output}`
      );
    }
  }
}

/**
 * @param {{ name: string, projectDir: string, definition: any }} testCase
 * @returns {Array<{ name: string, projectDir: string, definition: any }>}
 */
function expandResolveArgsRuns(testCase) {
  const { name, projectDir, definition } = testCase;
  const variants = definition.variants;

  if (!variants) {
    return [testCase];
  }

  return variants.map((variant, index) => {
    const variantName = variant.name ?? `#${index}`;
    const { variants: _variants, args: _args, ...shared } = definition;
    const { name: _variantName, args: variantArgs, ...variantOverrides } = variant;
    return {
      name: `${name} (${variantName})`,
      projectDir,
      definition: { ...shared, ...variantOverrides, args: variantArgs },
    };
  });
}

/**
 * @param {any[]} resolveCases
 */
function countResolveArgsRuns(resolveCases) {
  return resolveCases.reduce((total, testCase) => {
    const variants = testCase.definition.variants;
    return total + (variants ? variants.length : 1);
  }, 0);
}

/**
 * @param {any[]} serverCases
 */
function countServerRuns(serverCases) {
  return serverCases.reduce((total, testCase) => {
    const modes = testCase.definition.modes ?? ['wait'];
    return total + modes.length;
  }, 0);
}

async function main() {
  const { haxeVersion, verbose, noColor } = parseArgs();
  if (noColor) {
    setColorEnabled(false);
  }
  setVerbose(verbose);

  console.log(bold('Bootstrapping E2E environment...'));
  bootstrap();
  if (haxeVersion) {
    console.log(`Using Haxe version from --haxe-version: ${haxeVersion}`);
  }
  if (verbose) {
    console.log('Verbose logging enabled');
  }

  const resolveCases = await discoverCases('resolve-args');
  const haxelibFlagsCases = await discoverCases('haxelib-flags');
  const haxelibRunCases = await discoverCases('haxelib-run');
  const compileCases = await discoverCases('compile');
  const serverCases = await discoverCases('server');
  const failures = [];
  const runOptions = { haxeVersion };

  const resolveRunCount = countResolveArgsRuns(resolveCases);
  const haxelibFlagsRunCount = countResolveArgsRuns(haxelibFlagsCases);
  const haxelibRunCount = countResolveArgsRuns(haxelibRunCases);
  console.log(bold(`Running ${resolveRunCount} resolve-args cases...`));
  for (const testCase of resolveCases) {
    for (const run of expandResolveArgsRuns(testCase)) {
      try {
        await ensureFixturePrepared(run, runOptions);
        await runResolveArgsCase(run);
        console.log(`  ${green('ok')}  ${run.name}`);
      } catch (e) {
        console.error(`  ${boldRed('FAIL')} ${run.name}`);
        console.error(e instanceof Error ? e.message : e);
        failures.push(run.name);
      }
    }
  }

  console.log(bold(`Running ${haxelibFlagsRunCount} haxelib-flags cases...`));
  for (const testCase of haxelibFlagsCases) {
    for (const run of expandResolveArgsRuns(testCase)) {
      try {
        await ensureFixturePrepared(run, runOptions);
        await runHaxelibFlagsCase(run);
        console.log(`  ${green('ok')}  ${run.name}`);
      } catch (e) {
        console.error(`  ${boldRed('FAIL')} ${run.name}`);
        console.error(e instanceof Error ? e.message : e);
        failures.push(run.name);
      }
    }
  }

  console.log(bold(`Running ${haxelibRunCount} haxelib-run cases...`));
  for (const testCase of haxelibRunCases) {
    for (const run of expandResolveArgsRuns(testCase)) {
      try {
        await ensureFixturePrepared(run, runOptions);
        await runHaxelibFlagsCase(run);
        console.log(`  ${green('ok')}  ${run.name}`);
      } catch (e) {
        console.error(`  ${boldRed('FAIL')} ${run.name}`);
        console.error(e instanceof Error ? e.message : e);
        failures.push(run.name);
      }
    }
  }

  console.log(bold(`Running ${compileCases.length} compile cases...`));
  for (const testCase of compileCases) {
    try {
      await ensureFixturePrepared(testCase, runOptions);
      await runCompileCase(testCase);
      console.log(`  ${green('ok')}  ${testCase.name}`);
    } catch (e) {
      console.error(`  ${boldRed('FAIL')} ${testCase.name}`);
      console.error(e instanceof Error ? e.message : e);
      failures.push(testCase.name);
    }
  }

  const serverRunCount = countServerRuns(serverCases);
  console.log(bold(`Running ${serverRunCount} server cases...`));
  for (const testCase of serverCases) {
    const modes = testCase.definition.modes ?? ['wait'];
    for (const mode of modes) {
      const modeName = `${testCase.name} (${mode})`;
      try {
        await ensureFixturePrepared(testCase, runOptions);
        await runServerMode(modeName, testCase.projectDir, testCase.definition, mode);
        console.log(`  ${green('ok')}  ${modeName}`);
      } catch (e) {
        console.error(`  ${boldRed('FAIL')} ${modeName}`);
        console.error(e instanceof Error ? e.message : e);
        failures.push(modeName);
      }
    }
  }

  if (failures.length > 0) {
    console.error(boldRed(`\n${failures.length} case(s) failed.`));
    process.exit(1);
  }

  const totalCases =
    resolveRunCount + haxelibFlagsRunCount + haxelibRunCount + compileCases.length + serverRunCount;
  console.log(boldGreen(`\nAll ${totalCases} E2E cases passed.`));
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
