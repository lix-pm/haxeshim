import { spawn } from 'node:child_process';
import { createConnection, createServer } from 'node:net';
import { getShimPath } from './bootstrap.mjs';
import { formatFrame, log } from './log.mjs';

const DEFAULT_TIMEOUT_MS = 10_000;

/**
 * @param {string | Buffer} payload
 * @returns {Buffer}
 */
export function encodeFrame(payload) {
  const body = typeof payload === 'string' ? Buffer.from(payload) : payload;
  const frame = Buffer.alloc(4 + body.length);
  frame.writeInt32LE(body.length, 0);
  body.copy(frame, 4);
  return frame;
}

/**
 * @param {import('node:net').Socket} socket
 * @param {number} timeoutMs
 * @returns {Promise<Buffer>}
 */
export function readFrameFromSocket(socket, timeoutMs = DEFAULT_TIMEOUT_MS) {
  return new Promise((resolve, reject) => {
    let buffer = Buffer.alloc(0);
    let expectedLength = null;
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      socket.destroy();
      reject(new Error('Timed out reading frame from socket'));
    }, timeoutMs);

    function finish(err, result) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.removeListener('data', onData);
      socket.removeListener('error', onError);
      if (err) reject(err);
      else resolve(result);
    }

    function onError(err) {
      finish(err);
    }

    function onData(chunk) {
      buffer = Buffer.concat([buffer, chunk]);

      while (true) {
        if (expectedLength === null) {
          if (buffer.length < 4) return;
          expectedLength = buffer.readInt32LE(0);
          buffer = buffer.slice(4);
        }

        if (buffer.length >= expectedLength) {
          const payload = buffer.slice(0, expectedLength);
          const extra = buffer.slice(expectedLength);
          if (extra.length > 0) {
            socket.unshift(extra);
          }
          finish(null, payload);
          return;
        }
        return;
      }
    }

    socket.on('data', onData);
    socket.on('error', onError);
  });
}

/**
 * @returns {Promise<number>}
 */
export function getFreePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close();
        reject(new Error('Failed to allocate a free port'));
        return;
      }
      const { port } = address;
      server.close((err) => {
        if (err) reject(err);
        else resolve(port);
      });
    });
    server.on('error', reject);
  });
}

/**
 * @param {number} port
 * @param {number} timeoutMs
 */
function tryConnect(port, timeoutMs) {
  return new Promise((resolve, reject) => {
    const socket = createConnection({ host: '127.0.0.1', port });
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error(`Timed out connecting to 127.0.0.1:${port}`));
    }, timeoutMs);

    socket.once('connect', () => {
      clearTimeout(timer);
      socket.end();
      resolve();
    });

    socket.once('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

/**
 * @param {number} port
 * @param {number} timeoutMs
 */
export async function waitForPort(port, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    try {
      await tryConnect(port, Math.max(deadline - Date.now(), 1));
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }

  throw new Error(`Server did not accept connections on 127.0.0.1:${port} within ${timeoutMs}ms`);
}

/**
 * @param {string} projectDir
 * @param {number} port
 * @param {{ caseName?: string }} [options]
 */
export function spawnWaitServer(projectDir, port, { caseName } = {}) {
  const shim = getShimPath();
  const cmd = `${process.execPath} ${shim} --wait ${port}`;
  log(caseName ?? 'server', `spawn: ${cmd} (cwd=${projectDir})`);

  const child = spawn(process.execPath, [shim, '--wait', String(port)], {
    cwd: projectDir,
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stderr = '';
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString();
  });

  return {
    process: child,
    getStderr: () => stderr,
    kill() {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill();
      }
    },
  };
}

/**
 * @param {string} projectDir
 * @param {number} port
 * @param {{ caseName?: string }} [options]
 */
