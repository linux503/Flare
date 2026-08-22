(() => {
  fetch("./version.json", { cache: "no-cache" })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || !data.version) return;
      document.querySelectorAll("[data-app-version]").forEach((el) => {
        el.textContent = `v${data.version}`;
      });
      const dmg = data.downloadURL
        || `https://github.com/linux503/Flare/releases/download/v${data.version}/Flare-Pro-${data.version}-Universal.dmg`;
      document.querySelectorAll("[data-download]").forEach((el) => {
        el.setAttribute("href", dmg);
      });
      if (data.windowsURL) {
        document.querySelectorAll("[data-download-windows]").forEach((el) => {
          el.setAttribute("href", data.windowsURL);
        });
      }
      if (data.androidURL) {
        document.querySelectorAll("[data-download-android]").forEach((el) => {
          el.setAttribute("href", data.androidURL);
        });
      }
    })
    .catch(() => {});

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
    }, { threshold: 0.14, rootMargin: "0px 0px -6% 0px" });
    items.forEach((el) => io.observe(el));
  };
  reveal();

  const ua = navigator.userAgent || "";
  const you = /Android/i.test(ua) ? "android" : /Windows/i.test(ua) ? "win" : /Mac|iPhone|iPad/i.test(ua) ? "mac" : "";
  if (you) document.querySelector(`.hero-dls .dl-btn.${you}`)?.classList.add("is-you");

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
  document.querySelectorAll(".nav-links a").forEach((a) => {
    a.addEventListener("click", closeNav);
  });
  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeNav();
  });

  const sections = ["shot", "rec", "docs", "start", "get"]
    .map((id) => document.getElementById(id))
    .filter(Boolean);
  const linkOf = (id) => document.querySelector(`.nav-links a[href="#${id}"]`);
  if (sections.length) {
    const spy = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        document.querySelectorAll(".nav-links a").forEach((a) => a.classList.remove("is-on"));
        linkOf(entry.target.id)?.classList.add("is-on");
      });
    }, { rootMargin: "-40% 0px -50% 0px", threshold: 0.01 });
    sections.forEach((el) => spy.observe(el));
  }

  const fine = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  if (!reduce && fine) {
    document.body.classList.add("is-pointer");
    const orb = document.querySelector(".cursor-orb");
    let ox = 0, oy = 0, tx = 0, ty = 0, raf = 0;
    const tick = () => {
      ox += (tx - ox) * 0.12;
      oy += (ty - oy) * 0.12;
      if (orb) orb.style.transform = `translate(${ox}px, ${oy}px)`;
      raf = window.requestAnimationFrame(tick);
    };
    window.addEventListener("pointermove", (e) => {
      tx = e.clientX;
      ty = e.clientY;
    }, { passive: true });
    tick();
    document.querySelectorAll(".pill").forEach((el) => {
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        const x = (e.clientX - r.left - r.width / 2) * 0.16;
        const y = (e.clientY - r.top - r.height / 2) * 0.16;
        el.style.transform = `translate(${x}px, ${y}px)`;
      });
      el.addEventListener("pointerleave", () => {
        el.style.transform = "";
      });
    });
    document.querySelectorAll("[data-spot]").forEach((el) => {
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        el.style.setProperty("--sx", `${((e.clientX - r.left) / r.width) * 100}%`);
        el.style.setProperty("--sy", `${((e.clientY - r.top) / r.height) * 100}%`);
      });
    });
    const stage = document.querySelector(".stage");
    const show = document.querySelector(".showcase");
    show?.addEventListener("pointermove", (e) => {
      if (!stage) return;
      const r = show.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      stage.style.setProperty("--tilt-y", `${x * 8}deg`);
      stage.style.setProperty("--tilt-x", `${-y * 6}deg`);
    });
    show?.addEventListener("pointerleave", () => {
      if (!stage) return;
      stage.style.setProperty("--tilt-y", "0deg");
      stage.style.setProperty("--tilt-x", "0deg");
    });
  }

  const root = document.querySelector("[data-carousel]");
  if (!root) return;

  const frames = Array.from(root.querySelectorAll(".stage img"));
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

  const stop = () => {
    if (timer) window.clearInterval(timer);
    timer = 0;
  };

  const start = () => {
    if (reduce || frames.length < 2) return;
    stop();
    timer = window.setInterval(() => show(index + 1), 4800);
  };

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      show(Number(tab.getAttribute("data-goto") || "0"));
      start();
    });
  });

  root.addEventListener("pointerenter", stop);
  root.addEventListener("pointerleave", start);

  show(0);
  start();
})();
