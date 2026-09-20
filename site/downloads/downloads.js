/* =============================================================================
   Sautiplay — Real-Time Downloads & Release Ledger

   Direct GitHub Releases API Integration:
     Fetches live release metadata, files, download counters, and publish
     timestamps directly from api.github.com/repos/wambugu71/sautiflow/releases.
     No static record-keeping or manifest generation required. Whenever a new
     version is published on GitHub, it appears here automatically in real time.
   ========================================================================== */

(function (global) {
  "use strict";

  // ---------------------------------------------------------------- config --
  var CONFIG = {
    repo: "wambugu71/sautiflow",
    releasesApi: "https://api.github.com/repos/wambugu71/sautiflow/releases?per_page=100",
    docsUrl: "https://docs.sautiflow.us.ci",
    cacheKey: "sautiplay.downloads.releases.live.v1",
    cacheTtlMs: 5 * 60 * 1000 // 5 minutes cache
  };

  var REPO_URL = "https://github.com/" + CONFIG.repo;
  var RELEASES_URL = REPO_URL + "/releases";
  var LATEST_URL = RELEASES_URL + "/latest";
  var ARCHIVE_URL = REPO_URL + "/archive/refs/tags/";

  // ------------------------------------------------------------- platforms --
  var PLATFORMS = [
    { key: "android-arm64",     icon: "◆", label: "Android", abi: "arm64-v8a",  pkg: "APK",     note: "64-bit phones and tablets" },
    { key: "android-armv7",     icon: "◇", label: "Android", abi: "armeabi-v7a", pkg: "APK",    note: "older 32-bit devices" },
    { key: "android-universal", icon: "◆", label: "Android", abi: "universal",  pkg: "APK",     note: "single APK, all ABIs" },
    { key: "windows-zip",       icon: "▣", label: "Windows", abi: "x64",        pkg: "ZIP",     note: "portable folder, no installer" },
    { key: "windows-msix",      icon: "▣", label: "Windows", abi: "x64",        pkg: "MSIX",    note: "app package, test certificate" },
    { key: "linux-deb",         icon: "▤", label: "Linux",   abi: "amd64",      pkg: "DEB",     note: "Debian / Ubuntu package" },
    { key: "linux-tar",         icon: "▤", label: "Linux",   abi: "x86_64",     pkg: "TAR.GZ",  note: "portable bundle" },
    { key: "macos",             icon: "▥", label: "macOS",   abi: "universal",  pkg: "ZIP",     note: "zipped .app bundle" },
    { key: "ios",               icon: "◈", label: "iOS",     abi: "arm64",      pkg: "IPA",     note: "unsigned, sideload only" },
    { key: "other",             icon: "▪", label: "Other",   abi: "",           pkg: "FILE",    note: "unclassified asset" }
  ];

  var PLATFORM_BY_KEY = {};
  PLATFORMS.forEach(function (p) { PLATFORM_BY_KEY[p.key] = p; });

  // Pattern matching for binary asset filenames produced by CI
  var ASSET_RULES = [
    { key: "android-arm64",     match: function (n) { return /\.apk$/.test(n) && /arm64|aarch64/.test(n); } },
    { key: "android-armv7",     match: function (n) { return /\.apk$/.test(n) && /armeabi-v7a|armv7/.test(n); } },
    { key: "android-universal", match: function (n) { return /\.apk$/.test(n); } },
    { key: "windows-msix",      match: function (n) { return /\.msix$/.test(n); } },
    { key: "linux-deb",         match: function (n) { return /\.deb$/.test(n); } },
    { key: "ios",               match: function (n) { return /\.ipa$/.test(n) || /(^|[_-])ios/.test(n); } },
    { key: "macos",             match: function (n) { return /macos|mac-?osx|darwin/.test(n); } },
    { key: "windows-zip",       match: function (n) { return /windows/.test(n) || /^release\.zip$/.test(n); } },
    { key: "linux-tar",         match: function (n) { return /linux/.test(n) || /\.tar\.gz$/.test(n); } }
  ];

  // ------------------------------------------------------------- utilities --
  var ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

  function esc(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/[&<>"']/g, function (c) { return ESCAPES[c]; });
  }

  function inlineMd(value) {
    return esc(value)
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/`([^`]+)`/g, "<code>$1</code>");
  }

  function formatSize(bytes) {
    var size = Number(bytes) || 0;
    if (!size) return "";
    var mb = size / (1024 * 1024);
    if (mb >= 1) return mb.toFixed(mb >= 100 ? 0 : 1) + " MB";
    return Math.max(1, Math.round(size / 1024)) + " KB";
  }

  function formatCount(n) {
    return (Number(n) || 0).toLocaleString("en-US");
  }

  var MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

  function formatDate(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "UNKNOWN DATE";
    return String(d.getDate()).padStart(2, "0") + " " + MONTHS[d.getMonth()] + " " + d.getFullYear();
  }

  function formatIso(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "—";
    var m = String(d.getMonth() + 1).padStart(2, "0");
    return d.getFullYear() + "-" + m + "-" + String(d.getDate()).padStart(2, "0");
  }

  function dateValue(row) {
    var t = new Date(row && row.date).getTime();
    return isNaN(t) ? 0 : t;
  }

  function classifyAsset(name) {
    var n = String(name || "").toLowerCase();
    for (var i = 0; i < ASSET_RULES.length; i++) {
      if (ASSET_RULES[i].match(n)) return ASSET_RULES[i].key;
    }
    return "other";
  }

  function totalDownloads(assets) {
    return (assets || []).reduce(function (sum, a) { return sum + (Number(a.downloads) || 0); }, 0);
  }

  function assetUrl(tag, asset) {
    return asset.url || (RELEASES_URL + "/download/" + encodeURIComponent(tag) + "/" + encodeURIComponent(asset.name));
  }

  function commitUrl(sha) {
    return sha ? REPO_URL + "/commit/" + sha : REPO_URL + "/commits";
  }

  function archiveUrl(tag, kind) {
    return ARCHIVE_URL + encodeURIComponent(tag) + (kind === "zip" ? ".zip" : ".tar.gz");
  }

  // ------------------------------------------------------------ grouping ----
  function groupAssets(assets) {
    var buckets = {};
    (assets || []).forEach(function (a) {
      var key = classifyAsset(a.name);
      if (!buckets[key]) buckets[key] = [];
      buckets[key].push({
        key: key,
        name: a.name,
        size: Number(a.size) || 0,
        downloads: Number(a.downloads) || 0,
        url: a.url || ""
      });
    });
    return PLATFORMS
      .filter(function (p) { return buckets[p.key] && buckets[p.key].length; })
      .map(function (p) { return { def: p, items: buckets[p.key] }; });
  }

  // ------------------------------------------------------- device matching --
  function detectDevice(userAgent, platform) {
    var ua = String(userAgent || "");
    if (/Android/i.test(ua)) return /arm64|aarch64/i.test(ua) ? "android-arm64" : "android-armv7";
    if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
    if (/Macintosh|Mac OS X/i.test(ua)) return "macos";
    if (/Windows|Win32|Win64/i.test(ua) || /^Win/i.test(String(platform || ""))) return "windows-zip";
    if (/Linux|X11/i.test(ua)) return "linux-tar";
    return null;
  }

  var FALLBACK_ORDER = [
    "android-arm64", "windows-zip", "windows-msix", "linux-deb", "linux-tar",
    "macos", "android-armv7", "android-universal", "ios"
  ];

  function pickRecommended(assets, deviceKey) {
    var list = assets || [];
    if (!list.length) return null;
    if (deviceKey) {
      var exact = list.find(function (a) { return classifyAsset(a.name) === deviceKey; });
      if (exact) return exact;
    }
    for (var i = 0; i < FALLBACK_ORDER.length; i++) {
      var hit = list.find(function (a) { return classifyAsset(a.name) === FALLBACK_ORDER[i]; });
      if (hit) return hit;
    }
    return list[0];
  }

  // --------------------------------------------------------- API parser ----
  function normaliseAssets(list) {
    return (list || []).map(function (a) {
      return {
        name: a.name,
        size: Number(a.size) || 0,
        downloads: Number(a.download_count !== undefined ? a.download_count : a.downloads) || 0,
        url: a.browser_download_url || a.url || ""
      };
    });
  }

  function parseReleases(apiReleases) {
    var rows = (apiReleases || []).map(function (rel) {
      var assets = normaliseAssets(rel.assets);
      var notes = [];
      if (rel.body && rel.body.trim()) {
        notes = rel.body.split(/\r?\n/).map(function (l) { return l.trim(); }).filter(Boolean);
      }
      var tag = rel.tag_name || "";
      var title = (rel.name && rel.name.trim() && rel.name !== tag)
        ? rel.name.trim()
        : ("Release " + tag);

      return {
        tag: tag,
        name: rel.name || tag,
        title: title,
        date: rel.published_at || rel.created_at || null,
        targetCommitish: rel.target_commitish || "",
        notes: notes,
        assets: assets,
        published: true,
        live: true,
        prerelease: Boolean(rel.prerelease),
        releaseUrl: rel.html_url || (RELEASES_URL + "/tag/" + encodeURIComponent(tag))
      };
    });

    return rows.sort(function (a, b) { return dateValue(b) - dateValue(a); });
  }

  function hasPlatform(row, key) {
    if (!key || key === "all") return true;
    return row.assets.some(function (a) { return classifyAsset(a.name) === key; });
  }

  function filterRows(rows, state) {
    var q = String((state && state.query) || "").trim().toLowerCase();
    return (rows || []).filter(function (row) {
      if (!hasPlatform(row, state && state.platform)) return false;
      if (!q) return true;
      var haystack = [row.tag, row.title, (row.notes || []).join(" ")]
        .join(" ")
        .toLowerCase();
      return haystack.indexOf(q) !== -1;
    });
  }

  function platformSummary(rows) {
    var map = {};
    (rows || []).forEach(function (row) {
      groupAssets(row.assets).forEach(function (group) {
        var entry = map[group.def.key] || {
          def: group.def,
          rows: [],
          files: 0,
          downloads: 0
        };
        entry.rows.push(row);
        entry.files += group.items.length;
        group.items.forEach(function (item) { entry.downloads += item.downloads; });
        map[group.def.key] = entry;
      });
    });
    return PLATFORMS
      .filter(function (p) { return Boolean(map[p.key]); })
      .map(function (p) { return map[p.key]; });
  }

  function countWithBuilds(rows) {
    return (rows || []).filter(function (r) { return r.assets && r.assets.length > 0; }).length;
  }

  // --------------------------------------------------------------- markup ----
  function assetRow(row, asset, isRecommended, deviceKnown) {
    var def = PLATFORM_BY_KEY[classifyAsset(asset.name)] || PLATFORM_BY_KEY.other;
    var badge = isRecommended
      ? ' <span class="rec-badge">' + (deviceKnown ? "FOR YOU" : "START HERE") + "</span>"
      : "";
    var size = formatSize(asset.size);
    var meta = [
      size ? size + " ↓" : "",
      asset.downloads ? formatCount(asset.downloads) + " DOWNLOADS" : ""
    ].filter(Boolean).join(" · ");

    var a = document.createElement("a");
    a.className = "asset" + (isRecommended ? " rec" : "");
    a.href = assetUrl(row.tag, asset);
    a.rel = "noopener";
    a.innerHTML =
      '<span class="asset-icon">' + esc(def.icon) + "</span>" +
      '<span class="asset-main">' +
        '<span class="asset-os">' + esc(def.label) + (def.abi ? " · " + esc(def.abi) : "") + badge + "</span>" +
        '<span class="asset-file">' + esc(asset.name) + "</span>" +
      "</span>" +
      '<span class="asset-meta">' + esc(meta) + "</span>";
    return a;
  }

  function commitLine(row) {
    var parts = [];
    if (row.targetCommitish) {
      var isSha = /^[0-9a-f]{7,40}$/i.test(row.targetCommitish);
      var label = isSha ? row.targetCommitish.slice(0, 7) : row.targetCommitish;
      var targetUrl = isSha ? commitUrl(row.targetCommitish) : REPO_URL + "/tree/" + encodeURIComponent(row.targetCommitish);
      parts.push('TARGET <a href="' + esc(targetUrl) + '" target="_blank" rel="noopener">' + esc(label) + " ↗</a>");
    }
    if (row.date) parts.push(esc(formatDate(row.date)));
    parts.push("LIVE GITHUB API");
    return parts.join(" · ");
  }

  function sourceLinks(row) {
    var links = [
      '<a href="' + esc(archiveUrl(row.tag, "zip")) + '" target="_blank" rel="noopener">SOURCE ZIP ↗</a>',
      '<a href="' + esc(archiveUrl(row.tag, "tar.gz")) + '" target="_blank" rel="noopener">SOURCE TAR.GZ ↗</a>',
      '<a href="' + esc(row.releaseUrl) + '" target="_blank" rel="noopener">GITHUB RELEASE ↗</a>'
    ];
    return links.join(" ");
  }

  function platAsset(row, def, item) {
    var size = formatSize(item.size);
    var meta = [
      size ? size + " ↓" : "",
      item.downloads ? formatCount(item.downloads) + " DOWNLOADS" : ""
    ].filter(Boolean).join(" · ");
    return '<a class="asset" href="' + esc(assetUrl(row.tag, item)) + '" target="_blank" rel="noopener">' +
      '<span class="asset-icon">' + esc(def.icon) + "</span>" +
      '<span class="asset-main">' +
        '<span class="asset-os">' + esc(def.pkg) + (def.note ? " · " + esc(def.note) : "") + "</span>" +
        '<span class="asset-file">' + esc(item.name) + "</span>" +
      "</span>" +
      '<span class="asset-meta">' + esc(meta) + "</span>" +
    "</a>";
  }

  function platBlock(row, group) {
    var count = group.items.length;
    return '<div class="plat">' +
      '<div class="plat-head mono">' +
        '<span class="plat-name">' + esc(group.def.label.toUpperCase()) +
          (group.def.abi ? " · " + esc(group.def.abi.toUpperCase()) : "") + "</span>" +
        '<span class="plat-meta">' + esc(group.def.pkg) + " · " + count + " FILE" + (count === 1 ? "" : "S") + "</span>" +
      "</div>" +
      group.items.map(function (item) { return platAsset(row, group.def, item); }).join("") +
    "</div>";
  }

  function notesHtml(notes, row) {
    if (!notes || !notes.length) {
      return '<p class="ver-notes-none mono">Official release published by CI pipeline. ' +
        (row && row.releaseUrl ? '<a href="' + esc(row.releaseUrl) + '" target="_blank" rel="noopener">VIEW ON GITHUB ↗</a>' : "") +
        '</p>';
    }
    return "<h4>Release notes</h4><ul>" +
      notes.map(function (n) { return "<li>" + inlineMd(n) + "</li>"; }).join("") +
    "</ul>";
  }

  function ledgerCard(row, notesIndex, opts) {
    var flags = [];
    if (row.tag === opts.latestTag) flags.push('<span class="flag flag-latest">LATEST</span>');
    if (row.prerelease) flags.push('<span class="flag flag-pre">PRE-RELEASE</span>');
    if (!row.assets.length) {
      flags.push('<span class="flag flag-less">NO ASSETS</span>');
    } else {
      flags.push('<span class="flag">' + row.assets.length + " FILE" + (row.assets.length === 1 ? "" : "S") + "</span>");
    }
    var downloads = totalDownloads(row.assets);
    if (downloads) flags.push('<span class="flag flag-dl">↓ ' + esc(formatCount(downloads)) + "</span>");

    var groups = groupAssets(row.assets);
    var body = groups.length
      ? '<div class="plats">' + groups.map(function (g) { return platBlock(row, g); }).join("") + "</div>"
      : '<p class="ver-empty mono">NO PACKAGES ATTACHED TO THIS VERSION — SOURCE ARCHIVES ONLY.</p>';

    return '<details class="ver" id="ver-' + esc(row.tag) + '" data-tag="' + esc(row.tag) + '"' +
        (opts.open ? " open" : "") + ">" +
      "<summary>" +
        '<span class="ver-tag mono">' + esc(row.tag) + "</span>" +
        '<span class="ver-date mono">' + esc(formatIso(row.date)) + "</span>" +
        '<span class="ver-subjwrap">' +
          '<span class="ver-subj">' + esc(row.title) + "</span>" +
        "</span>" +
        '<span class="ver-flags mono">' + flags.join("") + "</span>" +
        '<span class="ver-caret mono" aria-hidden="true"></span>' +
      "</summary>" +
      '<div class="ver-body">' +
        '<p class="ver-commit mono">' + commitLine(row) + "</p>" +
        body +
        '<div class="ver-notes" data-notes="' + notesIndex + '"></div>' +
        '<p class="ver-src mono">' + sourceLinks(row) + "</p>" +
      "</div>" +
    "</details>";
  }

  function matrixRow(entry) {
    var newest = entry.rows[0];
    var oldest = entry.rows[entry.rows.length - 1];
    function link(row) {
      return '<a href="#ver-' + esc(row.tag) + '" data-ver="' + esc(row.tag) + '">' + esc(row.tag) + "</a>";
    }
    var range = newest === oldest ? link(oldest) : link(oldest) + " → " + link(newest);

    return "<tr>" +
      '<td class="m-plat"><span class="m-icon">' + esc(entry.def.icon) + "</span>" + esc(entry.def.label.toUpperCase()) + "</td>" +
      '<td class="m-target">' + esc(entry.def.abi || "—") + "</td>" +
      '<td class="m-pkg">' + esc(entry.def.pkg) + "</td>" +
      '<td class="m-note">' + esc(entry.def.note) + "</td>" +
      '<td class="m-count">' + entry.rows.length + " · " + entry.files + " FILE" + (entry.files === 1 ? "" : "S") + "</td>" +
      '<td class="m-range">' + range + "</td>" +
    "</tr>";
  }

  // ---------------------------------------------------------------- state ---
  var state = {
    rows: [],
    orderedRows: [],
    latestTag: null,
    device: null,
    order: "asc",
    platform: "all",
    query: "",
    notes: [],
    autoOpened: false
  };

  function $(id) { return document.getElementById(id); }
  function setText(el, text) { if (el) el.textContent = text; }

  // ------------------------------------------------------------ rendering ---
  function renderLatest(row) {
    var list = $("assets");
    if (!row) return;
    var recommended = pickRecommended(row.assets, state.device);

    setText($("rel-tag"), row.tag +
      (row.prerelease ? " · PRE-RELEASE" : "") +
      " · " + row.assets.length + " FILE" + (row.assets.length === 1 ? "" : "S"));
    setText($("rel-date"), row.date ? "PUBLISHED " + formatDate(row.date) : "");
    setText($("rel-subject"), row.title);
    $("rel-commit").innerHTML = commitLine(row);

    list.innerHTML = "";
    if (!row.assets.length) {
      list.innerHTML = '<div class="empty-state mono">THIS VERSION HAS NO PACKAGES ATTACHED. ' +
        '<a href="' + esc(row.releaseUrl) + '" target="_blank" rel="noopener">OPEN THE RELEASE PAGE ↗</a></div>';
    } else {
      row.assets.forEach(function (asset) {
        list.appendChild(assetRow(row, asset, asset === recommended, Boolean(state.device)));
      });
    }

    $("rel-source").innerHTML = sourceLinks(row) +
      ' <a href="' + esc(CONFIG.docsUrl) + '" target="_blank" rel="noopener">DOCS ↗</a>';
  }

  function renderMatrix() {
    var body = $("matrix-body");
    if (!body) return;
    var entries = platformSummary(state.rows);
    body.innerHTML = entries.length
      ? entries.map(matrixRow).join("")
      : '<tr><td colspan="6" class="empty-state mono">NO PACKAGES FOUND IN PUBLISHED RELEASES.</td></tr>';
  }

  function renderStatus(shown) {
    var parts = [shown + " OF " + state.rows.length + " RELEASES"];
    parts.push(countWithBuilds(state.rows) + " WITH PACKAGES");
    var def = PLATFORM_BY_KEY[state.platform];
    if (def) parts.push("FILTER " + def.label.toUpperCase() + (def.abi ? " " + def.abi.toUpperCase() : ""));
    setText($("ledger-status"), parts.join(" · "));
  }

  function renderLedger() {
    var list = $("ledger-list");
    if (!list) return;
    var rows = filterRows(state.rows, state);
    var ordered = state.order === "asc" ? rows.slice().reverse() : rows;
    state.orderedRows = ordered;

    state.notes = [];
    var html = ordered.map(function (row, i) {
      var notesIndex = state.notes.push(row.notes) - 1;
      var open = state.autoOpened === false && row.tag === state.latestTag;
      return ledgerCard(row, notesIndex, { latestTag: state.latestTag, open: open });
    }).join("");

    list.innerHTML = html || '<div class="empty-state mono">NO VERSIONS MATCH THAT FILTER. ' +
      '<button class="chipbtn mono" type="button" data-reset="1">CLEAR FILTERS</button></div>';

    if (html) state.autoOpened = true;
    renderStatus(rows.length);
  }

  function renderFilterChips() {
    var host = $("platform-filter");
    if (!host) return;
    var chips = ['<button class="chipbtn mono" type="button" data-platform="all">ALL BUILDS</button>'];
    platformSummary(state.rows).forEach(function (entry) {
      chips.push('<button class="chipbtn mono" type="button" data-platform="' + esc(entry.def.key) + '">' +
        esc(entry.def.icon) + " " + esc(entry.def.label.toUpperCase()) +
        (entry.def.abi ? " " + esc(entry.def.abi.toUpperCase()) : "") + "</button>");
    });
    host.innerHTML = chips.join("");
    syncChips();
  }

  function syncChips() {
    var chips = document.querySelectorAll("#platform-filter .chipbtn");
    Array.prototype.forEach.call(chips, function (chip) {
      chip.setAttribute("aria-pressed", String(chip.dataset.platform === state.platform));
    });
  }

  function renderHeaderFacts(apiStatus) {
    var rows = state.rows;
    var newest = rows[0] || null;
    var oldest = rows[rows.length - 1] || null;

    setText($("spec-versions"), String(rows.length));
    setText($("spec-first"), oldest ? oldest.tag : "—");
    setText($("spec-latest"), newest ? newest.tag : "—");

    var badge = $("ver-badge");
    if (badge && newest) {
      badge.textContent = newest.tag;
      badge.title = newest.tag + " — latest release on GitHub";
      badge.href = newest.releaseUrl || LATEST_URL;
    }

    var stamp = $("data-stamp");
    if (stamp) {
      stamp.textContent = [
        "GITHUB RELEASES API (LIVE)",
        rows.length + " PUBLISHED RELEASES",
        countWithBuilds(rows) + " WITH ATTACHED APPS",
        apiStatus === "ok" ? "REAL-TIME TRACKING" : "OFFLINE CACHE"
      ].join(" · ");
    }

    var note = $("api-note");
    if (!note) return;
    note.hidden = false;
    if (apiStatus === "ok") {
      note.className = "mono api-note";
      note.innerHTML = "ALL RELEASES, FILE SIZES AND DOWNLOAD COUNTERS ARE RETRIEVED LIVE FROM THE GITHUB RELEASES API. " +
        "NEW VERSIONS APPEAR AUTOMATICALLY AS THEY ARE PUBLISHED.";
    } else {
      note.className = "mono api-note warn";
      note.innerHTML = "COULD NOT CONNECT TO GITHUB API DIRECTLY. VIEW ALL RELEASES ON " +
        '<a href="' + esc(RELEASES_URL) + '" target="_blank" rel="noopener">GITHUB RELEASES ↗</a>.';
    }
  }

  function renderAll(apiStatus) {
    state.latestTag = state.rows.length ? state.rows[0].tag : null;
    state.device = detectDevice(navigator.userAgent, navigator.platform);
    renderHeaderFacts(apiStatus);
    renderLatest(state.rows[0]);
    renderMatrix();
    renderFilterChips();
    renderLedger();
  }

  // ------------------------------------------------------------ data load ---
  function readCache(key, ttl) {
    try {
      var raw = sessionStorage.getItem(key);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (!parsed || (Date.now() - parsed.at) > ttl) return null;
      return parsed.data;
    } catch (err) {
      return null;
    }
  }

  function writeCache(key, data) {
    try {
      sessionStorage.setItem(key, JSON.stringify({ at: Date.now(), data: data }));
    } catch (err) {
      /* quota or incognito mode */
    }
  }

  function fetchJson(url, cacheKey, ttl) {
    if (cacheKey) {
      var cached = readCache(cacheKey, ttl);
      if (cached) return Promise.resolve(cached);
    }
    return fetch(url, { headers: { Accept: "application/vnd.github+json" } })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        if (cacheKey) writeCache(cacheKey, data);
        return data;
      });
  }

  function renderFailure(apiError) {
    var message = "COULD NOT REACH GITHUB RELEASES API (" +
      esc(String(apiError && apiError.message)) + ").";
    var list = $("assets");
    if (list) {
      list.innerHTML = '<div class="error-state mono">' + message + "<br><br>" +
        '<a href="' + esc(RELEASES_URL) + '" target="_blank" rel="noopener">BROWSE ALL RELEASES ON GITHUB ↗</a></div>';
    }
    setText($("rel-tag"), "RELEASE DATA UNAVAILABLE");
    setText($("rel-date"), "");
    setText($("rel-subject"), "The releases page connects to GitHub Releases to display published packages.");
    setText($("rel-commit"), "");
    var ledger = $("ledger-list");
    if (ledger) ledger.innerHTML = '<div class="error-state mono">' + message + "</div>";
    setText($("ledger-status"), "OFFLINE");
    var note = $("api-note");
    if (note) {
      note.hidden = false;
      note.className = "mono api-note warn";
      note.innerHTML = 'GITHUB RELEASES API UNREACHABLE OR RATE LIMITED. VERIFY ON <a href="' + esc(RELEASES_URL) + '" target="_blank" rel="noopener">GITHUB RELEASES ↗</a>.';
    }
  }

  function boot() {
    var badge = $("ver-badge");
    if (badge) { badge.textContent = "v—"; badge.href = LATEST_URL; }

    fetchJson(CONFIG.releasesApi, CONFIG.cacheKey, CONFIG.cacheTtlMs)
      .then(function (data) {
        if (!Array.isArray(data) || !data.length) {
          throw new Error("No public releases found");
        }
        state.rows = parseReleases(data);
        renderAll("ok");
      })
      .catch(function (error) {
        renderFailure(error);
      });
  }

  // ----------------------------------------------------------------- wiring --
  function findClosest(target, selector) {
    return target && target.closest ? target.closest(selector) : null;
  }

  function fillNotes(card) {
    var box = card ? card.querySelector(".ver-notes") : null;
    if (!box || box.dataset.filled === "1") return;
    var idx = Number(box.dataset.notes);
    var row = state.orderedRows ? state.orderedRows[idx] : null;
    box.innerHTML = notesHtml(state.notes[idx], row);
    box.dataset.filled = "1";
  }

  function setAllOpen(open) {
    var cards = document.querySelectorAll("#ledger-list details.ver");
    Array.prototype.forEach.call(cards, function (card) {
      card.open = open;
      if (open) fillNotes(card);
    });
  }

  function clearFilters() {
    state.platform = "all";
    state.query = "";
    var search = $("ledger-search");
    if (search) search.value = "";
    syncChips();
    renderLedger();
  }

  function wire() {
    var list = $("ledger-list");
    if (list) {
      list.addEventListener("toggle", function (event) {
        var card = event.target;
        if (!card || card.tagName !== "DETAILS" || !card.open) return;
        fillNotes(card);
      }, true);

      list.addEventListener("click", function (event) {
        if (findClosest(event.target, "[data-reset]")) clearFilters();
      });
    }

    var filterHost = $("platform-filter");
    if (filterHost) {
      filterHost.addEventListener("click", function (event) {
        var chip = findClosest(event.target, ".chipbtn");
        if (!chip || !chip.dataset.platform) return;
        state.platform = chip.dataset.platform;
        syncChips();
        renderLedger();
      });
    }

    var search = $("ledger-search");
    if (search) {
      var timer = null;
      search.addEventListener("input", function () {
        clearTimeout(timer);
        timer = setTimeout(function () {
          state.query = search.value;
          renderLedger();
        }, 150);
      });
    }

    var orderToggle = $("order-toggle");
    if (orderToggle) {
      orderToggle.addEventListener("click", function () {
        state.order = state.order === "asc" ? "desc" : "asc";
        orderToggle.textContent = state.order === "asc" ? "ORDER: OLDEST FIRST" : "ORDER: NEWEST FIRST";
        orderToggle.setAttribute("aria-pressed", String(state.order === "desc"));
        renderLedger();
      });
    }

    var expandAll = $("expand-all");
    if (expandAll) expandAll.addEventListener("click", function () { setAllOpen(true); });

    var collapseAll = $("collapse-all");
    if (collapseAll) collapseAll.addEventListener("click", function () { setAllOpen(false); });

    var matrix = $("matrix-body");
    if (matrix) {
      matrix.addEventListener("click", function (event) {
        var link = findClosest(event.target, "a[data-ver]");
        if (!link) return;
        var card = $("ver-" + link.dataset.ver);
        if (!card) return;
        event.preventDefault();
        card.open = true;
        fillNotes(card);
        card.scrollIntoView({ block: "center" });
      });
    }
  }

  // ----------------------------------------------------------------- export --
  var API = {
    CONFIG: CONFIG,
    PLATFORMS: PLATFORMS,
    classifyAsset: classifyAsset,
    groupAssets: groupAssets,
    parseReleases: parseReleases,
    filterRows: filterRows,
    platformSummary: platformSummary,
    countWithBuilds: countWithBuilds,
    detectDevice: detectDevice,
    pickRecommended: pickRecommended,
    formatSize: formatSize,
    formatDate: formatDate,
    formatIso: formatIso,
    esc: esc,
    inlineMd: inlineMd,
    totalDownloads: totalDownloads
  };

  if (typeof module !== "undefined" && module.exports) module.exports = API;
  global.SautiDownloads = API;

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () { wire(); boot(); });
    } else {
      wire();
      boot();
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