export function spawnConnectClient(projectDir, port, { caseName } = {}) {
  const shim = getShimPath();
  const target = `127.0.0.1:${port}`;
  const cmd = `${process.execPath} ${shim} --server-connect ${target}`;
  log(caseName ?? 'server', `spawn: ${cmd} (cwd=${projectDir})`);

  const child = spawn(process.execPath, [shim, '--server-connect', target], {
    cwd: projectDir,
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stderr = '';
  child.stderr.on('data', (chunk) => {
    stderr += chunk.toString();
  });

  return {
    process: child,
    getStderr: () => stderr,
    kill() {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill();
      }
    },
  };
}

/**
 * @param {number} timeoutMs
 * @returns {Promise<{ port: number, waitForConnection(): Promise<import('node:net').Socket>, writeFrame(args: string[]): Promise<void>, readFrame(): Promise<Buffer>, close(): void }>}
 */
export async function createMockIdeServer(timeoutMs = DEFAULT_TIMEOUT_MS) {
  const port = await getFreePort();

  return new Promise((resolve, reject) => {
    const server = createServer();
    /** @type {import('node:net').Socket | null} */
    let socket = null;
    /** @type {((socket: import('node:net').Socket) => void) | null} */
    let onConnect = null;

    server.on('error', reject);

    server.listen(port, '127.0.0.1', () => {
      resolve({
        port,
        waitForConnection() {
          if (socket) return Promise.resolve(socket);

          return new Promise((res, rej) => {
            const timer = setTimeout(() => {
              rej(new Error(`Mock IDE on 127.0.0.1:${port} did not receive a connection within ${timeoutMs}ms`));
            }, timeoutMs);

            onConnect = (sock) => {
              clearTimeout(timer);
              socket = sock;
              res(sock);
            };
          });
        },
        async writeFrame(args) {
          if (!socket) throw new Error('Mock IDE: no connected client');
          const payload = args.join('\n');
          socket.write(encodeFrame(payload));
        },
        async readFrame() {
          if (!socket) throw new Error('Mock IDE: no connected client');
          return readFrameFromSocket(socket, timeoutMs);
        },
        close() {
          server.close();
          socket?.destroy();
        },
      });
    });

    server.on('connection', (sock) => {
      if (onConnect) {
        onConnect(sock);
        onConnect = null;
      } else {
        socket = sock;
      }
    });
  });
}

/**
 * @param {number} port
 * @param {string[]} args
 * @param {{ timeoutMs?: number, caseName?: string }} [options]
 * @returns {Promise<{ response: string }>}
 */
export function sendWaitCompileRequest(port, args, { timeoutMs = DEFAULT_TIMEOUT_MS, caseName } = {}) {
  const requestPayload = args.join('\n') + '\0';
  log(caseName ?? 'server', `wait request: ${formatFrame(requestPayload)}`);

  return new Promise((resolve, reject) => {
    const socket = createConnection({ host: '127.0.0.1', port });
    let response = '';
    let settled = false;

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      socket.destroy();
      reject(new Error(`Timed out waiting for compile response on 127.0.0.1:${port}`));
    }, timeoutMs);

    function finish(err, result) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (err) reject(err);
      else {
        log(caseName ?? 'server', `wait response (${result.response.length} bytes):`, result.response);
        resolve(result);
      }
    }

    socket.on('data', (chunk) => {
      response += chunk.toString();
    });

    socket.on('error', (err) => finish(err));
    socket.on('end', () => finish(null, { response }));
    socket.on('close', () => finish(null, { response }));

    socket.once('connect', () => {
      socket.write(requestPayload);
    });
  });
}

/**
 * @param {{ writeFrame(args: string[]): Promise<void>, readFrame(): Promise<Buffer> }} mock
 * @param {string[]} args
 * @param {{ caseName?: string }} [options]
 * @returns {Promise<{ response: string }>}
 */
export async function sendConnectCompileRequest(mock, args, { caseName } = {}) {
  const payload = args.join('\n');
  log(caseName ?? 'server', `connect frame (${payload.length} bytes):`, payload);

  await mock.writeFrame(args);
  const responseBuffer = await mock.readFrame();
  const response = responseBuffer.toString();

  log(caseName ?? 'server', `connect response (${response.length} bytes):`, response);
  return { response };
}
