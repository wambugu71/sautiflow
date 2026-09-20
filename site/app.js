const REPO = "wambugu71/sautiflow";
const RELEASES_URL = `https://github.com/${REPO}/releases/latest`;
const API_URL = `https://api.github.com/repos/${REPO}/releases/latest`;

// Version badge doubles as the docs entry point (see ver-badge in index.html).
const DOCS_URL = "https://docs.sautiflow.us.ci";

const PLATFORMS = [
  { test: (n) => /\.apk$/i.test(n) && /arm64|aarch64/i.test(n), os: "Android", sub: "arm64-v8a · modern devices", icon: "◆", key: "arm64" },
  { test: (n) => /\.apk$/i.test(n) && /armeabi-v7a|armv7/i.test(n), os: "Android", sub: "armeabi-v7a · older devices", icon: "◇", key: "armv7" },
  { test: (n) => /\.apk$/i.test(n), os: "Android", sub: "universal · all devices", icon: "◆", key: "android" },
  { test: (n) => /\.msix$/i.test(n), os: "Windows", sub: "x64 · MSIX package", icon: "▣", key: "windows-msix" },
  { test: (n) => /macos|mac-?osx|darwin/i.test(n), os: "macOS", sub: "universal · zipped app", icon: "▥", key: "macos" },
  { test: (n) => /windows|win/i.test(n) || /^release\.zip$/i.test(n), os: "Windows", sub: "x64 · portable, no installer", icon: "▣", key: "windows" },
  { test: (n) => /\.deb$/i.test(n), os: "Linux", sub: "amd64 · Debian / Ubuntu package", icon: "▤", key: "linux" },
  { test: (n) => /linux|\.tar\.gz$/i.test(n), os: "Linux", sub: "x86_64 · portable bundle", icon: "▤", key: "linux" },
  { test: (n) => /\.ipa$/i.test(n) || /(^|[_-])ios/i.test(n), os: "iOS", sub: "arm64 · sideload IPA", icon: "◈", key: "ios" },
];

function detectPlatform() {
  const ua = navigator.userAgent;
  if (/Android/i.test(ua)) return /arm64|aarch64/i.test(ua) ? "arm64" : "armv7";
  if (/Macintosh|Mac OS X/i.test(ua)) return "macos";
  if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
  if (/Win/i.test(navigator.platform || ua)) return "windows";
  if (/Linux|X11/i.test(ua)) return "linux";
  return null;
}

function formatSize(bytes) {
  const mb = bytes / (1024 * 1024);
  return mb >= 1 ? `${mb.toFixed(1)} MB` : `${(bytes / 1024).toFixed(0)} KB`;
}

function formatDate(iso) {
  return new Date(iso).toLocaleDateString(undefined, {
    year: "numeric", month: "short", day: "numeric",
  });
}

function matchPlatform(name) {
  for (const p of PLATFORMS) {
    if (typeof p.test === "function" ? p.test(name) : p.test.test(name)) return p;
  }
  return null;
}

function assetRow(asset, isRecommended) {
  const p = matchPlatform(asset.name);
  const a = document.createElement("a");
  a.className = "asset" + (isRecommended ? " rec" : "");
  a.href = asset.browser_download_url;
  a.innerHTML = `
    <span class="asset-icon">${p ? p.icon : "▪"}</span>
    <span class="asset-main">
      <span class="asset-os">${p ? p.os : "Other"}${isRecommended ? ' <span class="rec-badge">FOR YOU</span>' : ""}</span>
      <span class="asset-file">${asset.name}</span>
    </span>
    <span class="asset-meta">${formatSize(asset.size)} ↓</span>`;
  return a;
}

async function loadLatestRelease() {
  const list = document.getElementById("assets");
  const badge = document.getElementById("ver-badge");

  // the badge is the header's docs entry point — keep it pointed at the docs site
  badge.href = DOCS_URL;

  try {
    const res = await fetch(API_URL, { headers: { Accept: "application/vnd.github+json" } });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const rel = await res.json();

    badge.textContent = rel.tag_name;
    badge.title = `${rel.tag_name} — read the Sautiflow docs`;
    document.getElementById("rel-tag").textContent = `${rel.tag_name} — ${rel.name || "LATEST RELEASE"}`;
    document.getElementById("rel-date").textContent = `PUBLISHED ${formatDate(rel.published_at).toUpperCase()}`;

    list.innerHTML = "";
    const detected = detectPlatform();
    const assets = [...rel.assets].sort((a, b) => a.name.localeCompare(b.name));

    let recommendedShown = false;
    for (const asset of assets) {
      const p = matchPlatform(asset.name);
      const isRec = !recommendedShown && p && (
        (detected === "arm64" && p.key === "arm64") ||
        (detected === "armv7" && p.key === "armv7") ||
        (detected === "windows" && p.key === "windows") ||
        (detected === "linux" && p.key === "linux") ||
        (detected === "macos" && p.key === "macos") ||
        (detected === "ios" && p.key === "ios") ||
        detected === null
      );
      if (isRec) recommendedShown = true;
      list.appendChild(assetRow(asset, isRec));
    }

    if (!assets.length) {
      list.innerHTML = `<div class="empty-state mono">Release published but no assets attached yet.
        Check <a href="${RELEASES_URL}" target="_blank" rel="noopener">GitHub Releases ↗</a></div>`;
    }
  } catch (err) {
    badge.textContent = "v0.6.29";
    badge.title = "v0.6.29 — read the Sautiflow docs";
    list.innerHTML = `
      <div class="empty-state mono">NO PUBLIC RELEASE PUBLISHED YET.<br><br>
      The moment the first tag lands on GitHub, download links appear here automatically.<br><br>
      Meanwhile, watch the
      <a href="${RELEASES_URL}" target="_blank" rel="noopener">Releases page ↗</a> or grab source from
      <a href="https://github.com/${REPO}" target="_blank" rel="noopener">${REPO} ↗</a></div>`;
  }
}

loadLatestRelease();

// ---------- screenshot lightbox (native <dialog>, no dependencies) ----------
(function () {
  const dialog = document.getElementById("lightbox");
  if (!dialog || typeof dialog.showModal !== "function") return;
  const img = document.getElementById("lightbox-img");
  const cap = document.getElementById("lightbox-caption");
  const shots = Array.from(document.querySelectorAll(".shot-btn"));
  if (!shots.length) return;

  let current = 0;
  let lastTrigger = null;

  function show(i) {
    current = (i + shots.length) % shots.length;
    const btn = shots[current];
    img.src = btn.dataset.full;
    img.alt = btn.querySelector("img").alt;
    cap.textContent = btn.dataset.caption;
  }

  shots.forEach((btn, i) => {
    btn.addEventListener("click", () => {
      lastTrigger = btn;
      show(i);
      dialog.showModal();
    });
  });

  dialog.querySelector(".lb-close").addEventListener("click", () => dialog.close());
  dialog.querySelectorAll(".lb-nav").forEach((b) => {
    b.addEventListener("click", () => show(current + parseInt(b.dataset.dir, 10)));
  });

  // backdrop click closes
  dialog.addEventListener("click", (e) => {
    if (e.target === dialog) dialog.close();
  });

  // keyboard prev/next when open
  dialog.addEventListener("keydown", (e) => {
    if (e.key === "ArrowLeft") show(current - 1);
    if (e.key === "ArrowRight") show(current + 1);
  });

  dialog.addEventListener("close", () => {
    if (lastTrigger) lastTrigger.focus();
  });
})();
