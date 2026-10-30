const $ = (selector) => document.querySelector(selector);
const state = {home: "", root: "", path: "", page: 0, query: "", folder: null, request: 0, timer: null, phase: "idle"};
const colors = ["#557f70", "#9cc6a8", "#d9e9b6", "#f1d5a8", "#c5dbd2", "#e5e7d0", "#b7d4b8", "#f2e5c9", "#dce9df", "#d7e2b4", "#e9e4d5", "#c7d9c7"];
const darkText = (index) => index !== 0;

function formatSize(bytes) {
  if (!Number.isFinite(bytes)) return "—";
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB", "PB"];
  let value = bytes / 1024, unit = 0;
  while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
  return `${value >= 100 ? value.toFixed(0) : value >= 10 ? value.toFixed(1) : value.toFixed(2)} ${units[unit]}`;
}

function icon(name) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", `#i-${name}`);
  svg.append(use);
  return svg;
}

function toast(message) {
  const element = $("#toast");
  element.textContent = message;
  element.classList.add("show");
  clearTimeout(toast.timeout);
  toast.timeout = setTimeout(() => element.classList.remove("show"), 2600);
}

async function request(url, options) {
  const response = await fetch(url, options);
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || "请求失败");
  return data;
}

function updateDisk(disk) {
  const percent = Math.round(disk.used / disk.total * 100);
  $("#used-size").textContent = formatSize(disk.used);
  $("#total-size").textContent = formatSize(disk.total);
  $("#free-size").textContent = formatSize(disk.free);
  $("#used-percent").textContent = `${percent}% 已使用`;
  $("#donut-percent").textContent = `${percent}%`;
  $("#capacity-fill").style.width = `${percent}%`;
  $("#donut").style.background = `conic-gradient(#4e8163 0 ${percent}%, #d4e6d4 ${percent}% 100%)`;
}

function setActivePreset(path) {
  document.querySelectorAll("[data-preset]").forEach(button => {
    const preset = presetPath(button.dataset.preset);
    button.classList.toggle("active", preset === path);
  });
}

function presetPath(preset) {
  return {home: state.home, downloads: `${state.home}/Downloads`, applications: "/Applications", disk: "/"}[preset];
}

async function beginScan(path) {
  if (state.phase === "scanning") { toast("当前扫描还未结束，请稍候"); return; }
  try {
    await request("/api/scan", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({path})});
    state.phase = "scanning";
    state.root = path;
    state.path = "";
    state.folder = null;
    state.request++;
    $("#results").classList.add("hidden");
    $("#empty-state").classList.add("hidden");
    $("#notice").classList.add("hidden");
    $("#location-panel").classList.add("hidden");
    $("#scan-banner").classList.remove("hidden");
    $("#scan-meta").textContent = "正在扫描";
    setActivePreset(path);
    clearTimeout(state.timer);
    state.timer = setTimeout(pollStatus, 300);
  } catch (error) { toast(error.message); }
}

async function pollStatus() {
  try {
    const {scan, disk, home} = await request("/api/status");
    state.home = home;
    state.phase = scan.phase;
    updateDisk(disk);
    if (scan.phase === "scanning") {
      $("#scan-banner").classList.remove("hidden");
      $("#empty-state").classList.add("hidden");
      $("#scan-progress").textContent = `已读取 ${(scan.counts.files || 0).toLocaleString()} 个文件 · ${(scan.counts.folders || 0).toLocaleString()} 个文件夹 · ${scan.current}`;
      $("#scan-time").textContent = `${Math.round(scan.elapsed)} 秒`;
      $("#scan-meta").textContent = "正在扫描";
      state.timer = setTimeout(pollStatus, 850);
    } else if (scan.phase === "complete") {
      $("#scan-banner").classList.add("hidden");
      const counts = scan.counts;
      $("#scan-meta").textContent = `${counts.files.toLocaleString()} 个文件 · 用时 ${Math.round(scan.elapsed)} 秒`;
      if (counts.skipped) {
        $("#notice").textContent = `${counts.skipped.toLocaleString()} 个位置无法读取或属于其他磁盘，已跳过。若要查看更多系统目录，请在 macOS 中授予终端“完全磁盘访问权限”。`;
        $("#notice").classList.remove("hidden");
      }
      if (!state.folder || state.root !== scan.path) {
        state.root = scan.path;
        setActivePreset(scan.path);
        await openFolder(scan.path);
      }
    } else {
      $("#scan-banner").classList.add("hidden");
      if (scan.phase === "error") {
        $("#notice").textContent = `扫描失败：${scan.error}`;
        $("#notice").classList.remove("hidden");
      }
      $("#empty-state").classList.remove("hidden");
      $("#scan-meta").textContent = "等待扫描";
    }
    if (scan.phase !== "scanning") state.timer = setTimeout(pollStatus, 4000);
  } catch (error) {
    $("#scan-banner").classList.add("hidden");
    $("#empty-state").classList.remove("hidden");
    toast(`无法连接本地服务：${error.message}`);
  }
}

