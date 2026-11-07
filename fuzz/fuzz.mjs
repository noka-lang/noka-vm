// Fuzz harness for `zig build fuzz`. Not a shipped artifact.
//
// Generates random programs and runs each through the Debug native CLI (where Zig's safety checks
// abort on undefined behavior) and the shipped ReleaseSmall vm.wasm (where `unreachable` traps).
// A program may succeed, fail with a clean compile or runtime error, or run past the time limit
// (reported as a hang, not a failure, until the hang guard exists). Anything else is a crash.
//
// Crashing inputs are shrunk and saved to fuzz/corpus/, which is replayed first on every run, so
// each one stays a failing regression test until the VM is fixed.
//
//     zig build fuzz                       replay the corpus, then 1000 new programs from a random seed
//     zig build fuzz -- --count N          new programs to generate
//     zig build fuzz -- --seed N           reproduce a run
//     zig build fuzz -- --replay-only      only replay the corpus

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Worker } from 'node:worker_threads';

const here = dirname(fileURLToPath(import.meta.url));
const corpusDir = join(here, 'corpus');
const timeoutMs = 2000;

// Token vocabulary for the generators.
const keywords = ['case', 'end', 'while', 'for', 'in', 'stop', 'next', 'fn', 'do', 'this', 'and', 'or', 'not', 'band', 'bor', 'bnot', 'bxor', 'true', 'false', 'nil', 'if', 'ret', 'err', 'catch'];
const operators = ['+', '-', '*', '/', '%', '=', ':', '#', '<', '>', '.', '?', '++', '--', '+=', '-=', '*=', '/=', '%=', '==', '!=', '<=', '>=', '->', '|>', '**', '<<', '>>', '??', '?.', '?[', '?(', '?:', '**=', '<<=', '>>=', '(', ')', '[', ']', '{', '}', ','];
const literals = ['0', '1', '-1', '42', '3.14', '0.5', '1e308', '9007199254740993', '0xFF', '0x7fffffff', '0b101', '0x', '0b', '"a"', '""', '"hello"', "'x'", '"\\n"', 'f"{1}"', '"unterminated'];
const names = ['a', 'b', 'c', 'x', 'y', 'i', '_', 'print', 'len', 'init'];

const args = parseArgs(process.argv.slice(2));
const wasm = startWasm();
const crashes = [];
const seenSignatures = new Set(); // target + crash message, so one bug is saved once per run
let repeats = 0;
let hangs = 0;
let clean = 0;
const cleanBy = { ok: 0, compile: 0, runtime: 0 }; // native outcome of clean programs

// ---- corpus replay -----------------------------------------------------------------------------

const corpus = existsSync(corpusDir) ? readdirSync(corpusDir).filter((f) => f.endsWith('.noka')).sort() : [];
for (const file of corpus) {
  const source = readFileSync(join(corpusDir, file), 'utf8');
  const result = await check(source);
  if (result.crash) {
    crashes.push({ file, source, ...result.crash, fromCorpus: true });
    seenSignatures.add(`${result.crash.target}:${result.crash.detail}`);
  }
}
console.log(`corpus: ${corpus.length} input(s) replayed, ${crashes.length} still crash`);

// ---- generation --------------------------------------------------------------------------------

if (!args.replayOnly) {
  const rand = mulberry32(args.seed);
  for (let i = 0; i < args.count; i++) {
    // Core-mode programs stick to what the compiler accepts today, so they reach the runtime.
    // Full-mode programs use the whole spec and mostly exercise the scanner and compiler.
    const r = rand();
    const source = r < 0.2 ? tokenSoup(rand) : r < 0.6 ? grammarProgram(rand, true) : mutate(grammarProgram(rand, false), rand);
    const result = await check(source);
    if (result.hang) hangs++;
    else if (!result.crash) {
      clean++;
      cleanBy[result.how]++;
    }
    else if (seenSignatures.has(`${result.crash.target}:${result.crash.detail}`)) repeats++;
    else {
      seenSignatures.add(`${result.crash.target}:${result.crash.detail}`);
      const small = await shrink(source, result.crash.target);
      const file = `${createHash('sha1').update(small).digest('hex').slice(0, 10)}.noka`;
      if (!existsSync(join(corpusDir, file))) {
        mkdirSync(corpusDir, { recursive: true });
        writeFileSync(join(corpusDir, file), small);
        const again = await check(small);
        crashes.push({ file, source: small, ...(again.crash ?? result.crash), fromCorpus: false });
      }
    }
    if ((i + 1) % 250 === 0) process.stderr.write(`  ${i + 1}/${args.count}\n`);
  }
  console.log(`generated: ${args.count} programs from seed ${args.seed}: ${clean} clean (${cleanBy.ok} ran, ${cleanBy.compile} compile errors, ${cleanBy.runtime} runtime errors), ${hangs} hung past ${timeoutMs} ms, ${crashes.filter((c) => !c.fromCorpus).length} new crash(es)${repeats ? `, ${repeats} more input(s) hitting an already-seen crash` : ''}`);
}

