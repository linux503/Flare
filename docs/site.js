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
