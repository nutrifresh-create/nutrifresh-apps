const SW_VERSION = 'v152.1';
const CACHE_NAME = 'nutrifresh-v152.1';
const CORE_ASSETS = [
  '/',
  '/pos.html',
  '/office.html',
  '/staff.html',
  '/download.html',
  '/download-staff.html',
  '/supabase-adapter.js',
  '/nutri-theme.css',
  '/native-bridge.js',
  '/manifest-staff.json',
  '/icon-staff.png',
  '/icon-office.png',
  '/manifest.json',
  '/icon.png',
  '/logo.png',
  '/iconP.png'
];

// Hapus flag `redirected: true` (misal 308 Pretty URL Cloudflare Pages: /pos.html -> /pos)
// agar Chrome tidak menolak respons navigasi dengan error ERR_FAILED.
async function toCleanResponse(response) {
  if (!response) return response;
  if (!response.redirected) return response;
  try {
    const body = await response.clone().arrayBuffer();
    const headers = new Headers(response.headers);
    return new Response(body, {
      status: response.status,
      statusText: response.statusText,
      headers
    });
  } catch (err) {
    console.warn('[SW] Gagal bersihkan redirect response:', err?.message || err);
    return response;
  }
}

function getCanonicalCacheKey(pathname) {
  const p = String(pathname || '/').replace(/\/+$/, '') || '/';
  if (p === '/' || p === '/index' || p === '/index.html') return '/';
  if (p === '/pos' || p === '/pos.html') return '/pos.html';
  if (p === '/office' || p === '/office.html') return '/office.html';
  if (p === '/staff' || p === '/staff.html') return '/staff.html';
  if (p === '/download' || p === '/download.html') return '/download.html';
  if (p === '/download-staff' || p === '/download-staff.html') return '/download-staff.html';
  return pathname;
}

async function precacheAssetClean(cache, assetPath) {
  try {
    const res = await fetch(assetPath, { redirect: 'follow', credentials: 'same-origin', cache: 'no-cache' });
    if (res && res.status === 200) {
      const clean = await toCleanResponse(res);
      await cache.put(getCanonicalCacheKey(assetPath), clean);
    }
  } catch (err) {
    console.warn('[SW] Skip precache:', assetPath, err?.message || err);
  }
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => Promise.allSettled(CORE_ASSETS.map((asset) => precacheAssetClean(cache, asset))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('message', (event) => {
  if (!event.data) return;
  if (event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  } else if (event.data.type === 'GET_VERSION') {
    if (event.ports && event.ports[0]) {
      event.ports[0].postMessage({ version: SW_VERSION, cacheName: CACHE_NAME });
    }
  }
});

self.addEventListener('sync', (event) => {
  if (event.tag === 'nutrifresh-sync') {
    event.waitUntil(
      self.clients.matchAll({ includeUncontrolled: true, type: 'window' }).then((clients) => {
        clients.forEach((client) => client.postMessage({ type: 'TRIGGER_CLOUD_SYNC' }));
      })
    );
  }
});

self.addEventListener('periodicsync', (event) => {
  if (event.tag === 'nutrifresh-periodic-sync') {
    event.waitUntil(
      caches.open(CACHE_NAME).then((cache) =>
        Promise.allSettled(CORE_ASSETS.map((asset) => precacheAssetClean(cache, asset)))
      )
    );
  }
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('googleapis.com') ||
    url.hostname.includes('firebaseio.com') ||
    url.hostname.includes('gstatic.com') ||
    url.hostname.includes('esm.sh')
  ) {
    return;
  }

  if (url.origin !== self.location.origin) return;

  const isNav = event.request.mode === 'navigate';
  const isCodeFile = isNav || url.pathname.endsWith('.html') || url.pathname.endsWith('.js') || url.pathname.endsWith('.css');
  const cacheKey = isNav ? getCanonicalCacheKey(url.pathname) : event.request;

  // NETWORK-FIRST untuk halaman HTML & JS (dengan timeout 3.5 detik -> fallback cache offline)
  // Supaya HP tidak pernah terjebak di versi cache HTML lama saat ada update!
  if (isCodeFile) {
    event.respondWith(
      caches.open(CACHE_NAME).then(async (cache) => {
        const cachedRaw = await cache.match(cacheKey, { ignoreSearch: true });
        const cached = (cachedRaw && cachedRaw.redirected) ? await toCleanResponse(cachedRaw) : cachedRaw;

        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 3500);

        try {
          const networkResponse = await fetch(event.request.url, {
            redirect: 'follow',
            credentials: 'same-origin',
            cache: 'no-cache',
            signal: controller.signal
          });
          clearTimeout(timer);
          if (networkResponse) {
            const cleanRes = await toCleanResponse(networkResponse);
            if (cleanRes && cleanRes.status === 200) {
              await cache.put(cacheKey, cleanRes.clone());
            }
            return cleanRes;
          }
        } catch (err) {
          clearTimeout(timer);
          console.warn('[SW] Network-first fallback to cache:', url.pathname, err?.message || err);
        }

        if (cached) return cached;
        if (isNav) {
          const fallbackHome = await cache.match('/');
          if (fallbackHome) return await toCleanResponse(fallbackHome);
        }
        return fetch(event.request.url, { redirect: 'follow', credentials: 'same-origin' });
      })
    );
    return;
  }

  // CACHE-FIRST + background refresh untuk aset gambar/ikon/manifest
  let finishBg = () => {};
  const bgPromise = new Promise((resolve) => { finishBg = resolve; });
  event.waitUntil(bgPromise);

  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      let cached = await cache.match(cacheKey, { ignoreSearch: true });
      if (cached && cached.redirected) cached = await toCleanResponse(cached);

      const networkFetch = fetch(event.request.url, {
        redirect: 'follow',
        credentials: 'same-origin'
      })
        .then(async (networkResponse) => {
          if (!networkResponse) return networkResponse;
          const cleanRes = await toCleanResponse(networkResponse);
          if (cleanRes && cleanRes.status === 200) {
            await cache.put(cacheKey, cleanRes.clone());
          }
          return cleanRes;
        })
        .catch((err) => {
          console.warn('[SW] Static asset offline:', url.pathname, err?.message || err);
          if (cached) return cached;
          throw err;
        });

      if (cached) {
        networkFetch.catch(() => {}).finally(() => finishBg());
        return cached;
      }

      try {
        return await networkFetch;
      } finally {
        finishBg();
      }
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const c of clients) {
        if ('focus' in c) return c.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow('/');
    })
  );
});
