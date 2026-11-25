import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { cpus, platform, release, tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { performance } from 'node:perf_hooks';

const [inputDir, baselinePath] = process.argv.slice(2);
assert.ok(inputDir && process.argv.length <= 4,
  'Usage: node examples/performance/datasets.mjs DATA_DIRECTORY [BASELINE_EXECUTABLE]');
const current = ['relsift.exe', 'relsift']
  .map(file => resolve('_build/native/release/build/cmd/relsift', file))
  .find(existsSync);
assert.ok(current, 'Build cmd/relsift in native release mode first');
const temporary = mkdtempSync(join(tmpdir(), 'relsift-bench-'));
const generated = [];
const workLimit = '100000000';
const searchWidth = '4';
const repetitions = 7;
const workloads = [
  ['penguins.csv', ',', 'F204DB2C753B0937CAAC3CB35258562C14F073E4BBC76BE24B4C51CE22767A93'],
  ['winequality-red.csv', ';', '4A402CF041B025D4566D954C3B9BA8635A3A8A01E039005D97D6A710278CF05E'],
  ['winequality-white.csv', ';', '76C3F809815C17C07212622F776311FAEB31E87610D52C26D87D6E361B169836'],
];

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex').toUpperCase();
}

function save(file, contents) {
  writeFileSync(file, contents);
  generated.push(file);
}

function loadInput(file, delimiter, expectedHash) {
  const raw = readFileSync(join(inputDir, file));
  const hash = sha256(raw);
  assert.equal(hash, expectedHash, file);
  const text = new TextDecoder('utf-8', { fatal: true }).decode(raw);
  const lines = text.trimEnd().split(/\r?\n/);
  // These fixtures have quoted headers at most, and no quoted data cells.
  const headers = lines[0].split(delimiter).map(s => s.replace(/^"|"$/g, ''));
  const rows = lines.slice(1).map(line => {
    assert.ok(!line.includes('"'), 'Unexpected quoted data cell');
    const values = line.split(delimiter);
    assert.equal(values.length, headers.length, 'Unexpected input row width');
    return values;
  });
  if (delimiter === ';') assert.ok(!text.includes(','), 'Unexpected comma in wine data');
  const input = join(temporary, file);
  save(input, delimiter === ',' ? raw : text.replaceAll(';', ','));
  return {
    input,
    metadata: {
      source_sha256: hash,
      input_sha256: sha256(readFileSync(input)),
      rows: rows.length,
      columns: headers.length,
      cardinalities_in_source_order: headers.map((_, i) => new Set(rows.map(row => row[i])).size),
      duplicate_rows: rows.length - new Set(rows.map(row => JSON.stringify(row))).size,
    },
  };
}

function invoke(executable, args) {
  const start = performance.now();
  const result = spawnSync(executable, args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, timeout: 60000 });
  const elapsed = performance.now() - start;
  assert.ifError(result.error);
  assert.ok([0, 3].includes(result.status), result.stdout + result.stderr);
  return { elapsed, report: JSON.parse(result.stdout) };
}

function measure(executable, args) {
  const { report } = invoke(executable, args);
  const samples = [];
  for (let i = 0; i < repetitions; i++) {
    const run = invoke(executable, args);
    assert.deepEqual(run.report, report);
    samples.push(Number(run.elapsed.toFixed(3)));
  }
  samples.sort((a, b) => a - b);
  return { report, samples_ms: samples, median_ms: samples[Math.floor(repetitions / 2)] };
}

function summarize(measured, mode) {
  const { report, ...times } = measured;
  const table = report.tables[0];
  return {
    ...times,
    status: table.status,
    usage: table.usage,
    ...(mode === 'discover'
      ? { fds: table.fds.length, uccs: table.uccs.length }
      : { checked: table.checked_rules, baseline_rules: table.baseline_rules }),
  };
}

try {
  console.log(JSON.stringify({
    platform: platform(), os_release: release(), cpu: cpus()[0]?.model, node: process.version,
    repetitions, warmups: 1, max_work: workLimit,
    max_lhs: Number(searchWidth), max_ucc_width: Number(searchWidth),
  }));
  for (const [file, delimiter, hash] of workloads) {
    const { input, metadata } = loadInput(file, delimiter, hash);
    const discovery = measure(current, [
      'discover', input, '--max-lhs', searchWidth, '--max-ucc-width', searchWidth, '--max-work', workLimit,
    ]);
    assert.equal(discovery.report.status.kind, 'complete_in_domain');
    const baseline = join(temporary, basename(file, '.csv') + '-report.json');
    save(baseline, JSON.stringify(discovery.report));
    const args = ['compare', input, baseline, '--max-work', workLimit];
    const replay = measure(current, args);
    assert.equal(replay.report.status.kind, 'complete_in_domain');
    assert.ok(replay.report.tables[0].checks.every(x => x.outcome.kind === 'held_minimal'));
    const entry = {
      file, ...metadata, discovery: summarize(discovery, 'discover'), replay: summarize(replay, 'compare'),
    };
    if (baselinePath) {
      const earlier = measure(resolve(baselinePath), args);
      const priorChecks = earlier.report.tables[0].checks;
      assert.deepEqual(priorChecks, replay.report.tables[0].checks.slice(0, priorChecks.length));
      entry.prior_replay = summarize(earlier, 'compare');
    }
    console.log(JSON.stringify(entry));
  }
} finally {
  for (const file of generated) unlinkSync(file);
  rmdirSync(temporary);
}
