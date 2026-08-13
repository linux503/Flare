(() => {
  const versionLabel = document.getElementById("version-label");
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
})();
