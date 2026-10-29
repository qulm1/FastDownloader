import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readdirSync,readFileSync,writeFileSync,copyFileSync,mkdirSync} from 'node:fs';
import {join,resolve} from 'node:path';
const home=resolve(import.meta.dirname,'..');
const work=mkdtempSync(join(process.env.TEST_WORK_ROOT||'D:/CodexNightWork/2026-10-24','launcher-'));
const body=Buffer.alloc(1024*1024,73);
const server=createServer((req,res)=>{res.writeHead(200,{'Content-Length':body.length});res.end(body)});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url=`http://127.0.0.1:${server.address().port}/launcher.bin`;
const evidence=[];
async function run(exe,args,input,expected=0){
 return new Promise((ok,fail)=>{
  const p=spawn(exe,args,{cwd:home,windowsHide:true});let out='';
  p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>out+=x);
  const timer=setTimeout(()=>{spawn('taskkill.exe',['/PID',String(p.pid),'/T','/F'],{windowsHide:true});fail(Error('launcher timed out'))},45000);
  p.on('error',fail);p.on('close',code=>{clearTimeout(timer);try{assert.equal(code,expected,out);ok(out)}catch(e){fail(e)}});
  p.stdin.end(input);
 });
}
try{
 await run('cmd.exe',['/d','/c','StartDownload.cmd'],url+'\r\nQ\r\n');
 const jobs=join(home,'state/jobs');
 const record=readdirSync(jobs).map(id=>JSON.parse(readFileSync(join(jobs,id,'task.json'),'utf8').replace(/^\uFEFF/,''))).find(x=>x.Source===url);
 assert.ok(record);assert.equal(record.Status,'Completed');assert.match(record.OutputDir,/^D:\\Downloads\\FastDownloads\\/i);
 const files=readdirSync(record.OutputDir).filter(n=>!n.endsWith('.aria2'));assert.equal(files.length,1);
 assert.equal(createHash('sha256').update(readFileSync(join(record.OutputDir,files[0]))).digest('hex'),createHash('sha256').update(body).digest('hex'));
 evidence.push({name:'Exact default StartDownload.cmd entry, interactive URL/Q, clean state, D default output, complete SHA256',passed:true,output:record.OutputDir});
 const missing=join(work,'缺少依赖 测试');mkdirSync(missing);
 for(const name of ['FastDownload.ps1','BatchDownload.ps1'])copyFileSync(join(home,name),join(missing,name));
 const out=await run('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',join(missing,'FastDownload.ps1'),'-Source',url,'-StateDir',join(work,'missing-state'),'-DownloadDir',join(work,'missing-output')],'',1);
 assert.match(out,/aria2c\.exe/);evidence.push({name:'Missing engine produces actionable error and failure exit',passed:true});
 console.log('PASS: default launcher and missing dependency; evidence '+work);
}finally{server.closeAllConnections();await new Promise(r=>server.close(r));writeFileSync(join(work,'test-evidence.json'),JSON.stringify({work,evidence},null,2));}
