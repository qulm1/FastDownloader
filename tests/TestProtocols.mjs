// Actual FTP, Metalink 3/4 and certificate-validated HTTPS transfers.
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';

const home=resolve(import.meta.dirname,'..');
const work=mkdtempSync(join(process.env.TEST_WORK_ROOT||tmpdir(),'download-protocols-'));
const payload=Buffer.alloc(1024*1024+71);for(let i=0;i<payload.length;i++)payload[i]=i%247;
const sha=createHash('sha256').update(payload).digest('hex');
const evidence=[], sockets=new Set(),passives=new Set();let tlsServer;
const web=http.createServer((req,res)=>{res.writeHead(200,{'Content-Length':payload.length});res.end(payload)});
await new Promise(r=>web.listen(0,'127.0.0.1',r));
const httpBase=`http://127.0.0.1:${web.address().port}`;
const ftp=net.createServer(control=>{
  sockets.add(control); control.setTimeout(30000,()=>control.destroy());
  control.on('close',()=>sockets.delete(control));control.on('error',()=>{});
  let buffer='',chain=Promise.resolve(),connection=null,offset=0;
  const send=s=>control.write(s+'\r\n');send('220 Controlled local FTP fixture');
  async function command(line){
    const [verb,...rest]=line.split(' ');const arg=rest.join(' ');
    switch(verb.toUpperCase()){
      case 'USER':send('331 Password required');break;
      case 'PASS':send('230 Logged in');break;
      case 'TYPE':send('200 Binary');break;
      case 'SYST':send('215 UNIX Type: L8');break;
      case 'PWD':send('257 "/"');break;
      case 'CWD':send('250 Directory changed');break;
      case 'FEAT':send('211 End');break;
      case 'SIZE':send('213 '+payload.length);break;
      case 'MDTM':send('213 20261024000000');break;
      case 'REST':offset=Number(arg);send('350 Restart accepted');break;
      case 'EPSV':case 'PASV':{
        const passive=net.createServer();passives.add(passive);
        connection=new Promise(resolveConnection=>passive.once('connection',s=>{
          sockets.add(s);s.on('close',()=>sockets.delete(s));s.on('error',()=>{});resolveConnection(s);passive.close();passives.delete(passive);
        }));
        await new Promise(r=>passive.listen(0,'127.0.0.1',r));
        const port=passive.address().port;
        send(verb.toUpperCase()==='EPSV'?`229 Entering Extended Passive Mode (|||${port}|)`:`227 Entering Passive Mode (127,0,0,1,${port>>8},${port&255})`);break;
      }
      case 'RETR':{
        if(!connection){send('425 Use passive mode');break;}
        send('150 Opening data');const data=await connection;
        await new Promise(r=>data.end(payload.subarray(offset),r));offset=0;connection=null;send('226 Transfer complete');break;
      }
      case 'QUIT':send('221 Bye');control.end();break;
      default:send('502 Unsupported fixture command');
    }
  }
  control.on('data',data=>{
    buffer+=data.toString();let end;
    while((end=buffer.indexOf('\r\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+2);chain=chain.then(()=>command(line)).catch(()=>control.destroy());}
  });
});
await new Promise(r=>ftp.listen(0,'127.0.0.1',r));

async function processRun(exe,args,expected=0){
  return await new Promise((resolveRun,reject)=>{
    const p=spawn(exe,args,{windowsHide:true});let output='';p.stdout.on('data',x=>output+=x);p.stderr.on('data',x=>output+=x);
    const timer=setTimeout(()=>{spawn('taskkill.exe',['/PID',String(p.pid),'/T','/F'],{windowsHide:true});reject(Error(output+'\nTimed out; stopped this test process tree'))},60000);
    p.on('error',e=>{clearTimeout(timer);reject(e)});
    p.on('close',code=>{clearTimeout(timer);try{assert.equal(code,expected,output);resolveRun(output)}catch(e){reject(e)}});
  });
}
async function run(extra,expected=0){return await processRun('powershell.exe',['-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',join(home,'FastDownload.ps1'),'-StateDir',join(work,'state'),'-DownloadDir',join(work,'下载 协议'),...extra],expected)}
function task(source){const folder=join(work,'state/jobs');return readdirSync(folder).map(id=>JSON.parse(readFileSync(join(folder,id,'task.json'),'utf8').replace(/^\uFEFF/,''))).find(t=>t.Source===source)}
function passed(name){console.log('PASS:',name);evidence.push({name,passed:true})}
try{
  const source=`ftp://127.0.0.1:${ftp.address().port}/payload.bin`;
  await run(['-Source',source,'-FileName','ftp-test.bin','-Sha256',sha]);
  const ftpTask=task(source);assert.equal(ftpTask.Status,'Completed');assert.ok(readFileSync(join(ftpTask.OutputDir,'ftp-test.bin')).equals(payload));
  passed('Actual passive FTP authentication, size and binary transfer with SHA-256');
  const v4=`<?xml version="1.0" encoding="utf-8"?><metalink xmlns="urn:ietf:params:xml:ns:metalink"><file name="document.pdf"><size>${payload.length}</size><hash type="sha-256">${sha}</hash><url>${httpBase}/pdf</url></file><file name="installer.apk"><size>${payload.length}</size><hash type="sha-256">${sha}</hash><url>${httpBase}/apk</url></file></metalink>`;
  const v3=`<?xml version="1.0" encoding="utf-8"?><metalink version="3.0" xmlns="http://www.metalinker.org/"><files><file name="legacy.zip"><size>${payload.length}</size><verification><hash type="sha256">${sha}</hash></verification><resources><url type="http">${httpBase}/zip</url></resources></file></files></metalink>`;
  for(const [name,text,files] of [['真实 多文件.meta4',v4,['document.pdf','installer.apk']],['legacy.metalink',v3,['legacy.zip']]]){
    const path=join(work,name);writeFileSync(path,text);await run(['-Source',path]);
    const row=task(path);assert.equal(row.Status,'Completed');for(const file of files)assert.ok(readFileSync(join(row.OutputDir,file)).equals(payload));
    passed('Actual '+name.split('.').pop()+' transfer, selected filenames and embedded checksum');
  }
  assert.ok(process.env.TEST_CERT_ROOT,'Set TEST_CERT_ROOT after generating the temporary test-only certificate.');
  const certificate=join(process.env.TEST_CERT_ROOT,'certificate.pem');
  tlsServer=https.createServer({cert:readFileSync(certificate),key:readFileSync(join(process.env.TEST_CERT_ROOT,'key.pem'))},(req,res)=>{res.writeHead(200,{'Content-Length':payload.length});res.end(payload)});
  tlsServer.on('tlsClientError',()=>{});
  await new Promise(r=>tlsServer.listen(0,'127.0.0.1',r));
  const untrusted=`https://127.0.0.1:${tlsServer.address().port}/secure.bin`;
  await run(['-Source',untrusted,'-FileName','untrusted.bin'],1);
  assert.notEqual(task(untrusted).Status,'Completed');
  passed('HTTPS rejects an untrusted local certificate without changing Windows trust or disabling checks');
  const url=process.env.TEST_HTTPS_URL||'https://www.microsoft.com/robots.txt';
  const reference=join(work,'https-reference.txt');
  await processRun('curl.exe',['--fail','--silent','--show-error','--location','--max-time','30','--output',reference,url]);
  const expected=createHash('sha256').update(readFileSync(reference)).digest('hex');
  await run(['-Source',url,'-FileName','https-public.txt','-Sha256',expected,'-StopAfterSeconds','45']);
  const row=task(url);assert.equal(row.Status,'Completed');assert.ok(readFileSync(join(row.OutputDir,'https-public.txt')).equals(readFileSync(reference)));
  passed('Actual official HTTPS transfer with system certificate validation and independent SHA-256');
}finally{
  for(const s of sockets)s.destroy();for(const p of passives)p.close();
  if(tlsServer){tlsServer.closeAllConnections();await new Promise(r=>tlsServer.close(r));}
  web.closeAllConnections();await new Promise(r=>web.close(r));await new Promise(r=>ftp.close(r));
  writeFileSync(join(work,'test-evidence.json'),JSON.stringify({work,evidence},null,2));console.log('Evidence:',work);
}
