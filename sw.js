const CACHE='bizcontrol-v1-8-6-multi-item-cashier';
const ASSETS=['./','./index.html','./styles.css','./app.js','./runtime-config.js','./manifest.webmanifest','./icon.svg'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(Promise.all([
  caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('bizcontrol-')&&k!==CACHE).map(k=>caches.delete(k)))),
  self.clients.claim()
])));
self.addEventListener('fetch',e=>{
  const req=e.request;
  if(req.method!=='GET') return;
  const url=new URL(req.url);
  // Never cache Supabase/Auth/API/third-party responses. Only cache same-origin app shell/static files.
  if(url.origin!==self.location.origin) return;
  const staticNames=new Set(['index.html','styles.css','app.js','runtime-config.js','manifest.webmanifest','icon.svg']);
  const name=url.pathname.split('/').pop();
  const isStatic=req.mode==='navigate' || staticNames.has(name);
  if(!isStatic) return;
  e.respondWith(fetch(req).then(r=>{
    if(r.ok){const copy=r.clone();caches.open(CACHE).then(c=>c.put(req,copy));}
    return r;
  }).catch(()=>caches.match(req).then(x=>x||caches.match('./index.html'))));
});
