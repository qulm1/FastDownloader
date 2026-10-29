// Local-only integration tests. Never downloads copyrighted or third-party BT content.
import http from 'node:http';
import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';

const script = resolve(import.meta.dirname, '..', 'FastDownload.ps1');
const work = mkdtempSync(join(process.env.TEST_WORK_ROOT || tmpdir(), 'fastdownloader-test-'));
const data = Buffer.alloc(16 * 1024 * 1024);
for (let i = 0; i < data.length; i++) data[i] = i % 251;
const sha = createHash('sha256').update(data).digest('hex');
const stats = { ranges: 0, queries: [] };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  stats.queries.push(url.search);
  if (url.pathname === '/redirect') { res.writeHead(302, { Location: '/file.bin?token=abc&download=1' }); res.end(); return; }
  if (!['/file.bin', '/slow.bin'].includes(url.pathname)) { res.writeHead(404); res.end('not found'); return; }
  let start = 0, end = data.length - 1, code = 200;
  if (req.headers.range) {
    const match = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
    if (!match) { res.writeHead(416); res.end(); return; }
    start = Number(match[1]); if (match[2]) end = Math.min(Number(match[2]), end);
    if (start > end) { res.writeHead(416); res.end(); return; }
    code = 206; stats.ranges++;
  }
  const headers = { 'Content-Type': 'application/octet-stream', 'Content-Length': end - start + 1, 'Accept-Ranges': 'bytes', ETag: '"fixture-v1"', 'Content-Disposition': 'attachment; filename="fixture.bin"' };
  if (code === 206) headers['Content-Range'] = `bytes ${start}-${end}/${data.length}`;
  res.writeHead(code, headers);
  if (req.method === 'HEAD') { res.end(); return; }
  if (url.pathname !== '/slow.bin') { res.end(data.subarray(start, end + 1)); return; }
  let at = start;
  const timer = setInterval(() => {
    const next = Math.min(at + 32768, end + 1);
    res.write(data.subarray(at, next)); at = next;
    if (at > end) { clearInterval(timer); res.end(); }
  }, 35);
  res.on('close', () => clearInterval(timer));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
function run(extra, expected = 0, input = '') {
  return new Promise((resolveRun, reject) => {
    const p = spawn('powershell.exe', ['-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, '-DownloadDir', join(work, 'downloads'), '-StateDir', join(work, 'state'), ...extra], { windowsHide: true });
    p.stdin.end(input);
    let output = ''; p.stdout.on('data', b => output += b.toString()); p.stderr.on('data', b => output += b.toString());
    const timer = setTimeout(() => { p.kill(); reject(new Error('Test timed out')); }, 45000);
    p.on('error', e => { clearTimeout(timer); reject(e); });
    p.on('close', code => { clearTimeout(timer); try { assert.equal(code, expected, output); resolveRun(output); } catch (e) { reject(e); } });
  });
}
function records() {
  const root = join(work, 'state', 'jobs');
  return readdirSync(root).map(id => JSON.parse(readFileSync(join(root, id, 'task.json'), 'utf8').replace(/^\uFEFF/, '')));
}
function assertFile(record) {
  const file = join(record.OutputDir, 'fixture.bin');
  assert.equal(statSync(file).size, data.length);
  assert.equal(createHash('sha256').update(readFileSync(file)).digest('hex'), sha);
}
try {
  await run(['-Source', base + '/redirect', '-Sha256', sha, '-Connections', '8']);
  let task = records().find(r => r.Source.endsWith('/redirect'));
  assert.equal(task.Status, 'Completed'); assertFile(task);
  assert.ok(stats.queries.includes('?token=abc&download=1'), 'query ampersand was corrupted');
  console.log('PASS: HTTP redirect, ampersand URL, file download and SHA-256');

  await run(['-Source', base + '/slow.bin', '-Sha256', sha, '-StopAfterSeconds', '2'], 7);
  task = records().find(r => r.Source.endsWith('/slow.bin'));
  assert.equal(task.Status, 'Incomplete');
  assert.ok(statSync(join(task.JobFolder, 'unfinished.session')).size > 0);
  const rangesBefore = stats.ranges;
  await run([], 0, 'r\n1\nq\n');
  task = records().find(r => r.Source.endsWith('/slow.bin'));
  assert.equal(task.Status, 'Completed'); assertFile(task);
  assert.ok(stats.ranges > rangesBefore, 'resume did not use HTTP Range');
  console.log('PASS: interrupted download, saved task/session, range resume and checksum');

  await run(['-Source', 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=test&tr=https%3A%2F%2Fexample.com%2Fannounce', '-DryRun']);
  await run(['-Source', 'magnet:?xt=urn:btmh:1220abcd', '-DryRun'], 1);
  await run(['-Source', 'https://example.com/a.zip', '-FileName', '..\bad.zip', '-DryRun'], 1);
  await run(['-Source', 'https://example.com/a.zip', '-Referer', 'https://example.com/', '-Proxy', 'http://127.0.0.1:7890', '-DryRun']);
  console.log('PASS: magnet parsing, unsupported v2 rejection, path validation, optional parameters');

  // Valid v1 torrent for our own 4-byte payload: parse locally, never join a swarm.
  const tiny = Buffer.from('test');
  const pieceHash = createHash('sha1').update(tiny).digest();
  const torrent = Buffer.concat([Buffer.from('d4:infod6:lengthi4e4:name8:test.txt12:piece lengthi16384e6:pieces20:'), pieceHash, Buffer.from('ee')]);
  const torrentPath = join(work, '本地 测试.torrent'); writeFileSync(torrentPath, torrent);
  await run(['-Source', torrentPath, '-DryRun']);
  await new Promise((ok, fail) => {
    const p = spawn(resolve(import.meta.dirname, '..', 'bin', 'aria2c.exe'), ['--no-conf=true', '--show-files=true', torrentPath], { windowsHide: true });
    p.on('error', fail); p.on('close', code => code === 0 ? ok() : fail(new Error('Torrent parse failed')));
  });
  console.log('PASS: Unicode/space torrent path and aria2 v1 torrent parsing (offline)');
  console.log('ALL TESTS PASSED; temporary test files: ' + work);
} finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
