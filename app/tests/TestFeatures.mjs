// Interface, network flags and task-list behaviour. Local fixtures only.
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync,mkdirSync,existsSync,statSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import assert from 'node:assert/strict';

const home=resolve(import.meta.dirname,'..');
const script=join(home,'FastDownload.ps1');
const work=mkdtempSync(join(process.env.TEST_WORK_ROOT||tmpdir(),'download-features-'));
const body=Buffer.alloc(2*1024*1024,23);
const sha=createHash('sha256').update(body).digest('hex');
const server=createServer((req,res)=>{res.writeHead(200,{'Content-Length':body.length});res.end(body)});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url=`http://127.0.0.1:${server.address().port}/file.bin`;
const evidence=[];
const passed=name=>{console.log('PASS:',name);evidence.push({name,passed:true});};

function run(args,input){
  return new Promise((ok,fail)=>{
    const p=spawn('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',script,...args],{windowsHide:true});
    let out='';
    p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>out+=x);
    const timer=setTimeout(()=>{spawn('taskkill.exe',['/PID',String(p.pid),'/T','/F'],{windowsHide:true});fail(Error(out+'\nTimed out'))},90000);
    p.on('error',e=>{clearTimeout(timer);fail(e)});
    p.on('close',code=>{clearTimeout(timer);ok({code,out})});
    p.stdin.end(input||'');
  });
}
function runCommand(command){
  return new Promise((ok,fail)=>{
    const p=spawn('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-Command',command],{windowsHide:true});
    let out='';
    p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>out+=x);
    p.on('close',code=>ok({code,out}));
    p.on('error',fail);
  });
}
function stateDir(name){const path=join(work,name);mkdirSync(path,{recursive:true});return path;}
function readTask(state,id){
  const file=join(state,'jobs',id,'task.json');
  return JSON.parse(readFileSync(file,'utf8').replace(/^\uFEFF/,''));
}

