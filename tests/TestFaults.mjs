// Real controlled HTTP failures and restart integrity; no internet or filled disks.
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync,readdirSync,statSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
const home=resolve(import.meta.dirname,'..');
const work=mkdtempSync(join(process.env.TEST_WORK_ROOT||tmpdir(),'download-faults-'));
const old=Buffer.alloc(4*1024*1024,1),changed=Buffer.alloc(old.length,2),sha=x=>createHash('sha256').update(x).digest('hex');
let current=old;
const timers=new Set(),evidence=[];
const server=createServer((req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname;
 if(path==='/loop'){res.writeHead(302,{Location:'/loop'});res.end();return}
 if(path==='/denied'){res.writeHead(403);res.end('forbidden');return}
 if(path==='/stall'){return}
 const bytes=path==='/changing'?current:old;
 let begin=0,end=bytes.length-1,status=200;
 if(req.headers.range){const m=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);begin=+m[1];if(m[2])end=Math.min(+m[2],end);status=206}
 const headers={'Content-Length':end-begin+1,'Accept-Ranges':'bytes','ETag':bytes===old?'"old"':'"new"'};
 if(status===206)headers['Content-Range']=`bytes ${begin}-${end}/${bytes.length}`;
 if(path==='/download')headers['Content-Disposition']="attachment; filename*=UTF-8''%E4%B8%AD%E6%96%87%20%E6%96%87%E6%A1%A3.pdf";
 res.writeHead(status,headers);
 if(req.method==='HEAD'){res.end();return}
 if(path!=='/changing'){res.end(bytes.subarray(begin,end+1));return}
 let at=begin;
 const timer=setInterval(()=>{const next=Math.min(at+16384,end+1);res.write(bytes.subarray(at,next));at=next;if(at>end){clearInterval(timer);timers.delete(timer);res.end()}},30);
 timers.add(timer);res.on('close',()=>{clearInterval(timer);timers.delete(timer)});
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
function rows(){return readdirSync(join(work,'state/jobs')).flatMap(id=>{try{return [JSON.parse(readFileSync(join(work,'state/jobs',id,'task.json'),'utf8').replace(/^\uFEFF/,''))]}catch(e){if(e.code==='ENOENT')return [];throw e}})}
async function run(args,{failure=false}={}){
 return new Promise((ok,fail)=>{
  const outputArgs=args.includes('-DownloadDir')?[]:['-DownloadDir',join(work,'下载 输出')];
  const p=spawn('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',join(home,'FastDownload.ps1'),'-StateDir',join(work,'state'),...outputArgs,...args],{windowsHide:true});let out='';
  p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>out+=x);p.stdin.end();
  const timer=setTimeout(()=>{spawn('taskkill.exe',['/PID',String(p.pid),'/T','/F'],{windowsHide:true});fail(Error('fault test timed out'))},45000);
  p.on('error',fail);p.on('close',code=>{clearTimeout(timer);try{if(failure)assert.notEqual(code,0,out);else assert.equal(code,0,out);ok(out)}catch(e){fail(e)}});
 });
}
try{
 await run(['-Source',base+'/download','-Sha256',sha(old)]);
 let r=rows().find(x=>x.Source.endsWith('/download'));assert.equal(r.Status,'Completed');
 const filename=readdirSync(r.OutputDir)[0];assert.match(filename,/\.pdf$/);assert.equal(sha(readFileSync(join(r.OutputDir,filename))),sha(old));
 evidence.push({name:'No-extension URL with UTF-8 Content-Disposition filename, complete binary hash',passed:true});
 for(const endpoint of ['/loop','/denied','/stall']){
  await run(['-Source',base+endpoint,'-StopAfterSeconds','2'],{failure:true});
  assert.notEqual(rows().find(x=>x.Source.endsWith(endpoint)).Status,'Completed');
 }
 evidence.push({name:'Redirect loop, HTTP403 and stalled response never complete; bounded interruption saves failed/incomplete status',passed:true});
 await run(['-Source',base+'/changing','-Sha256',sha(old),'-StopAfterSeconds','1'],{failure:true});
 current=changed;
 await run(['-Source',base+'/changing','-StopAfterSeconds','12'],{failure:true});
 r=rows().find(x=>x.Source.endsWith('/changing'));assert.notEqual(r.Status,'Completed');
 evidence.push({name:'Remote same-length content/ETag changes after interruption; saved SHA256 rejects mixed/changed result',passed:true});
 await run(['-Source',base+'/changing','-NewTask','-Sha256',sha(changed),'-FileName','new.bin']);
 r=rows().filter(x=>x.Source.endsWith('/changing')).find(x=>x.Status==='Completed');assert.ok(r);assert.equal(sha(readFileSync(join(r.OutputDir,'new.bin'))),sha(changed));
 evidence.push({name:'Changed remote file recovers as independent new task with correct new SHA256',passed:true});
 const concurrent=base+'/changing?concurrent=1';
 const first=run(['-Source',concurrent,'-Sha256',sha(changed),'-StopAfterSeconds','3'],{failure:true});
 for(let i=0;i<50;i++){
  const r=rows().find(x=>x.Source===concurrent);
  if(r?.Status==='Downloading')break;
  await new Promise(resolve=>setTimeout(resolve,50));
 }
 const blocked=await run(['-Source',concurrent],{failure:true});
 assert.match(blocked,/另一个窗口|重复运行/);
 await first;
 evidence.push({name:'Concurrent same task is rejected by real exclusive task lock',passed:true});
 const collision=join(work,'not-a-directory');writeFileSync(collision,'test');
 await run(['-Source',base+'/readonly','-DownloadDir',collision],{failure:true});
 evidence.push({name:'Output path is a file: actionable failure, no claimed completed output',passed:true});
 console.log('PASS: real HTTP failure/recovery cases; evidence '+work);
}finally{for(const timer of timers)clearInterval(timer);server.closeAllConnections();await new Promise(r=>server.close(r));writeFileSync(join(work,'test-evidence.json'),JSON.stringify({work,evidence},null,2));}
