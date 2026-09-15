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
    // Copies are taken the moment the response lands, before the page can start
    // reading it - a response whose body is in use can no longer be cloned.
    const network = fetch(req)
      .then(res => ({ res, copy: res.ok ? res.clone() : null, probe: res.ok ? res.clone() : null }))
      .catch(() => null);
    // Refresh the cached page, and if it changed, tell open tabs so the app can
    // offer a one-tap refresh instead of waiting for the next visit.
    e.waitUntil(network.then(async (n) => {
      if (!n || !n.copy) return;
      const cache = await caches.open(SHELL);
      const old = await cache.match('/');
      const changed = !!old && (await old.text()) !== (await n.probe.text());
      await cache.put('/', n.copy);
      if (!changed) return;
      // Other open tabs are ready now.
      for (const client of await self.clients.matchAll({ type: 'window' })) {
        if (client.id !== e.resultingClientId) client.postMessage({ type: 'update-available' });
      }
      // The tab being opened may not exist yet - on a fast connection the new page
      // arrives before the browser has created it. Keep asking for a few seconds.
      for (let i = 0; i < 20; i++) {
        const tab = e.resultingClientId && await self.clients.get(e.resultingClientId);
        if (tab) { tab.postMessage({ type: 'update-available' }); return; }
        await new Promise(r => setTimeout(r, 250));
      }
    }));
    e.respondWith(
      caches.open(SHELL)
        .then(c => c.match('/'))
        .then(cached => cached || network.then(n => n ? n.res : new Response('Offline and not cached yet.', { status: 503 })))
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