await wasm.stop();

if (crashes.length > 0) {
  console.log('');
  for (const c of crashes) {
    console.log(`CRASH (${c.target}) fuzz/corpus/${c.file}${c.fromCorpus ? '' : '  [new]'}`);
    console.log(`  ${c.detail}`);
    console.log(c.source.split('\n').map((l) => `  | ${l}`).join('\n'));
  }
  process.exit(1);
}

// ---- running -----------------------------------------------------------------------------------

async function check(source) {
  const native = runNative(source);
  if (native.kind === 'crash') return { crash: { target: 'native', detail: native.detail } };
  const w = await wasm.run(source);
  if (w.kind === 'crash') return { crash: { target: 'wasm', detail: w.detail } };
  return { hang: native.kind === 'hang' || w.kind === 'hang', how: native.how };
}

function runNative(source) {
  const r = spawnSync(args.noka, [], { input: source, encoding: 'utf8', timeout: timeoutMs });
  if (r.error?.code === 'ETIMEDOUT') return { kind: 'hang' };
  const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  if (r.signal) return { kind: 'crash', detail: `killed by ${r.signal}: ${firstLine(r.stderr)}` };
  if (r.status === 0) return { kind: 'clean', how: 'ok' };
  // A failed program prints its crash report to stderr, and the report's first line is the reason.
  const reason = r.status === 1 ? (r.stderr ?? '').split('\n')[0] : '';
  if (reason === 'compile') return { kind: 'clean', how: 'compile' };
  if (/^(disc|frozen|math|oom|type|undefined)$/.test(reason)) return { kind: 'clean', how: 'runtime' };
  return { kind: 'crash', detail: `exit ${r.status}: ${firstLine(out)}` };
}

function startWasm() {
  let worker = spawn();
  function spawn() {
    return new Worker(join(here, 'wasm-worker.mjs'), { workerData: { wasm: args.wasm } });
  }
  return {
    run(source) {
      return new Promise((resolve) => {
        const timer = setTimeout(async () => {
          worker.removeAllListeners('message');
          await worker.terminate();
          worker = spawn();
          resolve({ kind: 'hang' });
        }, timeoutMs);
        worker.once('message', (msg) => {
          clearTimeout(timer);
          resolve(msg);
        });
        worker.postMessage(source);
      });
    },
    stop: () => worker.terminate(),
  };
}

// Greedy shrinking: drop whole lines, then single tokens, keeping each removal only while the
// input still crashes on the same target.
async function shrink(source, target) {
  const stillCrashes = async (s) => s.trim() !== '' && (await check(s)).crash?.target === target;
  let current = source;

  let lines = current.split('\n');
  for (let i = lines.length - 1; i >= 0; i--) {
    const candidate = [...lines.slice(0, i), ...lines.slice(i + 1)];
    if (await stillCrashes(candidate.join('\n'))) lines = candidate;
  }
  current = lines.join('\n');

  let parts = current.split(/(\s+)/); // whitespace runs kept as their own parts
  for (let i = parts.length - 1; i >= 0; i--) {
    if (/^\s*$/.test(parts[i])) continue;
    const candidate = [...parts.slice(0, i), ...parts.slice(i + 1)];
    if (await stillCrashes(candidate.join(''))) parts = candidate;
  }
  current = parts.join('');

  // Tidy whitespace so the same minimal input always gets the same corpus file name.
  const tidy = current.split('\n').map((l) => l.trim().replace(/\s+/g, ' ')).filter((l) => l !== '').join('\n');
  return (await stillCrashes(tidy)) ? tidy : current;
}

// ---- generators --------------------------------------------------------------------------------


function tokenSoup(rand) {
  const n = 1 + Math.floor(rand() * 40);
  const parts = [];
  for (let i = 0; i < n; i++) {
    const r = rand();
    if (r < 0.15) parts.push('\n');
    else parts.push(pick(rand, r < 0.4 ? operators : r < 0.6 ? keywords : r < 0.8 ? literals : names));
  }
  return parts.join(' ');
}

function grammarProgram(rand, core) {
  const ctx = { rand, core, vars: [], loops: 0 };
  const lines = [];
  const n = 1 + Math.floor(rand() * 8);
  for (let i = 0; i < n; i++) lines.push(...statement(ctx, 0));
  return lines.join('\n');
}

