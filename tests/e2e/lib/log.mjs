let verbose = false;

export function setVerbose(enabled) {
  verbose = enabled;
}

export function isVerbose() {
  return verbose;
}

/**
 * @param {string} payload
 */
export function formatFrame(payload) {
  return JSON.stringify(payload);
}

/**
 * @param {string} caseName
 * @param {string} message
 * @param {string} [detail]
 */
export function log(caseName, message, detail) {
  if (!verbose) return;
  console.log(`  [${caseName}] ${message}`);
  if (detail !== undefined && detail !== '') {
    console.log(detail);
  }
}
