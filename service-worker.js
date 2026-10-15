const CACHE='bad-workshop-v6-server-1';
const ASSETS=['./','./index.html','./app.js','./config.js','./manifest.webmanifest','./icon-192.png','./icon-512.png'];
const SUPABASE_LIB='https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
self.addEventListener('install',e=>e.waitUntil((async()=>{const c=await caches.open(CACHE);await c.addAll(ASSETS);try{const r=await fetch(SUPABASE_LIB,{mode:'no-cors',cache:'reload'});await c.put(SUPABASE_LIB,r)}catch(err){/* First install still succeeds; the library is cached when available. */}await self.skipWaiting()})()));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
 if(e.request.method!=='GET')return;
 const url=new URL(e.request.url);
 if(url.href===SUPABASE_LIB||url.hostname==='cdn.jsdelivr.net'&&url.pathname.includes('supabase-js')){
   e.respondWith(caches.match(e.request).then(cached=>cached||fetch(e.request).then(r=>{const copy=r.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));return r}).catch(()=>caches.match(SUPABASE_LIB))));return;
 }
 if(url.origin!==location.origin)return;
 e.respondWith(fetch(e.request).then(r=>{const copy=r.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));return r}).catch(()=>caches.match(e.request).then(r=>r||caches.match('./index.html'))));
});
