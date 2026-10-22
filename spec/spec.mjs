// Spec example suite for `zig build spec`. Not a shipped artifact.
//
// Every fenced code block in LANGUAGE.md is a test case, identified by its section path and its
// position within that section ("Arrays > Length #1"). spec/manifest.json says what each block
// should do, and holds a hash of the block's text so an edited block is caught and re-reviewed:
//
//     run        run it (with optional prelude/epilogue scaffolding); stdout must equal `expect`
//     compiles   a fragment with free names; it must compile (runtime errors are fine)
//     panics     it must stop with a runtime error naming `panic` (a panic kind or message part)
//     skip       not a program (grammar, keyword lists, deliberately invalid illustrations)
//     unstated   runnable, but the spec doesn't state its output; listed for Cam, not guessed
//
// Blocks marked `pending` are expected to fail until the VM implements what they use. A pending
// block that passes is reported, and `-- --update` clears or sets `pending` to match today's VM.
// A non-pending block that fails, a crash, an unclassified block or a changed block fails the step.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const languagePath = join(here, '..', 'LANGUAGE.md');
const manifestPath = join(here, 'manifest.json');
const testable = new Set(['run', 'compiles', 'panics']);

const args = parseArgs(process.argv.slice(2));
const blocks = extractBlocks(readFileSync(languagePath, 'utf8'));
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));

const problems = [];
const promoted = [];
const results = [];

for (const block of blocks) {
  const entry = manifest[block.id];
  if (!entry) {
    problems.push(`unclassified block: [${block.id}] at LANGUAGE.md:${block.line}`);
    continue;
  }
  if (entry.hash !== block.hash) {
    problems.push(`changed since classified: [${block.id}] at LANGUAGE.md:${block.line} (re-review it, then update its hash to ${block.hash})`);
    continue;
  }
  if (!testable.has(entry.kind)) {
    results.push({ block, entry, status: entry.kind });
    continue;
  }

  const outcome = run(block, entry);
  const pass = judge(entry, outcome);
  if (outcome.kind === 'crash') problems.push(`VM crashed on [${block.id}] at LANGUAGE.md:${block.line}: ${outcome.detail}`);
  else if (!pass && !entry.pending) problems.push(`regression: [${block.id}] at LANGUAGE.md:${block.line} ${explain(entry, outcome)}`);
  if (pass && entry.pending) promoted.push(block.id);
  if (args.update) entry.pending = pass ? undefined : true;
  results.push({ block, entry, status: pass ? 'pass' : 'pending', outcome });
}

for (const id of Object.keys(manifest)) {
  if (!blocks.some((b) => b.id === id)) problems.push(`manifest entry with no matching block: [${id}]`);
}

if (args.update) writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
report();
if (problems.length > 0) {
  console.log('');
  for (const p of problems) console.log(`FAIL ${p}`);
  process.exit(1);
}

// ---- extraction --------------------------------------------------------------------------------

function extractBlocks(text) {
  const out = [];
  const counts = new Map();
  let heading = [];
  let inBlock = false;
  let lines = [];
  let start = 0;
  text.split('\n').forEach((line, i) => {
    if (!inBlock) {
      const m = line.match(/^(#+) (.*)$/);
      if (m) heading = [...heading.slice(0, m[1].length - 1), m[2]];
      if (line.startsWith('```')) {
        inBlock = true;
        lines = [];
        start = i + 1;
      }
      return;
    }
    if (line.startsWith('```')) {
      const section = heading.slice(1).join(' > ');
      const n = (counts.get(section) ?? 0) + 1;
      counts.set(section, n);
      const body = lines.join('\n');
      out.push({ id: `${section} #${n}`, line: start, text: body, hash: createHash('sha1').update(body).digest('hex').slice(0, 10) });
      inBlock = false;
    } else {
      lines.push(line);
    }
  });
  return out;
}

// ---- running -----------------------------------------------------------------------------------

function run(block, entry) {
  const program = [entry.prelude, block.text, entry.epilogue].filter((s) => s !== undefined).join('\n');
  const r = spawnSync(args.noka, [], { input: program, encoding: 'utf8', timeout: 3000 });
  const output = (r.stdout ?? '') + (r.stderr ?? '');
  if (r.error?.code === 'ETIMEDOUT') return { kind: 'crash', detail: 'timed out after 3 s', output };
  if (r.signal) return { kind: 'crash', detail: `killed by ${r.signal}`, output };
  if (r.status === 0) return { kind: 'ok', stdout: r.stdout ?? '', output };
  if (r.status === 1) return { kind: /compile error/.test(output) ? 'compile_error' : 'runtime_error', output };
  return { kind: 'crash', detail: `exit status ${r.status}`, output };
}

function judge(entry, outcome) {
  switch (entry.kind) {
    case 'run':
      return outcome.kind === 'ok' && outcome.stdout.trimEnd() === entry.expect.join('\n');
    case 'compiles':
      return outcome.kind === 'ok' || outcome.kind === 'runtime_error';
    case 'panics':
      return outcome.kind === 'runtime_error' && outcome.output.includes(entry.panic);
  }
  return false;
}

function explain(entry, outcome) {
  const got = outcome.output.trim().split('\n').slice(0, 3).join(' | ');
  if (entry.kind === 'run') return `expected "${entry.expect.join(' | ')}", got ${outcome.kind}: "${got}"`;
  if (entry.kind === 'panics') return `expected a runtime error naming "${entry.panic}", got ${outcome.kind}: "${got}"`;
  return `expected it to compile, got ${outcome.kind}: "${got}"`;
}

// ---- reporting ---------------------------------------------------------------------------------

function report() {
  const count = (s) => results.filter((r) => r.status === s).length;
  const total = results.filter((r) => testable.has(r.entry.kind)).length;
  if (args.verbose) {
    for (const r of results) console.log(`${r.status.padEnd(8)} [${r.block.id}]`);
    console.log('');
  }
  console.log(`spec examples: ${count('pass')} of ${total} testable blocks pass (${count('pending')} pending), ${count('skip')} skipped, ${count('unstated')} with unstated output, ${blocks.length} blocks in LANGUAGE.md`);
  if (promoted.length > 0) {
    console.log(args.update ? '\nnow passing, pending cleared:' : `\nnow passing but still marked pending (run \`zig build spec -- --update\`):`);
    for (const id of promoted) console.log(`  [${id}]`);
  }
  const unstated = results.filter((r) => r.status === 'unstated');
  if (unstated.length > 0 && args.verbose) {
    console.log('\nunstated output (for Cam):');
    for (const r of unstated) console.log(`  [${r.block.id}] LANGUAGE.md:${r.block.line}: ${r.entry.reason}`);
  }
}

function parseArgs(argv) {
  const out = { noka: null, update: false, verbose: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--noka') out.noka = argv[++i];
    else if (a === '--update') out.update = true;
    else if (a === '--verbose' || a === '-v') out.verbose = true;
    else {
      console.error(`spec: unknown argument: ${a}`);
      process.exit(1);
    }
  }
  if (!out.noka) {
    console.error('spec.mjs is run by `zig build spec`, which passes --noka');
    process.exit(1);
  }
  return out;
}