function statement(ctx, depth) {
  const { rand } = ctx;
  const r = rand();
  const indent = '  '.repeat(depth);
  if (r < 0.3) {
    const name = `v${ctx.vars.length}`;
    const value = expr(ctx, 0); // before the push, so a declaration never reads itself
    ctx.vars.push(name);
    return [`${indent}${name} ${rand() < 0.8 ? ':' : '#'} ${value}`];
  }
  if (r < 0.45 && ctx.vars.length > 0) {
    const name = pick(rand, ctx.vars);
    return [`${indent}${name} ${ctx.core ? '=' : pick(rand, ['=', '+=', '-=', '*=', '%='])} ${expr(ctx, 0)}`];
  }
  if (r < 0.55 && depth < 3 && ctx.loops < 3) {
    // Bounded loop: a fresh counter that always advances.
    ctx.loops++;
    const counter = `k${ctx.loops}`;
    const body = [`${indent}  ${counter} = ${counter} + 1`];
    if (rand() < 0.3) body.push(`${indent}  case ${counter} > ${Math.floor(rand() * 5)} -> ${pick(rand, ['stop', 'next', `stop ${counter}`])}`);
    for (let i = 0; i < 1 + Math.floor(rand() * 3); i++) body.push(...statement(ctx, depth + 1));
    return [`${indent}${counter} : 0`, `${indent}while ${counter} < ${Math.floor(rand() * 20)}`, ...body, `${indent}end`];
  }
  if (r < 0.65 && depth < 3) {
    const body = [];
    for (let i = 0; i < 1 + Math.floor(rand() * 3); i++) body.push(...statement(ctx, depth + 1));
    return [`${indent}do`, ...body, `${indent}end`];
  }
  if (r < 0.75 && depth < 3) {
    const arms = [];
    for (let i = 0; i < 1 + Math.floor(rand() * 3); i++) arms.push(`${indent}  ${expr(ctx, 1)} -> ${expr(ctx, 1)}`);
    if (rand() < 0.5) arms.push(`${indent}  _ -> ${expr(ctx, 1)}`);
    return [`${indent}case`, ...arms, `${indent}end`];
  }
  return [`${indent}${expr(ctx, 0)}`];
}

function expr(ctx, depth) {
  const { rand } = ctx;
  const r = rand();
  if (depth > 4 || r < 0.3) {
    const a = rand();
    if (a < 0.5 && ctx.vars.length > 0) return pick(rand, ctx.vars);
    if (a < 0.6) return pick(rand, ctx.core ? names.filter((n) => n !== '_' && n !== 'init') : names);
    return pick(rand, literals.filter((l) => !l.startsWith('"unterminated') && l !== '0x' && l !== '0b' && !(ctx.core && /^0[xb]|^f"|e/.test(l))));
  }
  if (r < 0.6) return `${expr(ctx, depth + 1)} ${pick(rand, ['+', '-', '*', '/', '%', '**', '==', '!=', '<', '>', '<=', '>=', 'and', 'or', 'band', 'bor', 'bxor', '<<', '>>', '??', 'in'])} ${expr(ctx, depth + 1)}`;
  if (ctx.core && r >= 0.9) return `(${expr(ctx, depth + 1)})`; // no single-line do yet
  if (r < 0.7) return `${pick(rand, ['-', 'not ', 'bnot '])}${expr(ctx, depth + 1)}`;
  if (r < 0.8) return `(${expr(ctx, depth + 1)})`;
  if (r < 0.85) return `${expr(ctx, depth + 1)}?`;
  if (r < 0.9) return `case ${expr(ctx, depth + 1)} -> ${expr(ctx, depth + 1)}`;
  return `do ${expr(ctx, depth + 1)} end`;
}

function mutate(source, rand) {
  if (rand() < 0.5) return source;
  const parts = source.split(/(\s+)/);
  for (let m = 0; m < 1 + Math.floor(rand() * 3); m++) {
    const i = Math.floor(rand() * parts.length);
    const r = rand();
    if (r < 0.33) parts.splice(i, 1);
    else if (r < 0.66) parts.splice(i, 0, parts[i] ?? '');
    else parts[i] = pick(rand, [...operators, ...keywords, ...literals]);
  }
  return parts.join('');
}

// ---- helpers -----------------------------------------------------------------------------------

function pick(rand, list) {
  return list[Math.floor(rand() * list.length)];
}

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function firstLine(s) {
  return (s ?? '').trim().split('\n').find((l) => l.trim() !== '') ?? '';
}

function parseArgs(argv) {
  const out = { noka: null, wasm: null, count: 1000, seed: Math.floor(Math.random() * 2 ** 31), replayOnly: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--noka') out.noka = argv[++i];
    else if (a === '--wasm') out.wasm = argv[++i];
    else if (a === '--count') out.count = Number(argv[++i]);
    else if (a === '--seed') out.seed = Number(argv[++i]);
    else if (a === '--replay-only') out.replayOnly = true;
    else {
      console.error(`fuzz: unknown argument: ${a}`);
      process.exit(1);
    }
  }
  if (!out.noka || !out.wasm) {
    console.error('fuzz.mjs is run by `zig build fuzz`, which passes --noka and --wasm');
    process.exit(1);
  }
  return out;
}
