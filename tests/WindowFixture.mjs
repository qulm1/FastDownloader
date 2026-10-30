// Interactive Windows UI fixture; run with an external D: evidence directory.
import http from 'node:http';
import {mkdirSync,writeFileSync,appendFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
const work=resolve(process.argv[2]);mkdirSync(work,{recursive:true});
const bytes=Buffer.alloc(12*1024*1024+19);for(let i=0;i<bytes.length;i++)bytes[i]=(i*19)%251;
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://localhost');
 appendFileSync(join(work,'requests.jsonl'),JSON.stringify({path:url.pathname,range:req.headers.range||null,at:new Date().toISOString()})+'\n');
 if(url.pathname==='/missing'){res.writeHead(404);res.end('not found');return;}
 let begin=0,end=bytes.length-1,code=200;
 if(req.headers.range){const m=/bytes=(\d+)-(\d*)/.exec(req.headers.range);begin=+m[1];if(m[2])end=Math.min(+m[2],end);code=206;}
 const headers={'Content-Length':end-begin+1,'Accept-Ranges':'bytes','ETag':'"gui-fixture"'};
 if(code===206)headers['Content-Range']=`bytes ${begin}-${end}/${bytes.length}`;
 res.writeHead(code,headers);if(req.method==='HEAD'){res.end();return;}
 if(url.pathname==='/fast.bin'){res.end(bytes.subarray(begin,end+1));return;}
 let at=begin;
 const timer=setInterval(()=>{const next=Math.min(at+8192,end+1);res.write(bytes.subarray(at,next));at=next;if(at>end){clearInterval(timer);res.end();}},30);
 res.on('close',()=>clearInterval(timer));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const base=`http://127.0.0.1:${server.address().port}`;
const info={base,sha256:createHash('sha256').update(bytes).digest('hex'),size:bytes.length,work};
writeFileSync(join(work,'fixture.json'),JSON.stringify(info,null,2));
writeFileSync(join(work,'任务 清单.json'),JSON.stringify([{Source:base+'/fast.bin',FileName:'中文 安装包.exe',Sha256:info.sha256}]));
console.log(JSON.stringify(info));
process.on('SIGTERM',()=>{server.closeAllConnections();server.close(()=>process.exit());});