try{
  const help=await run(['-Help']);
  assert.equal(help.code,0,help.out);
  assert.match(help.out,/FastDownloader 2\.1\.0/);
  for(const flag of ['-MaxSpeed','-MaxUpload','-UseSystemProxy','-Header','-HttpUser','-ShowHash','-NoColor']){
    assert.ok(help.out.includes(flag),'help mentions '+flag);
  }
  passed('-Help lists the current interface');

  const gitStyle=await runCommand(`(Get-Help '${script}' -Full | Out-String)`);
  assert.equal(gitStyle.code,0,gitStyle.out);
  // Headings are localized, so assert on the parameter names the help carries instead.
  assert.ok(gitStyle.out.includes('-MaxSpeed'),'Get-Help exposes -MaxSpeed');
  assert.ok(gitStyle.out.includes('-UseSystemProxy'),'Get-Help exposes -UseSystemProxy');
  assert.ok(gitStyle.out.includes('-HttpPassword'),'Get-Help exposes -HttpPassword');
  assert.ok(gitStyle.out.includes('aria2'),'Get-Help carries the description');
  passed('Get-Help -Full renders the comment-based help');

  const dryBase=await run(['-Source',url,'-DryRun','-StateDir',stateDir('dry-base'),'-DownloadDir',join(work,'out-dry')]);
  assert.equal(dryBase.code,0,dryBase.out);
  const base=JSON.parse(dryBase.out.trim());

  const dryFlags=await run([
    '-Source',url,'-DryRun','-StateDir',stateDir('dry-flags'),'-DownloadDir',join(work,'out-dry'),
    '-MaxSpeed','2M','-MaxUpload','512K','-UserAgent','Fixture/1.0',
    '-Header','X-Fixture: 1','-HttpUser','fixture','-HttpPassword','secret-pw'
  ]);
  assert.equal(dryFlags.code,0,dryFlags.out);
  const flagged=JSON.parse(dryFlags.out.trim());
  assert.equal(flagged.ArgumentCount,base.ArgumentCount+4,'speed, header, user and password each add one aria2 flag');
  assert.ok(!dryFlags.out.includes('secret-pw'),'dry run must not echo the password');
  assert.equal(flagged.Destination,base.Destination);
  passed('network flags change the aria2 argument list and stay redacted in -DryRun');

  const badHeader=await run(['-Source',url,'-DryRun','-StateDir',stateDir('bad-header'),'-DownloadDir',join(work,'out-dry'),'-Header','Not A Header']);
  assert.equal(badHeader.code,1,badHeader.out);
  assert.match(badHeader.out,/请求头格式不正确/);

  const orphanPassword=await run(['-Source',url,'-DryRun','-StateDir',stateDir('bad-pass'),'-DownloadDir',join(work,'out-dry'),'-HttpPassword','only-password']);
  assert.equal(orphanPassword.code,1,orphanPassword.out);
  assert.match(orphanPassword.out,/HttpPassword 需要同时提供 HttpUser/);

  const badSpeed=await run(['-Source',url,'-DryRun','-StateDir',stateDir('bad-speed'),'-DownloadDir',join(work,'out-dry'),'-MaxSpeed','2X']);
  assert.notEqual(badSpeed.code,0,'an invalid rate must be rejected by parameter binding');
  passed('invalid header, orphan password and invalid rate are rejected before any network work');

  const listState=stateDir('list');
  const doneOut=join(work,'out-list','示例 文件');
  const todoOut=join(work,'out-list','老任务');
  mkdirSync(doneOut,{recursive:true});mkdirSync(todoOut,{recursive:true});
  writeFileSync(join(doneOut,'file.zip'),Buffer.alloc(1258291,1));
  writeFileSync(join(todoOut,'old.bin'),Buffer.alloc(2097152,2));
  mkdirSync(join(listState,'jobs','aaa111'),{recursive:true});
  mkdirSync(join(listState,'jobs','bbb222'),{recursive:true});
  writeFileSync(join(listState,'jobs','aaa111','task.json'),JSON.stringify({
    Id:'aaa111',Source:'https://example.com/a.zip',Type:'URL',Label:'示例 文件',DownloadDir:work,
    OutputDir:doneOut,Status:'Completed',UpdatedAt:'2026-10-30T15:02:11',TotalBytes:1258291
  }),'utf8');
  // Old record shape: no TotalBytes, no 2.1 fields. The list must still work.
  writeFileSync(join(listState,'jobs','bbb222','task.json'),JSON.stringify({
    Id:'bbb222',Source:'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',Type:'BT',
    Label:'老任务',OutputDir:todoOut,Status:'Incomplete',UpdatedAt:'2026-10-29T09:11:00'
  }),'utf8');
  const list=await run(['-ListTasks','-StateDir',listState]);
  assert.equal(list.code,0,list.out);
  assert.match(list.out,/状态\s+大小\s+类型\s+名称/);
  assert.match(list.out,/已完成\s+1\.2 MB\s+URL\s+示例 文件/);
  assert.match(list.out,/未完成\s+2\.0 MB\s+BT\s+老任务/);
  passed('task list renders an aligned table, sizes included, and tolerates 2.0 records');

  const dlState=stateDir('download');
  const dl=await run(['-Source',url,'-Sha256',sha,'-StateDir',dlState,'-DownloadDir',join(work,'out-dl'),
    '-MaxSpeed','4M','-MaxUpload','0','-Header','X-Fixture: 1']);
  assert.equal(dl.code,0,dl.out);
  assert.match(dl.out,/完成/);
  assert.match(dl.out,/文件\s+file\.bin/);
  assert.match(dl.out,/大小\s+2\.0 MB/);
  assert.match(dl.out,/SHA-256 通过/);
  assert.match(dl.out,/位置\s+/);
  const recordId=readdirSync(join(dlState,'jobs'))[0];
  const record=readTask(dlState,recordId);
  assert.equal(record.Status,'Completed');
  assert.equal(record.MaxSpeed,'4M');
  assert.equal(record.MaxUpload,'0');
  assert.deepEqual(record.Header,['X-Fixture: 1']);
  assert.ok(!record.UserAgent,'no custom user agent was recorded');
  assert.ok(record.TotalBytes>=body.length,'record stores the finished size');
  assert.ok(record.ElapsedSeconds>=0,'record stores the elapsed time');
  assert.ok(record.FinishedAt,'record stores the finish time');
  const downloaded=join(record.OutputDir,'file.bin');
  assert.ok(existsSync(downloaded));
  assert.equal(statSync(downloaded).size,body.length);
  assert.equal(createHash('sha256').update(readFileSync(downloaded)).digest('hex'),sha);
  passed('download reports size, time, speed and checksum; record keeps the new fields');

  const shown=await run(['-Source',url,'-NewTask','-ShowHash','-StateDir',dlState,'-DownloadDir',join(work,'out-dl')]);
  assert.equal(shown.code,0,shown.out);
  assert.ok(shown.out.includes(sha),'the computed SHA-256 is printed');
  passed('-ShowHash prints the computed SHA-256');

  const proxy=await run(['-Source',url,'-UseSystemProxy','-DryRun','-StateDir',stateDir('proxy'),'-DownloadDir',join(work,'out-dry')]);
  assert.equal(proxy.code,0,proxy.out);
  passed('-UseSystemProxy falls back cleanly when no system proxy is configured');

  const banner=await run(['-StateDir',stateDir('banner'),'-DownloadDir',join(work,'out-banner')],'q\n');
  assert.equal(banner.code,0,banner.out);
  assert.match(banner.out,/FastDownloader 2\.1\.0/);
  assert.match(banner.out,/粘贴链接或清单路径/);
  assert.match(banner.out,/> /);
  passed('interactive mode shows the banner, the caret prompt and honours Q');
}finally{
  server.closeAllConnections();
  await new Promise(r=>server.close(r));
  writeFileSync(join(work,'test-evidence.json'),JSON.stringify({work,evidence},null,2));
  console.log('Evidence:',work);
}