async function openFolder(path, append = false, resetFilter = true) {
  const requestId = ++state.request;
  if (!append) {
    state.path = path;
    state.page = 0;
    if (resetFilter) {
      state.query = "";
      $("#filter-input").value = "";
    }
  }
  try {
    const params = new URLSearchParams({path, query: state.query, page: state.page});
    const folder = await request(`/api/folder?${params}`);
    if (requestId !== state.request) return;
    state.folder = folder;
    state.root = folder.root_path;
    $("#results").classList.remove("hidden");
    $("#empty-state").classList.add("hidden");
    if (!append) {
      renderBreadcrumbs(folder);
      renderTreemap(folder);
      renderLargest(folder);
      $("#file-list").replaceChildren();
    }
    renderList(folder, append);
  } catch (error) { if (requestId === state.request) toast(error.message); }
}

function renderBreadcrumbs(folder) {
  const box = $("#breadcrumbs");
  box.replaceChildren();
  const root = folder.root_path;
  const paths = [{name: root === "/" ? "启动磁盘" : root.split("/").pop(), path: root}];
  const relative = folder.path.slice(root === "/" ? 1 : root.length).split("/").filter(Boolean);
  let current = root === "/" ? "" : root;
  for (const part of relative) { current += `/${part}`; paths.push({name: part, path: current}); }
  paths.forEach((part, index) => {
    if (index) box.append(icon("arrow"));
    const button = document.createElement("button");
    button.textContent = part.name;
    button.title = part.path;
    button.onclick = () => { if (part.path !== state.path) openFolder(part.path); };
    box.append(button);
  });
}

function splitTiles(items, x, y, width, height, output) {
  if (!items.length) return;
  if (items.length === 1) { output.push({...items[0], x, y, width, height}); return; }
  const total = items.reduce((sum, item) => sum + item.weight, 0);
  let left = 0, cutoff = 0;
  while (cutoff < items.length - 1 && (left < total / 2 || cutoff === 0)) left += items[cutoff++].weight;
  const share = left / total;
  if (width >= height) {
    splitTiles(items.slice(0, cutoff), x, y, width * share, height, output);
    splitTiles(items.slice(cutoff), x + width * share, y, width * (1 - share), height, output);
  } else {
    splitTiles(items.slice(0, cutoff), x, y, width, height * share, output);
    splitTiles(items.slice(cutoff), x, y + height * share, width, height * (1 - share), output);
  }
}

function renderTreemap(folder) {
  const map = $("#treemap");
  map.replaceChildren();
  $("#visual-total").textContent = formatSize(folder.size);
  if (!folder.treemap.length) {
    const label = document.createElement("div");
    label.className = "no-files";
    label.textContent = "这个文件夹是空的";
    map.append(label);
    return;
  }
  const items = folder.treemap.map(item => ({...item, weight: Math.max(item.size, folder.size * .003, 1)}));
  const tiles = [];
  splitTiles(items, 0, 0, 100, 100, tiles);
  tiles.forEach((item, index) => {
    const tile = document.createElement("div");
    tile.className = "tile";
    tile.style.cssText = `left:${item.x}%;top:${item.y}%;width:${item.width}%;height:${item.height}%;background:${colors[index % colors.length]};color:${darkText(index) ? "#365744" : "#fff"}`;
    tile.dataset.folder = item.type === "folder";
    tile.title = `${item.name} · ${formatSize(item.size)}`;
    if (item.width < 17 || item.height < 27) tile.classList.add("compact");
    if (item.width < 9 || item.height < 13) { tile.title = `${item.name} · ${formatSize(item.size)}`; map.append(tile); return; }
    tile.append(icon(item.type === "folder" ? "folder" : "file"));
    const label = document.createElement("div");
    const name = document.createElement("strong");
    name.textContent = item.name;
    const size = document.createElement("small");
    size.textContent = formatSize(item.size);
    label.append(name, size);
    tile.append(label);
    if (item.type === "folder") { tile.tabIndex = 0; tile.setAttribute("role", "button"); tile.setAttribute("aria-label", `打开 ${item.name}`); tile.onclick = () => openFolder(item.path); tile.onkeydown = event => { if (event.key === "Enter") openFolder(item.path); }; }
    map.append(tile);
  });
}

