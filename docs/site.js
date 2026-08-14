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

  const stage = document.querySelector("[data-parallax]");
  if (!stage || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  if (window.matchMedia("(pointer: coarse)").matches) return;

  const mount = stage.querySelector(".stage-mount");
  const marquee = stage.querySelector(".marquee");
  const shot = stage.querySelector(".shot");

  let raf = 0;
  let tx = 0;
  let ty = 0;
  let cx = 0;
  let cy = 0;

  const tick = () => {
    cx += (tx - cx) * 0.08;
    cy += (ty - cy) * 0.08;
    if (mount) mount.style.transform = `translate3d(${cx * -12}px, ${cy * -8}px, 0)`;
    if (marquee) marquee.style.transform = `translate3d(${cx * 10}px, ${cy * 6}px, 0)`;
    if (shot) {
      shot.style.transform = `translate(calc(-50% + ${cx * 18}px), calc(-54% + ${cy * 12}px))`;
    }
    raf = requestAnimationFrame(tick);
  };

  stage.addEventListener(
    "pointermove",
    (e) => {
      const r = stage.getBoundingClientRect();
      tx = (e.clientX - r.left) / r.width - 0.5;
      ty = (e.clientY - r.top) / r.height - 0.5;
    },
    { passive: true }
  );

  stage.addEventListener("pointerleave", () => {
    tx = 0;
    ty = 0;
  });

  raf = requestAnimationFrame(tick);
})();
