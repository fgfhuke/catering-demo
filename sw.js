// Service Worker — Catering ZvE V2.0
const CACHE = "catering-demo-v3-5";
const HTML_FILES = ["./index.html", "./listenansicht.html"];
const CDN_FILES = [
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",
  "https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.8.2/jspdf.plugin.autotable.min.js",
  "https://cdn.jsdelivr.net/npm/jszip@3.10.1/dist/jszip.min.js"
];

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(CACHE).then(async c => {
      await c.addAll(HTML_FILES);
      // CDN-Bibliotheken vorab cachen (best-effort — schlägt fehl wenn offline)
      await Promise.all(CDN_FILES.map(url =>
        fetch(url).then(res => { if(res.ok) return c.put(url, res); }).catch(()=>{})
      ));
    })
  );
  self.skipWaiting();
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);

  // Supabase API → immer Network (App hat eigenes Offline-Handling)
  if (url.hostname.includes("supabase.co")) return;

  // Google Fonts → Network only (App funktioniert auch ohne Schriftarten)
  if (url.hostname.includes("googleapis.com") || url.hostname.includes("gstatic.com")) return;

  // CDN-Bibliotheken → Cache first, dann Network + nachladen
  if (url.hostname.includes("cdnjs.cloudflare.com") || url.hostname.includes("cdn.jsdelivr.net")) {
    e.respondWith(
      caches.match(e.request).then(cached => {
        if (cached) return cached;
        return fetch(e.request).then(res => {
          if (res.ok) caches.open(CACHE).then(c => c.put(e.request, res.clone()));
          return res;
        });
      })
    );
    return;
  }

  // HTML-Dateien → Stale-While-Revalidate
  if (e.request.destination === "document") {
    e.respondWith(
      caches.match(e.request).then(cached => {
        const network = fetch(e.request).then(res => {
          if (res.ok) caches.open(CACHE).then(c => c.put(e.request, res.clone()));
          return res;
        }).catch(() => cached);
        return cached || network;
      })
    );
  }
});
