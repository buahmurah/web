/* buahmurah.id — service worker
   Naikkan angka VERSI setiap kali index.html diubah, supaya HP mengambil versi baru. */
const VERSI = "buahmurah-v6";
const RANGKA = [
  "./",
  "./index.html",
  "./manifest.json",
  "./ikon/ikon-192.png",
  "./ikon/ikon-512.png",
  "./ikon/ikon-maskable-512.png",
  "./ikon/apple-touch-icon.png"
];

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(VERSI)
      .then(c => c.addAll(RANGKA).catch(() => null))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(k => Promise.all(k.filter(n => n !== VERSI).map(n => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);

  // Jangan pernah simpan data Supabase — harus selalu ambil yang terbaru.
  if (url.hostname.endsWith("supabase.co") || e.request.method !== "GET") return;

  // Halaman: coba jaringan dulu, pakai simpanan kalau offline.
  if (e.request.mode === "navigate") {
    e.respondWith(
      fetch(e.request)
        .then(r => {
          const salinan = r.clone();
          caches.open(VERSI).then(c => c.put("./index.html", salinan));
          return r;
        })
        .catch(() => caches.match("./index.html"))
    );
    return;
  }

  // Aset: pakai simpanan dulu supaya cepat dibuka.
  e.respondWith(
    caches.match(e.request).then(tersimpan =>
      tersimpan ||
      fetch(e.request).then(r => {
        if (r.ok && (url.origin === location.origin ||
                     url.hostname.includes("gstatic") ||
                     url.hostname.includes("jsdelivr"))) {
          const salinan = r.clone();
          caches.open(VERSI).then(c => c.put(e.request, salinan));
        }
        return r;
      }).catch(() => tersimpan)
    )
  );
});

/* ---------------------------------------------------------------------
   NOTIFIKASI
   Saat aplikasi terbuka, halaman yang memanggil registration.showNotification().
   Handler push di bawah disiapkan untuk Web Push (butuh kunci VAPID + server
   pengirim); tanpa itu handler ini tidak pernah terpanggil dan tidak mengganggu.
   --------------------------------------------------------------------- */
self.addEventListener("push", e => {
  let isi = { judul: "buahmurah.id", pesan: "Ada catatan baru.", hal: "penjualan_m" };
  try { isi = { ...isi, ...e.data.json() }; }
  catch (err) { if (e.data) isi.pesan = e.data.text(); }

  e.waitUntil(
    self.registration.showNotification(isi.judul, {
      body: isi.pesan,
      icon: "./ikon/ikon-192.png",
      badge: "./ikon/ikon-192.png",
      tag: isi.tag || "buahmurah",
      data: { hal: isi.hal },
      vibrate: [90, 50, 90]
    })
  );
});

self.addEventListener("notificationclick", e => {
  e.notification.close();
  const hal = e.notification.data && e.notification.data.hal;
  const tujuan = hal ? `./index.html?hal=${hal}` : "./index.html";

  e.waitUntil((async () => {
    const daftar = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const klien of daftar) {
      if (klien.url.includes("index.html") || klien.url.endsWith("/")) {
        await klien.focus();
        if (hal) klien.postMessage({ tipe: "buka-halaman", hal });
        return;
      }
    }
    await self.clients.openWindow(tujuan);
  })());
});
