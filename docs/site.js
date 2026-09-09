(() => {
  const ICONS = {
    mac: "M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z",
    win: "M3 5.5L10.5 4.6v7.5H3V5.5zm10.5-.9L21 3.5v8.6h-7.5V4.6zM3 13.5h7.5v7.5L3 19.6V13.5zm10.5 0H21v6.1l-7.5 1.4V13.5z",
    android: "M6 18c0 .55.45 1 1 1h1v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h2v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h1c.55 0 1-.45 1-1V8H6v10zM3.5 8C2.67 8 2 8.67 2 9.5v7c0 .83.67 1.5 1.5 1.5S5 17.33 5 16.5v-7C5 8.67 4.33 8 3.5 8zm17 0c-.83 0-1.5.67-1.5 1.5v7c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5v-7c0-.83-.67-1.5-1.5-1.5zm-4.97-5.41l1.41-1.41 1.06 1.06-1.41 1.41-1.06-1.06zm-6.12 0l-1.06-1.06-1.41 1.41 1.06 1.06 1.41-1.41zM12 4.5c-2.67 0-4.83 2.16-4.83 4.83h9.66C16.83 6.66 14.67 4.5 12 4.5z",
  };

  const defaults = {
    mac: {
      href: "./downloads/Flare-Pro-1.3.21-Universal.dmg",
      file: "DMG · Universal",
      titleKey: "dl.macTitle",
      download: true,
    },
    win: {
      href: "https://github.com/linux503/Flare/releases/download/v1.3.19/Flare-Windows-x64.exe",
      file: "EXE · x64",
      titleKey: "dl.winTitle",
      download: false,
    },
    android: {
      href: "./downloads/Flare-Android.apk",
      file: "APK",
      titleKey: "dl.andTitle",
      download: true,
    },
  };

  let catalog = { ...defaults };
  let current = "mac";
  let releaseMeta = null;

  const t = (key, fallback) => {
    const dict = window.__flareI18n;
    if (dict && dict[key]) return dict[key];
    return fallback;
  };

  const escapeHtml = (text) => String(text).replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]));

  const renderChangelog = () => {
    if (!releaseMeta) return;
    const lang = document.documentElement.lang === "en" ? "en" : "zh";
    const items = (lang === "en" && Array.isArray(releaseMeta.changelogEn) && releaseMeta.changelogEn.length)
      ? releaseMeta.changelogEn
      : (Array.isArray(releaseMeta.changelog) ? releaseMeta.changelog : []);
    const list = document.querySelector("[data-changelog]");
    if (list && items.length) {
      list.innerHTML = items.map((text) => `<li>${escapeHtml(text)}</li>`).join("");
    }
  };

  const titleFor = (os) => {
    const map = {
      mac: ["dl.macTitle", "下载 macOS 版"],
      win: ["dl.winTitle", "下载 Windows 版"],
      android: ["dl.andTitle", "下载 Android 版"],
    };
    const [key, fallback] = map[os] || map.mac;
    return t(key, fallback);
  };

  const detectOs = () => {
    const ua = navigator.userAgent || "";
    if (/Android/i.test(ua)) return "android";
    if (/Win/i.test(ua)) return "win";
    return "mac";
  };

  const applyOs = (os) => {
    const item = catalog[os] || catalog.mac;
    current = os;
    document.querySelectorAll("[data-dl-dock] .dl-tabs button").forEach((btn) => {
      const on = btn.getAttribute("data-os") === os;
      btn.classList.toggle("is-on", on);
      btn.setAttribute("aria-selected", on ? "true" : "false");
    });
    document.querySelectorAll("[data-dl-main]").forEach((el) => {
      el.setAttribute("href", item.href);
      el.setAttribute("data-os", os);
      if (item.download) el.setAttribute("download", "");
      else el.removeAttribute("download");
    });
    document.querySelectorAll("[data-dl-title]").forEach((el) => {
      el.textContent = titleFor(os);
      el.setAttribute("data-i18n", item.titleKey);
    });
    document.querySelectorAll("[data-dl-file]").forEach((el) => {
      el.textContent = item.file;
    });
    document.querySelectorAll("[data-dl-icon]").forEach((svg) => {
      const path = svg.querySelector("path");
      if (path) path.setAttribute("d", ICONS[os] || ICONS.mac);
    });
  };

  fetch("./version.json", { cache: "no-cache" })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || !data.version) return;
      document.querySelectorAll("[data-app-version]").forEach((el) => {
        el.textContent = `v${data.version}`;
      });
      if (data.publishedAt) {
        document.querySelectorAll("[data-published-at]").forEach((el) => {
          el.textContent = data.publishedAt;
        });
      }
      releaseMeta = data;
      renderChangelog();
      const dmg = data.downloadURL || `./downloads/Flare-Pro-${data.version}-Universal.dmg`;
      const win = data.windowsURL
        || `https://github.com/linux503/Flare/releases/download/v${data.version}/Flare-Windows-x64.exe`;
      const apk = data.androidURL || "./downloads/Flare-Android.apk";
      catalog = {
        mac: { ...defaults.mac, href: dmg, download: !/^https?:\/\/github\.com\//.test(dmg) },
        win: { ...defaults.win, href: win, download: false },
        android: { ...defaults.android, href: apk, download: !/^https?:\/\/github\.com\//.test(apk) },
      };
      document.querySelectorAll("[data-download]").forEach((el) => el.setAttribute("href", catalog.mac.href));
      document.querySelectorAll("[data-download-windows]").forEach((el) => el.setAttribute("href", catalog.win.href));
      document.querySelectorAll("[data-download-android]").forEach((el) => el.setAttribute("href", catalog.android.href));
      applyOs(current);
    })
    .catch(() => {});

  current = detectOs();
  applyOs(current);
  document.querySelectorAll("[data-dl-dock] .dl-tabs button").forEach((btn) => {
    btn.addEventListener("click", () => applyOs(btn.getAttribute("data-os") || "mac"));
  });

  window.addEventListener("flare:lang", () => {
    applyOs(current);
    renderChangelog();
  });

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const reveal = () => {
    const items = Array.from(document.querySelectorAll("[data-reveal]"));
    if (!items.length) return;
    if (reduce) {
      items.forEach((el) => el.classList.add("in"));
      return;
    }
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("in");
        io.unobserve(entry.target);
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    items.forEach((el) => io.observe(el));
  };
  reveal();

  const header = document.querySelector(".site-header");
  const bar = document.querySelector(".scroll-progress");
  const onScroll = () => {
    const max = document.documentElement.scrollHeight - window.innerHeight;
    const p = max > 0 ? window.scrollY / max : 0;
    if (bar) bar.style.transform = `scaleX(${Math.min(1, Math.max(0, p))})`;
    header?.classList.toggle("is-on", window.scrollY > 24);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  const toggle = document.querySelector(".nav-toggle");
  const closeNav = () => {
    header?.classList.remove("nav-open");
    toggle?.setAttribute("aria-expanded", "false");
  };
  toggle?.addEventListener("click", () => {
    const open = header.classList.toggle("nav-open");
    toggle.setAttribute("aria-expanded", open ? "true" : "false");
  });
  document.querySelectorAll(".nav-links a").forEach((a) => a.addEventListener("click", closeNav));
  window.addEventListener("keydown", (e) => { if (e.key === "Escape") closeNav(); });

  const sections = ["features", "scenarios", "privacy", "platforms", "get"]
    .map((id) => document.getElementById(id))
    .filter(Boolean);
  if (sections.length) {
    const spy = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        document.querySelectorAll(".nav-links > a").forEach((a) => a.classList.remove("is-on"));
        document.querySelector(`.nav-links > a[href="#${entry.target.id}"]`)?.classList.add("is-on");
      });
    }, { rootMargin: "-40% 0px -50% 0px", threshold: 0.01 });
    sections.forEach((el) => spy.observe(el));
  }

  const root = document.querySelector("[data-carousel]");
  if (!root) return;

  const frames = Array.from(root.querySelectorAll(".proof-frame"));
  const tabs = Array.from(root.querySelectorAll(".switcher button"));
  let index = 0;
  let timer = 0;

  const show = (i) => {
    index = (i + frames.length) % frames.length;
    frames.forEach((el, n) => el.classList.toggle("on", n === index));
    tabs.forEach((el, n) => {
      const on = n === index;
      el.classList.toggle("on", on);
      el.setAttribute("aria-selected", on ? "true" : "false");
    });
  };

  const arm = () => {
    if (reduce || frames.length < 2) return;
    clearInterval(timer);
    timer = setInterval(() => show(index + 1), 5200);
  };

  tabs.forEach((btn) => {
    btn.addEventListener("click", () => {
      show(Number(btn.getAttribute("data-goto") || 0));
      arm();
    });
  });
  show(0);
  arm();
})();
