(() => {
  const versionLabel = document.getElementById("version-chip");
  const downloadBtn = document.getElementById("download-btn");

  fetch("./version.json", { cache: "no-store" })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || !data.version) return;
      if (versionLabel) versionLabel.textContent = `v${data.version}`;
      if (downloadBtn && data.downloadURL) {
        downloadBtn.setAttribute("href", data.downloadURL);
      }
    })
    .catch(() => {});

  const root = document.querySelector("[data-carousel]");
  if (!root) return;

  const slides = Array.from(root.querySelectorAll(".slide"));
  const dots = Array.from(root.querySelectorAll(".dot"));
  const caption = root.querySelector("[data-caption]");
  const captions = ["截图 · 框选即得", "录屏 · 一键开录", "标注 · 改完就走"];
  let index = 0;
  let timer = 0;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const interval = 5200;

  const go = (next) => {
    index = (next + slides.length) % slides.length;
    slides.forEach((s, i) => s.classList.toggle("is-active", i === index));
    dots.forEach((d, i) => {
      const on = i === index;
      d.classList.toggle("is-active", on);
      d.setAttribute("aria-selected", on ? "true" : "false");
    });
    if (caption) caption.textContent = captions[index] || "";
  };

  const stop = () => {
    if (timer) window.clearInterval(timer);
    timer = 0;
  };

  const start = () => {
    if (reduce || slides.length < 2) return;
    stop();
    timer = window.setInterval(() => go(index + 1), interval);
  };

  dots.forEach((dot) => {
    dot.addEventListener("click", () => {
      const i = Number(dot.getAttribute("data-goto") || "0");
      go(i);
      start();
    });
  });

  root.addEventListener("pointerenter", stop);
  root.addEventListener("pointerleave", start);

  document.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight") {
      go(index + 1);
      start();
    } else if (e.key === "ArrowLeft") {
      go(index - 1);
      start();
    }
  });

  go(0);
  start();
})();
