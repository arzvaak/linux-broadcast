const version = "0.2.0";
const base = `https://arzvak.com/downloads/linux-broadcast/v${version}`;
let series = "rtx40";
let format = "rpm";

const names = { rtx20: "RTX 20", rtx30: "RTX 30", rtx40: "RTX 40", rtx50: "RTX 50" };
const formats = {
  rpm: { label: "RPM", file: () => `linux-broadcast-${version}-${series}.x86_64.rpm` },
  deb: { label: "DEB", file: () => `linux-broadcast_${version}_${series}_amd64.deb` },
  tar: { label: "portable TAR", file: () => `linux-broadcast-${version}-${series}-x86_64.tar` },
};

function updateDownload() {
  const button = document.querySelector("#downloadButton");
  button.href = `${base}/${formats[format].file()}`;
  button.querySelector("b").textContent = `Download for ${names[series]}`;
  document.querySelector("#downloadMeta").textContent = `${formats[format].label} · x86_64 · about 2.8 GB`;
}

function select(group, chosen, attribute) {
  group.querySelectorAll("button").forEach((button) => {
    const active = button.dataset[attribute] === chosen;
    button.classList.toggle("selected", active);
    button.setAttribute("aria-checked", String(active));
  });
}

document.querySelectorAll("[data-series]").forEach((button) => button.addEventListener("click", () => {
  series = button.dataset.series;
  select(document.querySelector(".gpu-choices"), series, "series");
  updateDownload();
}));

document.querySelectorAll("[data-format]").forEach((button) => button.addEventListener("click", () => {
  format = button.dataset.format;
  select(document.querySelector(".format-choices"), format, "format");
  updateDownload();
}));

const agent = navigator.userAgent.toLowerCase();
if (agent.includes("ubuntu") || agent.includes("debian")) {
  format = "deb";
  select(document.querySelector(".format-choices"), format, "format");
  updateDownload();
}
