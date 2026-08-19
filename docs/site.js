(() => {
  fetch("./version.json", { cache: "no-store" })
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

  const root = document.querySelector("[data-carousel]");
  if (!root) return;

  const frames = Array.from(root.querySelectorAll(".stage img"));
  const tabs = Array.from(root.querySelectorAll(".switcher button"));
  let index = 0;
  let timer = 0;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const show = (i) => {
    index = (i + frames.length) % frames.length;
    frames.forEach((el, n) => el.classList.toggle("on", n === index));
    tabs.forEach((el, n) => el.classList.toggle("on", n === index));
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