function renderList(folder, append) {
  $("#item-count").textContent = folder.filtered_items.toLocaleString();
  const list = $("#file-list");
  if (!append) list.replaceChildren();
  if (!folder.entries.length && !append) {
    const empty = document.createElement("div");
    empty.className = "no-files";
    empty.textContent = state.query ? "没有匹配的文件" : "这个文件夹是空的";
    list.append(empty);
  }
  folder.entries.forEach(item => {
    const row = document.createElement("div");
    row.className = `file-row ${item.type === "folder" ? "folder-row" : ""}`;
    const badge = document.createElement("span");
    badge.className = `file-icon ${item.type === "file" ? "file" : ""}`;
    badge.append(icon(item.type === "folder" ? "folder" : "file"));
    const label = document.createElement("div");
    label.className = "file-name";
    const name = document.createElement("strong");
    name.textContent = item.name;
    const detail = document.createElement("small");
    detail.textContent = item.type === "folder" ? `文件夹 · ${item.items.toLocaleString()} 个直接项目` : item.path;
    label.append(name, detail);
    const meter = document.createElement("div");
    meter.className = "row-meter";
    const fill = document.createElement("span");
    fill.style.width = `${Math.max(3, Math.min(100, item.size / (folder.size || 1) * 100))}%`;
    meter.append(fill);
    const size = document.createElement("div");
    size.className = "file-size";
    size.textContent = formatSize(item.size);
    const action = document.createElement("button");
    action.className = "row-action";
    action.title = item.type === "folder" ? "打开文件夹" : "复制文件路径";
    action.setAttribute("aria-label", action.title);
    action.append(icon(item.type === "folder" ? "arrow" : "copy"));
    if (item.type === "folder") { row.onclick = () => openFolder(item.path); action.onclick = event => { event.stopPropagation(); openFolder(item.path); }; }
    else action.onclick = () => copyPath(item.path);
    row.append(badge, label, meter, size, action);
    list.append(row);
  });
  $("#load-more").classList.toggle("hidden", (state.page + 1) * 80 >= folder.filtered_items);
}

function renderLargest(folder) {
  const section = $("#largest-section");
  section.classList.toggle("hidden", !folder.largest.length);
  const grid = $("#largest-grid");
  grid.replaceChildren();
  folder.largest.slice(0, 6).forEach(file => {
    const card = document.createElement("div");
    card.className = "large-file";
    card.title = `${file.path} · 点击复制路径`;
    card.style.cursor = "pointer";
    card.onclick = () => copyPath(file.path);
    const badge = document.createElement("span");
    badge.className = "file-icon file";
    badge.append(icon("file"));
    const info = document.createElement("div");
    info.className = "large-file-text";
    const name = document.createElement("strong");
    name.textContent = file.name;
    const path = document.createElement("small");
    path.textContent = file.path;
    info.append(name, path);
    const size = document.createElement("b");
    size.textContent = formatSize(file.size);
    card.append(badge, info, size);
    grid.append(card);
  });
}

async function copyPath(path) {
  try { await navigator.clipboard.writeText(path); toast("文件路径已复制"); }
  catch { toast(path); }
}

document.querySelectorAll("[data-preset]").forEach(button => button.onclick = () => beginScan(presetPath(button.dataset.preset)));
$("#rescan-button").onclick = () => beginScan(state.root || state.home);
$("#start-button").onclick = () => beginScan(state.home);
$("#choose-button").onclick = () => {
  $("#location-panel").classList.toggle("hidden");
  $("#custom-path").value = state.root || state.home;
  if (!$("#location-panel").classList.contains("hidden")) $("#custom-path").focus();
};
$("#custom-scan").onclick = () => beginScan($("#custom-path").value.trim());
$("#custom-path").onkeydown = event => { if (event.key === "Enter") beginScan(event.target.value.trim()); };
$("#load-more").onclick = () => { state.page++; openFolder(state.path, true); };
let searchTimer;
$("#filter-input").oninput = event => {
  clearTimeout(searchTimer);
  const query = event.target.value;
  searchTimer = setTimeout(() => { state.query = query; openFolder(state.path, false, false); }, 230);
};

pollStatus();
