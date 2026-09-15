// Crystamber service worker: opens instantly on a repeat visit and keeps
// working with no signal - a card event in a mall basement, say.
//
// - The page: served from cache straight away and refreshed in the background,
//   so a new deploy shows up on the open after next.
// - Card images and the vendored library: cache-first. Their file names never
//   change [a new image goes in a new folder, a new library version gets a new
//   file name], so a cached copy is always the right one. Only what someone has
//   actually looked at is cached - nothing is downloaded ahead of time.
// - Supabase and every other origin: never touched. Auth and collection data
//   always go to the network, and the app's own sync queue handles being offline.
//
// To switch this off, deploy a sw.js that calls self.registration.unregister().

const SHELL  = 'crystamber-shell-v1';
const ASSETS = 'crystamber-assets-v1';
// The app cannot start without its library, and on a first visit the page
// fetches it before this worker is in control - so it would never reach the
// cache by itself. Fetch it here instead. Keep in step with index.html.
const LIBRARY = '/vendor/supabase-js-2.116.0.js';

self.addEventListener('install', (e) => {
  e.waitUntil(
    Promise.all([
      caches.open(SHELL).then(c => c.add('/')),
      caches.open(ASSETS).then(c => c.add(LIBRARY)),
    ]).catch(() => {}).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== SHELL && key !== ASSETS) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // Every page URL [/?u= binder links, /?join= invites] is the same app, so
  // they share one cached copy of the page.
  if (req.mode === 'navigate' && (url.pathname === '/' || url.pathname === '/index.html')) {
    const fresh = fetch(req).then(res => {
      const copy = res.clone();
      if (res.ok) caches.open(SHELL).then(c => c.put('/', copy));
      return res;
    }).catch(() => null);
    e.waitUntil(fresh);
    e.respondWith(
      caches.open(SHELL)
        .then(c => c.match('/'))
        .then(cached => cached || fresh.then(res => res || new Response('Offline and not cached yet.', { status: 503 })))
    );
    return;
  }

  if (url.pathname.startsWith('/img/') || url.pathname.startsWith('/vendor/')) {
    e.respondWith((async () => {
      const cache = await caches.open(ASSETS);
      const hit = await cache.match(req);
      if (hit) return hit;
      const res = await fetch(req);
      if (res.ok) cache.put(req, res.clone());
      return res;
    })());
  }
});
