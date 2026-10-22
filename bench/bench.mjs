// Benchmark orchestrator for `zig build bench`. Not a shipped artifact.
//
// Runs every program in bench/programs/ twice over: natively through the ReleaseFast runner, and
// as the shipped ReleaseSmall vm.wasm inside Node. Each program's header declares what it must
// print and how many loop iterations it does:
//
//     // iterations: 10000000
//     // expect: 10000000
//
// Results go to bench/results.json (not committed). Each program and target is compared against
// bench/baseline.json (committed) by its fastest run. More than 10% slower fails the step.
//
//     zig build bench                  run and compare
//     zig build bench -- --update      run and rewrite the baseline
//     zig build bench -- --only NAME   run one program
//     zig build bench -- --runs N      timed runs per program and target (default 5)

import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import os from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
const programsDir = join(here, 'programs');
const baselinePath = join(here, 'baseline.json');
const resultsPath = join(here, 'results.json');
const threshold = 1.10;
let midLine = false; // a progress line is waiting for its " done"

const args = parseArgs(process.argv.slice(2));
const programs = loadPrograms().filter((p) => !args.only || p.name === args.only);
if (programs.length === 0) fail(`no programs found${args.only ? ` named ${args.only}` : ''}`);

const wasm = await loadWasm(args.wasm);
const results = {
  machine: machineName(),
  date: new Date().toISOString(),
  runs: args.runs,
  results: {},
};

for (const program of programs) {
  process.stderr.write(`${program.name} ...`);
  midLine = true;
  results.results[program.name] = {
    iterations: program.iterations,
    native: timeNative(program),
    wasm: timeWasm(program),
  };
  process.stderr.write(' done\n');
  midLine = false;
}

writeFileSync(resultsPath, JSON.stringify(results, null, 2) + '\n');

if (args.update) {
  writeFileSync(baselinePath, JSON.stringify(results, null, 2) + '\n');
  printTable(results, null);
  console.log(`\nbaseline written to ${baselinePath}`);
  process.exit(0);
}

const baseline = existsSync(baselinePath) ? JSON.parse(readFileSync(baselinePath, 'utf8')) : null;
if (baseline && baseline.machine !== results.machine) {
  console.log(`warning: baseline was recorded on "${baseline.machine}", this is "${results.machine}". Comparisons are unreliable.\n`);
}
const regressions = printTable(results, baseline);
if (regressions > 0) fail(`${regressions} benchmark(s) more than ${Math.round((threshold - 1) * 100)}% slower than the baseline`);

// ---- programs ----------------------------------------------------------------------------------

function loadPrograms() {
  return readdirSync(programsDir)
    .filter((f) => f.endsWith('.noka'))
    .sort()
    .map((f) => {
      const path = join(programsDir, f);
      const text = readFileSync(path, 'utf8');
      const header = {};
      const lines = text.split('\n');
      let i = 0;
      for (; i < lines.length && lines[i].startsWith('//'); i++) {
        const m = lines[i].match(/^\/\/\s*(\w+):\s*(.*)$/);
        if (m) header[m[1]] = m[2].trim();
      }
      if (header.expect === undefined) fail(`${f} has no "// expect:" header`);
      return {
        name: basename(f, '.noka'),
        path,
        source: lines.slice(i).join('\n'), // the VM doesn't scan comments yet
        expect: header.expect,
        iterations: header.iterations ? Number(header.iterations) : null,
      };
    });
}

// ---- native ------------------------------------------------------------------------------------

function timeNative(program) {
  const check = spawnSync(args.runner, ['check', program.path], { encoding: 'utf8' });
  if (check.status !== 0) fail(`${program.name} (native) failed:\n${check.stdout}${check.stderr}`);
  expectOutput(program, 'native', check.stdout);

  const run = spawnSync(args.runner, ['time', String(args.runs), program.path], { encoding: 'utf8' });
  if (run.status !== 0) fail(`${program.name} (native) failed while timing:\n${run.stderr}`);
  const line = run.stderr.trim().split('\n').pop();
  return withPerIteration(JSON.parse(line), program);
}

