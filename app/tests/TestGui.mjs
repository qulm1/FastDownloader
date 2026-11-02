import http from 'node:http';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
const work=mkdtempSync(join(process.env.TEST_WORK_ROOT||tmpdir(),'wpf-gui-'));
const bytes=Buffer.alloc(6*1024*1024+31);for(let i=0;i<bytes.length;i++)bytes[i]=(i*11)%251;
const sha=createHash('sha256').update(bytes).digest('hex');let ranges=0;
let seedPort=0,seed=null;
function bencode(v){
 if(Buffer.isBuffer(v))return Buffer.concat([Buffer.from(v.length+':'),v]);
 if(typeof v==='string')return bencode(Buffer.from(v));
 if(typeof v==='number')return Buffer.from('i'+v+'e');
 return Buffer.concat([Buffer.from('d'),...Object.keys(v).sort().flatMap(k=>[bencode(k),bencode(v[k])]),Buffer.from('e')]);
}
const server=http.createServer((req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname;
 if(path==='/announce'){res.end(bencode({interval:1,peers:Buffer.from([127,0,0,1,seedPort>>8,seedPort&255])}));return;}
 if(path==='/missing'){res.writeHead(404);res.end();return;}
 const unknown=path==='/unknown';let first=0,last=bytes.length-1,code=200;
 if(req.headers.range&&!unknown){const m=/bytes=(\d+)-(\d*)/.exec(req.headers.range);first=+m[1];if(m[2])last=Math.min(+m[2],last);code=206;ranges++;}
 const headers={'Content-Type':'application/octet-stream'};
 if(!unknown){headers['Content-Length']=last-first+1;headers['Accept-Ranges']='bytes';if(code===206)headers['Content-Range']=`bytes ${first}-${last}/${bytes.length}`;}
 res.writeHead(code,headers);if(req.method==='HEAD'){res.end();return;}
 if(path==='/second'){res.end(bytes.subarray(first,last+1));return;}
 let at=first;const timer=setInterval(()=>{const next=Math.min(at+32768,last+1);res.write(bytes.subarray(at,next));at=next;if(at>last){clearInterval(timer);res.end();}},35);
 res.on('close',()=>clearInterval(timer));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
try{
 const picker=net.createServer();await new Promise(r=>picker.listen(0,'127.0.0.1',r));seedPort=picker.address().port;await new Promise(r=>picker.close(r));
 const seedDir=join(work,'seed');mkdirSync(seedDir);writeFileSync(join(seedDir,'fixture-seed.bin'),bytes);
 const pieces=[];for(let i=0;i<bytes.length;i+=262144)pieces.push(createHash('sha1').update(bytes.subarray(i,i+262144)).digest());
 const info={length:bytes.length,name:'fixture-seed.bin','piece length':262144,pieces:Buffer.concat(pieces),private:1};
 const torrent=join(work,'本机 种子.torrent');writeFileSync(torrent,bencode({announce:base+'/announce',info}));
 const magnet=`magnet:?xt=urn:btih:${createHash('sha1').update(bencode(info)).digest('hex')}&tr=${encodeURIComponent(base+'/announce')}`;
 seed=spawn(join(import.meta.dirname,'..','bin','aria2c.exe'),['--no-conf=true','--enable-rpc=false','--enable-dht=false','--enable-dht6=false','--enable-peer-exchange=false','--seed-ratio=0.0','--seed-time=5','--check-integrity=true','--listen-port='+seedPort,'--dir='+seedDir,'--console-log-level=warn',torrent],{windowsHide:true});
 seed.stdout.resume();seed.stderr.resume();await new Promise((ok,fail)=>{seed.once('error',fail);setTimeout(ok,1200);});
 await new Promise((ok,fail)=>{
  const p=spawn('powershell.exe',['-NoLogo','-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',join(import.meta.dirname,'TestWpf.ps1'),'-WorkRoot',work,'-NetworkSource',base+'/first?fixture=1&mode=2','-SecondSource',base+'/second','-UnknownSource',base+'/unknown','-MissingSource',base+'/missing','-ExpectedHash',sha,'-TorrentSource',torrent,'-MagnetSource',magnet],{windowsHide:true});
  let output='';p.stdout.on('data',b=>output+=b);p.stderr.on('data',b=>output+=b);p.stdin.end();
  const timeout=setTimeout(()=>{spawn('taskkill.exe',['/PID',String(p.pid),'/T','/F'],{windowsHide:true});fail(Error('WPF timeout: '+output));},150000);
  p.on('error',fail);p.on('close',code=>{clearTimeout(timeout);try{assert.equal(code,0,output);ok();}catch(e){fail(e);}});
 });
 const report=JSON.parse(readFileSync(join(work,'test-evidence.json'),'utf8').replace(/^\uFEFF/,''));assert.equal(report.passed,true);assert.ok(ranges>0,'Resume did not send Range');
 console.log('PASS: actual WPF events, local HTTP, pause/resume/restart, queue, unknown-length, errors and SHA256; '+work);
}finally{if(seed){seed.kill();await new Promise(r=>{if(seed.exitCode!==null)r();else seed.once('exit',r);});}server.closeAllConnections();await new Promise(r=>server.close(r));}
