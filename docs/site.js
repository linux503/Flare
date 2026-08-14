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
  const tag = root.querySelector("[data-tag]");
  const prev = root.querySelector("[data-prev]");
  const next = root.querySelector("[data-next]");

  const copy = [
    { tag: "截图", caption: "框选瞬间完成，工具栏直达下一步" },
    { tag: "录屏", caption: "独立录制菜单，暂停、倒计时、导出 MOV" },
    { tag: "标注", caption: "箭头高亮马赛克，OCR 识字顺手导出" },
  ];

  let index = 0;
  let timer = 0;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const paint = () => {
    slides.forEach((s, i) => s.classList.toggle("is-active", i === index));
    dots.forEach((d, i) => {
      const on = i === index;
      d.classList.toggle("is-active", on);
      d.setAttribute("aria-selected", on ? "true" : "false");
    });
    const item = copy[index] || copy[0];
    if (caption) caption.textContent = item.caption;
    if (tag) {
      tag.textContent = item.tag;
      tag.style.background =
        index === 1 ? "var(--red)" : index === 2 ? "var(--amber)" : "var(--teal)";
      tag.style.color = index === 1 || index === 2 ? "#1a1208" : "var(--teal-ink)";
      if (index === 1) tag.style.color = "#2a0707";
    }
  };

  const go = (n) => {
    index = (n + slides.length) % slides.length;
    paint();
  };

  const stop = () => {
    if (timer) window.clearInterval(timer);
    timer = 0;
  };

  const start = () => {
    if (reduce || slides.length < 2) return;
    stop();
    timer = window.setInterval(() => go(index + 1), 5600);
  };

  dots.forEach((dot) => {
    dot.addEventListener("click", () => {
      go(Number(dot.getAttribute("data-goto") || "0"));
      start();
    });
  });
  prev && prev.addEventListener("click", () => { go(index - 1); start(); });
  next && next.addEventListener("click", () => { go(index + 1); start(); });

  root.addEventListener("pointerenter", stop);
  root.addEventListener("pointerleave", start);
  document.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight") { go(index + 1); start(); }
    if (e.key === "ArrowLeft") { go(index - 1); start(); }
  });

  paint();
  start();
})();
