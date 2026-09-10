const BUILD = '__BUILD_HASH__';
const PRECACHE = __PRECACHE__;
const CACHE = 'graphghan-' + BUILD;
const scopeUrl = u => new URL(u, self.registration.scope).href;

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(PRECACHE.map(scopeUrl))));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('graphghan-') && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('message', e => { if (e.data === 'SKIP_WAITING') self.skipWaiting(); });

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return;
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const direct = await cache.match(e.request, { ignoreSearch: true });
    if (direct) return direct;
    if (e.request.mode === 'navigate') {
      const scopePath = new URL(self.registration.scope).pathname;
      let path = url.pathname;
      if (path.endsWith('/')) path += 'index.html';
      else if (!/\.[^/]+$/.test(path)) path += '/index.html';
      const asIndex = await cache.match(scopeUrl(path.replace(scopePath, '')));
      if (asIndex) return asIndex;
    }
    try {
      const res = await fetch(e.request);
      if (res.ok) e.waitUntil(cache.put(e.request, res.clone()).catch(() => {}));
      return res;
    } catch (err) {
      if (e.request.mode === 'navigate') return cache.match(scopeUrl('index.html'));
      throw err;
    }
  })());
});
