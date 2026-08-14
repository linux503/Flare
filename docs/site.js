(() => {
  const versionLabel = document.getElementById("version-chip");
  const downloadBtn = document.getElementById("download-btn");

  fetch("./version.json", { cache: "no-store" })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || !data.version) return;
      if (versionLabel) versionLabel.textContent = `v${data.version}`;
      if (downloadBtn && data.downloadURL) {
        downloadBtn.href = data.downloadURL;
      }
    })
    .catch(() => {});

  const root = document.querySelector("[data-carousel]");
  if (!root) return;

  const frames = Array.from(root.querySelectorAll(".frame"));
  const tabs = Array.from(root.querySelectorAll(".tab"));
  let index = 0;
  let timer = 0;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const show = (i) => {
    index = (i + frames.length) % frames.length;
    frames.forEach((el, n) => el.classList.toggle("is-on", n === index));
    tabs.forEach((el, n) => el.classList.toggle("is-on", n === index));
  };

  const stop = () => {
    if (timer) window.clearInterval(timer);
    timer = 0;
  };

  const start = () => {
    if (reduce || frames.length < 2) return;
    stop();
    timer = window.setInterval(() => show(index + 1), 5000);
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
