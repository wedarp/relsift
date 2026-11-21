import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, writeFileSync, unlinkSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

// The pinned MoonBit toolchain also emits a .exe suffix for Linux ELF binaries.
const executable = ['relsift.exe', 'relsift']
  .map(name => resolve('_build/native/release/build/cmd/relsift', name))
  .find(existsSync);
assert.ok(executable, 'Build the native release CLI before running integration tests.');
const temporary = mkdtempSync(join(tmpdir(), 'relsift-cli-'));
const created = [];
function fixture(name, content) {
  const path = join(temporary, name);
  writeFileSync(path, content);
  created.push(path);
  return path;
}
after(() => {
  for (const path of created) unlinkSync(path);
  rmdirSync(temporary);
});
function run(args, expected = 0) {
  const result = spawnSync(executable, args, { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, expected, result.stdout + result.stderr);
  return { raw: result.stdout.trim(), json: JSON.parse(result.stdout) };
}
const orderArgs = ['discover', 'examples/orders.csv', '--table-id', 'orders'];
const rows = [ ['O1', '1', 'P1', 'Pen'], ['O1', '2', 'P2', 'Book'], ['O2', '1', 'P2', 'Book'], ['O2', '2', 'P1', 'Pen'] ];
const positions = { order_id: 0, line_no: 1, product_id: 2, product_name: 3 };

test('all observed rules, minimality evidence and duplicate multiplicity', () => {
  const result = run(orderArgs);
  const table = result.json.tables[0];
  assert.equal(result.json.status.kind, 'complete_in_domain');
  assert.equal(table.fds.length, 8);
  assert.equal(table.uccs.length, 5);
  function pair(evidence, parent, rhs) {
    const a = rows[Number(evidence.pair.first.slice(1)) - 1];
    const b = rows[Number(evidence.pair.second.slice(1)) - 1];
    assert.ok(a && b);
    for (const column of parent) assert.equal(a[positions[column]], b[positions[column]]);
    if (rhs) assert.notEqual(a[positions[rhs]], b[positions[rhs]]);
  }
  for (const fd of table.fds) {
    assert.equal(fd.minimality, 'proven');
    assert.equal(fd.deletions.length, fd.lhs.length);
    for (const e of fd.deletions) pair(e, fd.lhs.filter(c => c !== e.removed), fd.rhs);
  }
  for (const key of table.uccs) {
    assert.equal(key.deletions.length, key.columns.length);
    for (const e of key.deletions) pair(e, key.columns.filter(c => c !== e.removed));
  }
  const duplicate = run(['discover', 'examples/orders-duplicate.csv', '--table-id', 'orders']).json.tables[0];
  assert.deepEqual(duplicate.fds, table.fds);
  assert.deepEqual(duplicate.uccs, []);
  assert.equal(run(orderArgs).raw, result.raw);
});

test('independent validation exits distinguish success and concrete failure', () => {
  const failure = run(['verify', 'examples/orders.csv', 'examples/verify-fd.json', '--table-id', 'orders'], 1).json;
  assert.deepEqual(failure.counterexample, { first: 'r1', second: 'r2' });
  assert.equal(failure.holds, false);
  assert.equal(run(['verify', 'examples/orders.csv', 'examples/verify-unique.json', '--table-id', 'orders']).json.holds, true);
  const ind = run(['verify', 'examples/exports.json', 'examples/verify-ind.json'], 1).json;
  assert.deepEqual(ind.orphans, ['P3']);
  assert.equal(ind.orphan_count, 1);
});

test('only successful directed INDs are returned', () => {
  const result = run(['ind', 'examples/exports.json']).json;
  assert.deepEqual(result.relations, [{ source_table: 'orders', source_column: 'product_id', target_table: 'products', target_column: 'product_id', source_distinct: 2, target_distinct: 3, target_unique: true }]);
});

test('budget exhaustion is partial, never absence or failure', () => {
  for (const [option, value] of [['--max-work', '0'], ['--max-candidates', '0'], ['--max-results', '0']]) {
    const result = run([...orderArgs, option, value], 3).json;
    assert.equal(result.status.kind, 'partial');
    assert.equal(result.tables[0].status.kind, 'partial');
    assert.deepEqual(result.tables[0].uccs, []);
  }
  const domain = run([...orderArgs, '--max-lhs', '0', '--max-ucc-width', '1']).json.tables[0];
  assert.equal(domain.status.kind, 'complete_in_domain');
  assert.deepEqual(domain.fds, []);
  assert.deepEqual(domain.uccs, []);
});

test('invalid CSV, UTF-8, options and JSON are execution failures', () => {
  const files = [
    fixture('width.csv', 'a,b\n1\n'),
    fixture('quote.csv', 'a\n"unterminated'),
    fixture('headers.csv', 'a,a\n1,2'),
    fixture('utf8.csv', Buffer.from([0x61, 0x0a, 0xc3, 0x28])),
    fixture('duplicate.json', '{"schema_version":1,"schema_version":1,"null_policy":"reject","tables":[]}'),
  ];
  for (const file of files) assert.equal(run(['discover', file], 2).json.status.kind, 'failed');
  assert.equal(run([...orderArgs, '--unknown', '1'], 2).json.status.kind, 'failed');
  assert.equal(run([...orderArgs, '--max-work', '-1'], 2).json.status.kind, 'failed');
  assert.equal(run([], 2).json.status.kind, 'failed');
});

test('JSON null policy and exact lexical values survive real IO', () => {
  const envelope = { schema_version: 1, null_policy: 'equal', tables: [{ id: 't', columns: [{ id: 'c', name: 'c' }], rows: [null, '', '01', '1', 'é', 'é'].map((cell, i) => ({ id: `r${i}`, cells: [cell] })) }] };
  const file = fixture('null.json', JSON.stringify(envelope));
  const result = run(['discover', file]).json.tables[0];
  assert.equal(result.null_policy, 'equal');
  assert.deepEqual(result.uccs[0].columns, ['c']);
  const bad = fixture('reject.json', JSON.stringify({ ...envelope, null_policy: 'reject' }));
  assert.equal(run(['discover', bad], 2).json.status.kind, 'failed');
});

test('bounded diagnostics aggregate exact failures and provenance', () => {
  const report = run(['diagnose', 'examples/orders.csv', 'examples/verify-fd.json', '--table-id', 'orders'], 1).json;
  assert.equal(report.counts_complete, true);
  assert.equal(report.conflicting_groups, 2);
  assert.equal(report.violating_pairs, '2');
  assert.deepEqual(report.groups[0].rows, ['r1', 'r2']);
  const partial = run(['diagnose', 'examples/orders.csv', 'examples/verify-fd.json', '--table-id', 'orders', '--max-results', '0'], 3).json;
  assert.equal(partial.holds, false);
  assert.equal(partial.counts_complete, false);
  const ind = run(['diagnose', 'examples/exports.json', 'examples/verify-ind.json'], 1).json;
  assert.deepEqual(ind.groups, [{ value: 'P3', source_rows: ['p3'] }]);
});

test('serialized report certificates can be replayed and tampering is rejected', () => {
  const discovery = run(orderArgs).json;
  const file = fixture('certificate.json', JSON.stringify(discovery));
  const verified = run(['verify-report', 'examples/orders.csv', file, '--table-id', 'orders']).json;
  assert.equal(verified.valid, true);
  assert.equal(verified.checked_fds, 8);
  assert.equal(verified.checked_uccs, 5);
  assert.equal(verified.completeness_verified, false);
  const tampered = structuredClone(discovery);
  tampered.tables[0].fds[0].deletions[0].pair.first = 'unknown';
  const invalid = fixture('tampered.json', JSON.stringify(tampered));
  assert.equal(run(['verify-report', 'examples/orders.csv', invalid, '--table-id', 'orders'], 1).json.valid, false);
  const partial = run([...orderArgs, '--max-results', '0'], 3).json;
  const partialFile = fixture('partial-certificate.json', JSON.stringify(partial));
  assert.equal(run(['verify-report', 'examples/orders.csv', partialFile, '--table-id', 'orders']).json.reported_status.kind, 'partial');
});

test('snapshot replay separates violations, lost minimality and unfinished checks', () => {
  const baseline = fixture('baseline.json', JSON.stringify(run(orderArgs).json));
  const args = ['compare', 'examples/orders-duplicate.csv', baseline, '--table-id', 'orders'];
  const changed = run(args, 1).json;
  const checks = changed.tables[0].checks;
  assert.equal(checks.filter(c => c.outcome.kind === 'violated').length, 5);
  assert.equal(checks.filter(c => c.outcome.kind === 'held_minimal').length, 8);
  assert.equal(changed.new_rules_searched, false);
  const oneRow = fixture('one-row.csv', 'order_id,line_no,product_id,product_name\nO1,1,P1,Pen\n');
  const smaller = run(['compare', oneRow, baseline, '--table-id', 'orders']).json;
  assert.ok(smaller.tables[0].checks.every(c => c.outcome.kind === 'held_nonminimal'));
  assert.equal(run([...args, '--max-candidates', '0'], 3).json.status.kind, 'partial');
});

test('stepped CLI retains full proofs and honors cumulative resource limits', () => {
  const batch = run(orderArgs).json.tables[0];
  for (const quota of ['1', '7', '1000']) {
    const stepped = run(['discover-stepped', ...orderArgs.slice(1), '--step-candidates', quota]).json.tables[0];
    assert.deepEqual(stepped.fds, batch.fds);
    assert.deepEqual(stepped.uccs, batch.uccs);
    assert.equal(stepped.usage.candidates, batch.usage.candidates);
    assert.equal(stepped.usage.partitions, batch.usage.partitions);
  }
  const partial = run(['discover-stepped', ...orderArgs.slice(1), '--step-candidates', '1', '--max-candidates', '3'], 3).json;
  assert.equal(partial.tables[0].usage.candidates, 3);
  assert.equal(run(['discover-stepped', ...orderArgs.slice(1), '--step-candidates', '0'], 2).json.status.kind, 'failed');
});

test('fractional integer fields fail instead of being silently truncated', () => {
  const report = run(orderArgs).json;
  report.tables[0].limits.max_lhs = 2.5;
  const certificate = fixture('fractional-report.json', JSON.stringify(report));
  assert.equal(run(['verify-report', 'examples/orders.csv', certificate, '--table-id', 'orders'], 2).json.status.kind, 'failed');
  const rule = fixture('fractional-rule.json', JSON.stringify({ kind: 'ind', source_table: 'products', source_column: 'product_id', target_table: 'orders', target_column: 'product_id', orphan_limit: 0.5 }));
  for (const command of ['verify', 'diagnose']) {
    assert.equal(run([command, 'examples/exports.json', rule], 2).json.status.kind, 'failed');
  }
});