// ---- wasm --------------------------------------------------------------------------------------

async function loadWasm(path) {
  let output = '';
  let memory;
  const decoder = new TextDecoder();
  const imports = {
    env: {
      host_print(ptr, len) {
        output += decoder.decode(new Uint8Array(memory.buffer, ptr, len));
      },
    },
  };
  const { instance } = await WebAssembly.instantiate(readFileSync(path), imports);
  const e = instance.exports;
  memory = e.memory;

  return {
    run(source) {
      const bytes = new TextEncoder().encode(source);
      if (bytes.length > e.disc_cap()) fail('program larger than the disc buffer');
      new Uint8Array(memory.buffer, e.disc_ptr(), bytes.length).set(bytes);
      output = '';
      e.init();
      const status = e.eval(bytes.length);
      return { status, output };
    },
  };
}

function timeWasm(program) {
  const first = wasm.run(program.source);
  if (first.status !== 0) fail(`${program.name} (wasm) failed:\n${first.output}`);
  expectOutput(program, 'wasm', first.output);

  const samples = [];
  for (let i = 0; i < args.runs; i++) {
    const start = process.hrtime.bigint();
    wasm.run(program.source);
    samples.push(Number(process.hrtime.bigint() - start));
  }
  samples.sort((a, b) => a - b);
  return withPerIteration({ min_ns: samples[0], median_ns: samples[Math.floor(args.runs / 2)] }, program);
}

// ---- reporting ---------------------------------------------------------------------------------

function expectOutput(program, target, output) {
  const got = output.trim();
  if (got !== program.expect) fail(`${program.name} (${target}) printed "${got}", expected "${program.expect}"`);
}

function withPerIteration(timing, program) {
  if (program.iterations) timing.ns_per_iteration = round(timing.min_ns / program.iterations, 2);
  return timing;
}

function printTable(current, base) {
  let regressions = 0;
  const rows = [['program', 'target', 'min ms', 'ns/iter', 'baseline ms', 'change']];
  for (const [name, r] of Object.entries(current.results)) {
    for (const target of ['native', 'wasm']) {
      const t = r[target];
      const b = base?.results?.[name]?.[target];
      let change = '';
      if (b) {
        const ratio = t.min_ns / b.min_ns;
        change = `${ratio >= 1 ? '+' : ''}${round((ratio - 1) * 100, 1)}%`;
        if (ratio > threshold) {
          change += '  FAIL';
          regressions++;
        }
      } else if (base) {
        change = 'new';
      }
      rows.push([
        name,
        target,
        round(t.min_ns / 1e6, 2).toString(),
        t.ns_per_iteration?.toString() ?? '',
        b ? round(b.min_ns / 1e6, 2).toString() : '',
        change,
      ]);
    }
  }
  const widths = rows[0].map((_, c) => Math.max(...rows.map((row) => row[c].length)));
  for (const row of rows) console.log(row.map((cell, c) => cell.padEnd(widths[c])).join('  ').trimEnd());
  return regressions;
}

// ---- helpers -----------------------------------------------------------------------------------

function parseArgs(argv) {
  const out = { runs: 5, update: false, only: null, runner: null, wasm: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--update') out.update = true;
    else if (a === '--runs') out.runs = Number(argv[++i]);
    else if (a === '--only') out.only = argv[++i];
    else if (a === '--runner') out.runner = argv[++i];
    else if (a === '--wasm') out.wasm = argv[++i];
    else fail(`unknown argument: ${a}`);
  }
  if (!out.runner || !out.wasm) fail('bench.mjs is run by `zig build bench`, which passes --runner and --wasm');
  if (!Number.isInteger(out.runs) || out.runs < 1) fail('--runs must be a positive integer');
  return out;
}

function machineName() {
  return `${os.cpus()[0]?.model ?? 'unknown cpu'}, ${os.platform()} ${os.arch()}`;
}

function round(n, places) {
  const f = 10 ** places;
  return Math.round(n * f) / f;
}

function fail(message) {
  if (midLine) process.stderr.write('\n');
  console.error(`bench: ${message}`);
  process.exit(1);
}
