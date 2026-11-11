// Service worker do Meu Planner: deixa o app abrir sem internet.
// Estratégia: tenta a rede primeiro (sempre pega a versão nova) e usa o cache quando estiver offline.
var V = "planner-v1";
var CORE = ["./", "index.html", "config.js", "manifest.webmanifest", "icon-192.png", "icon-512.png", "apple-touch-icon.png"];
self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(V).then(function (c) { return c.addAll(CORE).catch(function () {}); }));
  self.skipWaiting();
});
self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (ks) {
    return Promise.all(ks.filter(function (k) { return k !== V; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});
self.addEventListener("fetch", function (e) {
  var r = e.request;
  if (r.method !== "GET") return;
  var u = new URL(r.url);
  var ok = u.origin === location.origin || /(^|\.)(googleapis|gstatic)\.com$|^cdn\.jsdelivr\.net$/.test(u.hostname);
  if (!ok) return; // Supabase e o resto passam direto
  e.respondWith(
    fetch(r).then(function (res) {
      if (res && (res.status === 200 || res.type === "opaque")) { var cp = res.clone(); caches.open(V).then(function (c) { c.put(r, cp); }); }
      return res;
    }).catch(function () {
      return caches.match(r).then(function (m) { return m || caches.match("index.html"); });
    })
  );
});
