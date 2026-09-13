const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {webcrypto: crypto} = require('node:crypto');
const source=fs.readFileSync(require('node:path').join(__dirname,'../../web/rtc_transport.js'),'utf8');
const b64=b=>Buffer.from(b).toString('base64url');
async function setup(mode='tamper', page='https://web.example/web/'){
 const key=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
 const pub=await crypto.subtle.exportKey('raw',key.publicKey);
 const id=Buffer.from(await crypto.subtle.digest('SHA-256',pub)).toString('hex');
 const code={v:1,key:b64(pub),id,signal:'wss://reschool.app/signal',server:'https://server.example:4443'};
 const stored=new Map(); let accepted=0;
 class Peer{
  constructor(){this.iceGatheringState='complete';this.connectionState='connected';}
  createDataChannel(){return {readyState:'open',close(){}};}
  async createOffer(){return {type:'offer',sdp:'original-offer'};}
  async setLocalDescription(offer){this.localDescription=offer;}
  async setRemoteDescription(){accepted++;}
  close(){this.connectionState='closed';}
 }
 class Socket{
  constructor(){setTimeout(()=>this.onmessage?.({data:JSON.stringify({type:'challenge',iceServers:[]})}),0);}
  async send(text){
   const offer=JSON.parse(text);
   let payload=JSON.stringify({v:1,serverId:id,challenge:mode==='replay'?'replayed':offer.challenge,
    offerHash:mode==='offer'?'wrong':Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(offer.sdp))).toString('hex'),sdp:'answer'});
   const sig=await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key.privateKey,new TextEncoder().encode(payload));
   if(mode==='tamper')payload=payload.replace('answer','intercepted');
   this.onmessage({data:JSON.stringify({type:'answer',payload,signature:b64(sig)})});
  }
  close(){this.onclose?.();}
 }
 const context={crypto,TextEncoder,TextDecoder,URL,Uint8Array,ArrayBuffer,atob,btoa,setTimeout,clearTimeout,RTCPeerConnection:Peer,WebSocket:Socket,
 localStorage:{getItem:k=>stored.get(k),setItem:(k,v)=>stored.set(k,v)},location:new URL(page),isSecureContext:true,addEventListener(){}};
 context.window=context;
 vm.runInNewContext(source,context);
 return {api:context.reSchoolTransport,code,encode:c=>'rsc1.'+b64(JSON.stringify(c)),accepted:()=>accepted};
}
test('public code validates and stores stable identity',async()=>{
 const s=await setup(); assert.equal(await s.api.saveCode(s.encode(s.code)),s.code.server);
 assert.equal(s.api.hasServer(s.code.server+'/config'),true);
 assert.equal(s.api.hasServer('https://other.example'),false);
});
test('same-origin HTTPS uses browser transport despite an old pairing',async()=>{
 const s=await setup('tamper','https://server.example:4443/web/');
 await s.api.saveCode(s.encode(s.code));
 assert.equal(s.api.hasServer(s.code.server+'/config'),false);
});
test('loopback signaling is only accepted on local development pages',async()=>{
 const remote=await setup();
 await assert.rejects(remote.api.saveCode(remote.encode({...remote.code,signal:'ws://localhost:8787/signal'})),/Некорректный код/);
 const local=await setup('tamper','http://localhost:8085/');
 await local.api.saveCode(local.encode({...local.code,signal:'ws://localhost:8787/signal'}));
 assert.equal(local.api.hasServer(local.code.server),true);
});
test('changed identity cannot silently replace pairing',async()=>{
 const a=await setup(),b=await setup();await a.api.saveCode(a.encode(a.code));
 await assert.rejects(a.api.saveCode(b.encode(b.code)),/Ключ этого сервера изменился/);
});
test('nonlocal insecure signaling and forged key hash are rejected',async()=>{
 const s=await setup();
 await assert.rejects(s.api.saveCode(s.encode({...s.code,signal:'ws://remote.example/signal'})),/Некорректный код/);
 await assert.rejects(s.api.saveCode(s.encode({...s.code,id:'0'.repeat(64)})),/Ключ сервера/);
});
for(const mode of ['tamper','replay','offer'])test(`signed signaling rejects ${mode} before accepting DTLS fingerprint`,async()=>{
 const s=await setup(mode);await s.api.saveCode(s.encode(s.code));
 await assert.rejects(s.api.request(JSON.stringify({url:s.code.server+'/config',method:'GET',headers:{},body:''})),/Ключ сервера|неподходящее подтверждение/);
 assert.equal(s.accepted(),0);
});
