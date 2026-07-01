import { readdir, readFile, unlink, access } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { bootstrap } from './lib/bootstrap.mjs';
import { runShim } from './lib/shim.mjs';
import { parseLines, assertExpected, assertResolveArgsCheck, exitCodesMatch } from './lib/assert.mjs';

const e2eRoot = dirname(fileURLToPath(import.meta.url));
const fixturesRoot = join(e2eRoot, 'fixtures');

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

/**
 * @param {{ name: string, projectDir: string, definition: any }} testCase
 */
async function runResolveArgsCase(testCase) {
  const { name, projectDir, definition } = testCase;
  const result = await runShim(projectDir, ['--run', 'resolve-args', ...definition.args]);

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
 * @param {{ name: string, projectDir: string, definition: any }} testCase
 */
async function runCompileCase(testCase) {
  const { name, projectDir, definition } = testCase;

  if (definition.resolveArgsCheck) {
    const resolved = await runShim(projectDir, ['--run', 'resolve-args', ...definition.args]);
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

  const result = await runShim(projectDir, definition.args);

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

async function main() {
  console.log('Bootstrapping E2E environment...');
  bootstrap();

  const resolveCases = await discoverCases('resolve-args');
  const compileCases = await discoverCases('compile');
  const failures = [];

  console.log(`Running ${resolveCases.length} resolve-args cases...`);
  for (const testCase of resolveCases) {
    try {
      await runResolveArgsCase(testCase);
      console.log(`  ok  ${testCase.name}`);
    } catch (e) {
      console.error(`  FAIL ${testCase.name}`);
      console.error(e instanceof Error ? e.message : e);
      failures.push(testCase.name);
    }
  }

  console.log(`Running ${compileCases.length} compile cases...`);
  for (const testCase of compileCases) {
    try {
      await runCompileCase(testCase);
      console.log(`  ok  ${testCase.name}`);
    } catch (e) {
      console.error(`  FAIL ${testCase.name}`);
      console.error(e instanceof Error ? e.message : e);
      failures.push(testCase.name);
    }
  }

  if (failures.length > 0) {
    console.error(`\n${failures.length} case(s) failed.`);
    process.exit(1);
  }

  console.log(`\nAll ${resolveCases.length + compileCases.length} E2E cases passed.`);
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
