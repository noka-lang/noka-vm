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
      const m = e.noka_new();
      if (!m) return { kind: 'crash', output: '', detail: 'noka_new returned null' };
      if (src.length > e.noka_disc_cap(m)) {
        e.noka_free(m);
        return { kind: 'clean', output: 'too large for the disc buffer' };
      }
      // noka_new can grow memory, which detaches older views, so take the view after it.
      new Uint8Array(memory.buffer, e.noka_disc_ptr(m), src.length).set(src);
      output = '';
      const status = e.noka_eval(m, src.length);
      e.noka_free(m);
      return { kind: status === 0 || status === 1 ? 'clean' : 'crash', output, detail: `noka_eval returned ${status}` };
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
