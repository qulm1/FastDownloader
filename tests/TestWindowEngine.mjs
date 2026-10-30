import http from 'node:http';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import assert from 'node:assert/strict';
const work=mkdtempSync(join(process.env.TEST_WORK_ROOT || 'D:/','window-engine-'));
const bytes=Buffer.alloc(8*1024*1024+79);for(let i=0;i<bytes.length;i++)bytes[i]=i%251;
let ranges=0;
const server=http.createServer((req,res)=>{
 let start=0,end=bytes.length-1,code=200;
 if(req.headers.range){const m=/bytes=(\d+)-(\d*)/.exec(req.headers.range);start=+m[1];if(m[2])end=Math.min(+m[2],end);code=206;ranges++;}
 const headers={'Content-Length':end-start+1,'Accept-Ranges':'bytes','ETag':'"window-v1"'};
 if(code===206)headers['Content-Range']=`bytes ${start}-${end}/${bytes.length}`;
 res.writeHead(code,headers);if(req.method==='HEAD'){res.end();return;}
 let at=start;
 const timer=setInterval(()=>{const next=Math.min(at+32768,end+1);res.write(bytes.subarray(at,next));at=next;if(at>end){clearInterval(timer);res.end();}},30);
 res.on('close',()=>clearInterval(timer));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url=`http://127.0.0.1:${server.address().port}/test?token=local-only&download=1`;
try{
 for(const test of ['TestWindowEngine.ps1','TestWindowFlow.ps1'])await new Promise((ok,fail)=>{
  const p=spawn('powershell.exe',['-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',join(import.meta.dirname,test),test==='TestWindowFlow.ps1'?'-NetworkSource':'-Source',url,'-WorkRoot',work],{windowsHide:true});
  let out='';p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>out+=x);p.stdin.end();
  const timer=setTimeout(()=>{spawn('taskkill.exe',['/PID',String(p.pid),'/T','/F'],{windowsHide:true});fail(Error('timeout: '+out));},90000);
  p.on('error',fail);p.on('close',code=>{clearTimeout(timer);try{assert.equal(code,0,out);ok();}catch(e){fail(e);}});
 });
 const report=JSON.parse(readFileSync(join(work,'window-engine-evidence.json'),'utf8').replace(/^\uFEFF/,''));
 const actual=readFileSync(report.output);assert.deepEqual(actual,bytes);assert.ok(ranges>0);
 report.sha256=createHash('sha256').update(actual).digest('hex');report.range_requests=ranges;
 writeFileSync(join(work,'window-engine-evidence.json'),JSON.stringify(report,null,2));
 const flow=JSON.parse(readFileSync(join(work,'window-flow','flow-evidence.json'),'utf8').replace(/^\uFEFF/,''));
 assert.deepEqual(readFileSync(flow.output),bytes);flow.sha256=createHash('sha256').update(bytes).digest('hex');
 writeFileSync(join(work,'window-flow','flow-evidence.json'),JSON.stringify(flow,null,2));
 console.log('PASS: engine and hidden window backend: actual HTTP pause, resume, recovery and full SHA256; '+work);
}finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
