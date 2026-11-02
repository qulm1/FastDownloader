// End-to-end CLI tests against controlled HTTP and a private local BitTorrent swarm.
import http from 'node:http';
import net from 'node:net';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';

const home = resolve(import.meta.dirname, '..');
const work = mkdtempSync(join(process.env.TEST_WORK_ROOT || tmpdir(), 'download-realistic-'));
const script = join(home, 'FastDownload.ps1');
const payload = Buffer.alloc(1024 * 1024 + 41);
for (let i = 0; i < payload.length; i++) payload[i] = (i * 17) % 251;
const sha = createHash('sha256').update(payload).digest('hex');
const evidence = [];
const children = new Set();
let requests = 0, seedPort = 0;
function bencode(value) {
  if (Buffer.isBuffer(value)) return Buffer.concat([Buffer.from(value.length + ':'), value]);
  if (typeof value === 'string') return bencode(Buffer.from(value));
  if (typeof value === 'number') return Buffer.from(`i${value}e`);
  if (Array.isArray(value)) return Buffer.concat([Buffer.from('l'), ...value.map(bencode), Buffer.from('e')]);
  return Buffer.concat([Buffer.from('d'), ...Object.keys(value).sort().flatMap(k => [bencode(k), bencode(value[k])]), Buffer.from('e')]);
}
const server = http.createServer((req, res) => {
  requests++;
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/announce') {
    const peer = Buffer.from([127, 0, 0, 1, seedPort >> 8, seedPort & 255]);
    res.end(bencode({ interval: 1, peers: peer })); return;
  }
  if (url.pathname === '/missing') { res.writeHead(404); res.end('missing'); return; }
  if (url.pathname === '/loop') { res.writeHead(302, { Location: '/loop' }); res.end(); return; }
  if (url.pathname === '/redirect') { res.writeHead(307, { Location: '/payload?x=1&y=2' }); res.end(); return; }
  if (url.pathname === '/empty') { res.writeHead(200, { 'Content-Length': 0 }); res.end(); return; }
  const chunked = url.pathname === '/chunked';
  const noRange = url.pathname === '/no-range';
  let start = 0, end = payload.length - 1, status = 200;
  if (req.headers.range && !noRange && !chunked) {
    const m = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
    if (!m) { res.writeHead(416); res.end(); return; }
    start = Number(m[1]); if (m[2]) end = Math.min(Number(m[2]), end);
    if (start > end) { res.writeHead(416); res.end(); return; }
    status = 206;
  }
  const headers = { 'Content-Type': 'application/octet-stream', ETag: '"stable-fixture"' };
  if (!chunked) headers['Content-Length'] = end - start + 1;
  if (!noRange && !chunked) headers['Accept-Ranges'] = 'bytes';
  if (status === 206) headers['Content-Range'] = `bytes ${start}-${end}/${payload.length}`;
  res.writeHead(status, headers);
  if (req.method === 'HEAD') { res.end(); return; }
  res.end(payload.subarray(start, end + 1));
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

async function run(args, { expected = 0, input = '', state = 'state', timeout = 60000 } = {}) {
  return await new Promise((resolveRun, reject) => {
    const p = spawn('powershell.exe', ['-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script,
      '-StateDir', join(work, state), '-DownloadDir', join(work, '下载 数据'), ...args], { windowsHide: true });
    children.add(p); p.stdin.end(input);
    let output = '';
    p.stdout.on('data', b => output += b.toString()); p.stderr.on('data', b => output += b.toString());
    const timer = setTimeout(() => { p.kill(); reject(new Error('timeout: ' + output)); }, timeout);
    p.on('error', e => { clearTimeout(timer); children.delete(p); reject(e); });
    p.on('close', code => {
      clearTimeout(timer); children.delete(p);
      try {
        if (expected === 'failure') assert.notEqual(code, 0, output); else assert.equal(code, expected, output);
        resolveRun({ code, output });
      } catch (e) { reject(e); }
    });
  });
}
function records(state = 'state') {
  const folder = join(work, state, 'jobs');
  if (!existsSync(folder)) return [];
  return readdirSync(folder).filter(id => existsSync(join(folder, id, 'task.json')))
    .map(id => JSON.parse(readFileSync(join(folder, id, 'task.json'), 'utf8').replace(/^\uFEFF/, '')));
}
function verifyRecord(record) {
  assert.equal(record.Status, 'Completed');
  const file = join(record.OutputDir, record.FileName);
  assert.equal(createHash('sha256').update(readFileSync(file)).digest('hex'), sha);
}
function passed(name) { evidence.push({ name, passed: true }); console.log('PASS:', name); }
try {
  const inputs = [
    ['批量.txt', `# comment\n${base}/payload?format=txt\n${base}/payload?format=txt2\n`],
    ['列表.csv', `Source,FileName,Sha256\n${base}/payload?format=csv,中文 安装包.apk,${sha}\n`],
    ['tasks.json', JSON.stringify({ downloads: [{ Source: base + '/payload?format=json', FileName: 'archive.zip', Sha256: sha }] })],
    ['windows.url', `[InternetShortcut]\r\nURL=${base}/payload?format=url\r\n`],
    ['tasks.urls', `${base}/payload?format=urls\n`],
    ['tasks.lst', `${base}/payload?format=lst\n`],
  ];
  for (const [name, data] of inputs) {
    const path = join(work, name); writeFileSync(path, '\uFEFF' + data);
    await run(['-BatchFile', path, '-FileName', 'fixture.bin', '-Sha256', sha]);
  }
  const saved = records(); assert.equal(saved.length, 7); saved.forEach(verifyRecord);
  passed('TXT/CSV/JSON/URL/URLS/LST actual binary downloads and Unicode paths');
  const before = requests;
  await run(['-Source', join(work, 'tasks.json')]);
  assert.equal(requests, before, 'completed task downloaded again');
  const list = await run(['-ListTasks']);
  assert.match(list.output, /已完成/); assert.ok(!list.output.includes('?format='));
  passed('Source file autodetection, completed task skip and task listing without URL disclosure');

  for (const pathName of ['/chunked', '/no-range', '/redirect']) {
    await run(['-Source', base + pathName, '-FileName', pathName.slice(1) + '.bin', '-Sha256', sha]);
    verifyRecord(records().find(r => r.Source === base + pathName));
  }
  await run(['-Source', base + '/empty', '-FileName', 'empty.txt']);
  const empty = records().find(r => r.Source.endsWith('/empty'));
  assert.equal(empty.Status, 'Completed'); assert.equal(statSync(join(empty.OutputDir, 'empty.txt')).size, 0);
  passed('Unknown length, server ignoring Range, 307 redirects and zero-byte files');

  for (const [name, content] of [
    ['invalid.json', JSON.stringify([{ Source: base + '/must-not-start', FileName: '../escape' }])],
    ['option.json', JSON.stringify([{ Source: base + '/must-not-start', Header: 'unexpected' }])],
    ['duplicates.txt', `${base}/same\n${base}/same`],
    ['empty.json', '[]'],
  ]) {
    const path = join(work, name); writeFileSync(path, content); const previous = requests;
    await run(['-BatchFile', path], { expected: 1 }); assert.equal(requests, previous);
  }
  for (const fileName of ['CON.txt', 'trailing.', 'NUL', '../escape']) {
    await run(['-Source', base + '/invalid-name', '-FileName', fileName, '-DryRun'], { expected: 1 });
  }
  passed('Whole-batch preflight, unknown-field rejection, duplicates, empty lists and Windows reserved names');

  await run(['-Source', base + '/payload?wrong-hash', '-Sha256', '0'.repeat(64), '-StopAfterSeconds', '3'], { expected: 'failure' });
  assert.notEqual(records().find(r => r.Source.includes('wrong-hash')).Status, 'Completed');
  const errorBatch = join(work, 'partial.json');
  writeFileSync(errorBatch, JSON.stringify([{ Source: base + '/missing' }, { Source: base + '/payload?after-failure', FileName: 'after.bin', Sha256: sha }]));
  await run(['-BatchFile', errorBatch], { expected: 1 });
  verifyRecord(records().find(r => r.Source.includes('after-failure')));
  passed('Checksum failure never completed; batch continues independent tasks and returns failure');

  // Real private local swarm: aria2 seeder + normal downloader; no public tracker/content.
  const pickPort = net.createServer();
  await new Promise(r => pickPort.listen(0, '127.0.0.1', r)); seedPort = pickPort.address().port;
  await new Promise(r => pickPort.close(r));
  const seedFolder = join(work, 'seed'); mkdirSync(seedFolder);
  const seedBytes = Buffer.alloc(4 * 1024 * 1024); for (let i = 0; i < seedBytes.length; i++) seedBytes[i] = i % 239;
  writeFileSync(join(seedFolder, 'private.bin'), seedBytes);
  const pieces = [];
  for (let i = 0; i < seedBytes.length; i += 262144) pieces.push(createHash('sha1').update(seedBytes.subarray(i, i + 262144)).digest());
  const info = { length: seedBytes.length, name: 'private.bin', 'piece length': 262144, pieces: Buffer.concat(pieces), private: 1 };
  const torrentPath = join(work, '私有 本地.torrent');
  writeFileSync(torrentPath, bencode({ announce: base + '/announce', info }));
  const seed = spawn(join(home, 'bin', 'aria2c.exe'), ['--no-conf=true', '--enable-rpc=false', '--enable-dht=false', '--enable-dht6=false',
    '--enable-peer-exchange=false', '--seed-ratio=0.0', '--seed-time=5', '--check-integrity=true', '--listen-port=' + seedPort,
    '--dir=' + seedFolder, '--console-log-level=notice', torrentPath], { windowsHide: true });
  children.add(seed); let seedOutput = ''; seed.stdout.on('data', b => seedOutput += b); seed.stderr.on('data', b => seedOutput += b);
  await new Promise(r => setTimeout(r, 2000));
  try {
    await run(['-Source', torrentPath, '-StopAfterSeconds', '25'], { timeout: 45000 });
    let task = records().find(r => r.Source === torrentPath);
    assert.equal(task.Status, 'Completed'); assert.ok(readFileSync(join(task.OutputDir, 'private.bin')).equals(seedBytes));
    passed('Actual private torrent transfer with local tracker and SHA-1 pieces');
    const hash = createHash('sha1').update(bencode(info)).digest('hex');
    const magnet = `magnet:?xt=urn:btih:${hash}&tr=${encodeURIComponent(base + '/announce')}`;
    await run(['-Source', magnet, '-StopAfterSeconds', '25'], { timeout: 45000 });
    task = records().find(r => r.Source === magnet);
    assert.equal(task.Status, 'Completed'); assert.ok(readFileSync(join(task.OutputDir, 'private.bin')).equals(seedBytes));
    passed('Actual magnet metadata retrieval and private local content transfer');
  } catch (e) { e.message += '\nSeeder output:\n' + seedOutput; throw e; }
} finally {
  for (const child of children) child.kill();
  server.closeAllConnections(); await new Promise(r => server.close(r));
  writeFileSync(join(work, 'test-evidence.json'), JSON.stringify({ work, evidence }, null, 2));
  console.log('Evidence:', work);
}
