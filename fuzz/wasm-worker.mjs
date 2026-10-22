// Runs programs through the shipped vm.wasm for fuzz.mjs, one message per program. Lives in a
// worker so a program that never returns can be killed by terminating the worker.

import { parentPort, workerData } from 'node:worker_threads';
import { readFileSync } from 'node:fs';

const bytes = readFileSync(workerData.wasm);
let vm = await instantiate();

async function instantiate() {
  let memory;
  let output = '';
  const decoder = new TextDecoder();
  const { instance } = await WebAssembly.instantiate(bytes, {
    env: {
      host_print(ptr, len) {
        output += decoder.decode(new Uint8Array(memory.buffer, ptr, len));
      },
    },
  });
  const e = instance.exports;
  memory = e.memory;
  return {
    run(source) {
      const src = new TextEncoder().encode(source);
      if (src.length > e.disc_cap()) return { kind: 'clean', output: 'too large for the disc buffer' };
      new Uint8Array(memory.buffer, e.disc_ptr(), src.length).set(src);
      output = '';
      e.init();
      const status = e.eval(src.length);
      return { kind: status === 0 || status === 1 ? 'clean' : 'crash', output, detail: `eval returned ${status}` };
    },
  };
}

parentPort.on('message', async (source) => {
  try {
    parentPort.postMessage(vm.run(source));
  } catch (err) {
    // A trap leaves the instance in an unknown state, so start the next program on a fresh one.
    vm = await instantiate();
    parentPort.postMessage({ kind: 'crash', output: '', detail: `${err.name}: ${err.message}` });
  }
});
