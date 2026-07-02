const PAIR_FLAGS = new Set(['-cp', '-p', '--class-path', '-D', '--define']);

/** Tokens that start a new compiler argument (flags and --run-style names). */
function looksLikeFlag(token) {
  return token.startsWith('-');
}

/**
 * @param {string} line
 * @param {string} projectDir
 */
export function normalizePath(line, projectDir) {
  const normalizedProject = projectDir.replace(/\\/g, '/').replace(/\/+$/, '');
  const normalizedLine = line.replace(/\\/g, '/').replace(/\/+/g, '/');

  if (normalizedLine === normalizedProject) {
    return '<fixture>';
  }
  if (normalizedLine.startsWith(normalizedProject + '/')) {
    return '<fixture>' + normalizedLine.slice(normalizedProject.length);
  }
  return normalizedLine;
}

/**
 * @param {string} stdout
 * @param {string} projectDir
 * @returns {string[]}
 */
export function parseLines(stdout, projectDir) {
  return stdout
    .trim()
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => normalizePath(line, projectDir));
}

/**
 * @param {number} actual
 * @param {number} expected
 */
export function exitCodesMatch(actual, expected) {
  return (actual & 0xff) === (expected & 0xff);
}

/**
 * @param {string[]} actual
 * @param {Array<string | { set: string[] }>} expected
 * @param {string} label
 */
export function assertExpected(actual, expected, label = 'output') {
  let ai = 0;

  for (let ei = 0; ei < expected.length; ei++) {
    const exp = expected[ei];

    if (typeof exp === 'object' && exp !== null && 'set' in exp) {
      throw new Error(`${label}: value set must follow a flag in expected definition`);
    }

    if (ai >= actual.length) {
      throw new Error(
        `${label}: expected more tokens at index ${ei}, got only ${actual.length} lines\n` +
          `  missing: ${JSON.stringify(expected.slice(ei))}\n` +
          `  actual: ${JSON.stringify(actual)}`
      );
    }

    const actualToken = actual[ai];

    if (expected[ei + 1] && typeof expected[ei + 1] === 'object' && 'set' in expected[ei + 1]) {
      const flag = /** @type {string} */ (exp);
      const valueSet = /** @type {{ set: string[] }} */ (expected[ei + 1]).set;

      if (actualToken !== flag) {
        throw new Error(
          `${label}: expected flag ${JSON.stringify(flag)} at line ${ai}, got ${JSON.stringify(actualToken)}\n` +
            `  actual: ${JSON.stringify(actual)}`
        );
      }

      ai++;
      const collected = [];

      while (ai < actual.length && !looksLikeFlag(actual[ai])) {
        collected.push(actual[ai]);
        ai++;
      }

      const expectedNormalized = valueSet;
      const missing = expectedNormalized.filter((v) => !collected.includes(v));
      const extra = collected.filter((v) => !expectedNormalized.includes(v));

      if (missing.length > 0 || extra.length > 0) {
        throw new Error(
          `${label}: flag ${JSON.stringify(flag)} value mismatch\n` +
            `  expected set: ${JSON.stringify(expectedNormalized)}\n` +
            `  actual set:   ${JSON.stringify(collected)}`
        );
      }

      ei++;
      continue;
    }

    if (actualToken !== exp) {
      throw new Error(
        `${label}: expected ${JSON.stringify(exp)} at line ${ai}, got ${JSON.stringify(actualToken)}\n` +
          `  expected: ${JSON.stringify(expected)}\n` +
          `  actual:   ${JSON.stringify(actual)}`
      );
    }

    ai++;
  }

  if (ai < actual.length) {
    throw new Error(
      `${label}: unexpected extra lines: ${JSON.stringify(actual.slice(ai))}\n` +
        `  expected: ${JSON.stringify(expected)}`
    );
  }
}

/**
 * @param {string} stdout
 * @param {string} projectDir
 * @param {{ mustNotContain?: string[], mustContainPairs?: Record<string, string[]> }} check
 */
export function assertResolveArgsCheck(stdout, projectDir, check) {
  const lines = parseLines(stdout, projectDir);

  for (const token of check.mustNotContain ?? []) {
    if (lines.includes(token)) {
      throw new Error(`resolve-args check: must not contain ${JSON.stringify(token)}\n  actual: ${JSON.stringify(lines)}`);
    }
  }

  for (const [flag, values] of Object.entries(check.mustContainPairs ?? {})) {
    const collected = [];
    for (let i = 0; i < lines.length; i++) {
      if (lines[i] !== flag) continue;
      let j = i + 1;
      while (j < lines.length && !looksLikeFlag(lines[j])) {
        collected.push(lines[j]);
        j++;
      }
    }

    for (const value of values) {
      const normalized = normalizePath(value, projectDir);
      const found = collected.some(
        (c) => c === normalized || c === value || c.endsWith('/' + value.replace(/^<fixture>\//, ''))
      );
      if (!found) {
        throw new Error(
          `resolve-args check: expected ${JSON.stringify(flag)} value ${JSON.stringify(normalized)}\n` +
            `  collected: ${JSON.stringify(collected)}\n` +
            `  lines: ${JSON.stringify(lines)}`
        );
      }
    }
  }
}
