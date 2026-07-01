import { styleText } from 'node:util';

let disabled = false;

export function setColorEnabled(enabled) {
  disabled = !enabled;
}

/**
 * @param {string | string[]} format
 * @param {string} text
 */
function fmt(format, text) {
  if (disabled) return text;
  return styleText(format, text);
}

export const green = (t) => fmt('green', t);
export const red = (t) => fmt('red', t);
export const cyan = (t) => fmt('cyan', t);
export const dim = (t) => fmt('dim', t);
export const bold = (t) => fmt('bold', t);
export const boldGreen = (t) => fmt(['bold', 'green'], t);
export const boldRed = (t) => fmt(['bold', 'red'], t);
