// 介面測試共用:載入 Roblox 模擬器(roblox.js)+ 補模擬器缺的 API + 把 src/shared 掛成 ModuleScript 樹 + 跑 src/client。
// ui-check.js(自動檢查)與 ui-preview.js(產生預覽圖)共用。
const fs = require('fs');
const path = require('path');

const RBX_PATHS = [path.join(__dirname, '..', 'tools', 'roblox.js'), 'K:/Html5/roblox-studio/roblox.js'];
const rbxPath = RBX_PATHS.find((p) => fs.existsSync(p));
const R = rbxPath ? require(rbxPath) : null;
const L = rbxPath ? require(path.join(path.dirname(rbxPath), 'luau.js')) : null;
const SRC = path.join(__dirname, '..', 'src');

// ── 模擬器缺的 Roblox API(真的 Roblox 都有):只補「存得進去」,不模擬外觀 ──
// 補在建立 Runtime 之前(類別成員表第一次用到時才會攤平快取)
if (R) {
  const ANYP = { any: true, v: undefined };
  Object.assign(R.CLASSES.ImageLabel.props, { SliceCenter: ANYP, SliceScale: 1 });
  Object.assign(R.CLASSES.ScrollingFrame.props, { AutomaticCanvasSize: ANYP, ScrollingDirection: ANYP, ScrollBarImageColor3: ANYP });
  Object.assign(R.CLASSES.UIGridLayout.props, { HorizontalAlignment: ANYP, VerticalAlignment: ANYP });
  // 缺的類別:照 WeldConstraint 的結構補(只存屬性,不模擬物理)
  const addClass = (name, baseName, props) => {
    if (R.CLASSES[name]) {
      // 已有這個類別:只補缺的屬性
      for (const k in props) if (!(k in R.CLASSES[name].props)) R.CLASSES[name].props[k] = props[k];
      return;
    }
    R.CLASSES[name] = { name, base: R.CLASSES[baseName], props, methods: {}, events: [], virt: {}, readonly: [],
      notCreatable: false, service: false, init: undefined, onSet: undefined, valueChanged: false, all: null };
  };
  addClass('Weld', 'Instance', { Part0: ANYP, Part1: ANYP, C0: () => new R.CFrame(), C1: () => new R.CFrame(), Enabled: true });
  addClass('ParticleEmitter', 'Instance', { Color: ANYP, LightEmission: 0, Rate: 5, Lifetime: ANYP, Speed: ANYP, SpreadAngle: ANYP, Size: ANYP, Enabled: true, Texture: '' });
  Object.assign(R.CLASSES.BillboardGui.props, { StudsOffsetWorldSpace: ANYP });
  R.CLASSES.Animator.methods.GetPlayingAnimationTracks = L.nat("GetPlayingAnimationTracks", () => new L.LuaTable());
  // game.PrivateServerId("" = 公開伺服器);TeleportService(模擬器裡傳送一律失敗,只驗流程)
  Object.assign(R.CLASSES.DataModel.props, { PrivateServerId: "", PrivateServerOwnerId: 0 });
  addClass("TeleportService", "Instance", {});
  // Player:GetJoinData() → { TeleportData = { homeOwner = rt.joinHomeOwner } }(模擬「被傳送進私人伺服器」)
  R.CLASSES.Player.methods.GetJoinData = L.nat("GetJoinData", (a) => {
    const t = new L.LuaTable();
    const owner = a[0].rt.joinHomeOwner;
    if (owner !== undefined) { const td = new L.LuaTable(); td.set("homeOwner", owner); t.set("TeleportData", td); }
    return t;
  });
  R.CLASSES.TeleportService.service = true;
  const EnumType = Object.getPrototypeOf(R.ENUMS.PartType).constructor;
  const MISSING_ENUMS = { ScrollingDirection: ['X', 'Y', 'XY'], AssetFetchStatus: ['Success', 'Failure', 'None', 'Loading', 'TimedOut'], AnimationPriority: ['Core', 'Idle', 'Movement', 'Action'] };
  for (const [n, items] of Object.entries(MISSING_ENUMS)) if (!R.ENUMS[n]) R.ENUMS[n] = new EnumType(n, items);
  // ContentProvider:PreloadAsync(清單, 回呼) —— rt.preloadOk 決定圖片「載入成功」或「失敗(例如還在審核)」
  addClass('ContentProvider', 'Instance', {});
  R.CLASSES.ContentProvider.service = true;
  R.CLASSES.ContentProvider.methods.PreloadAsync = L.nat('PreloadAsync', (a, I) => {
    const list = a[1], cb = a[2];
    const status = R.ENUMS.AssetFetchStatus.items[a[0].rt.preloadOk ? 'Success' : 'Failure'];
    for (let i = 1; list && list.get(i) !== undefined; i++) {
      a[0].rt.preloadCount = (a[0].rt.preloadCount || 0) + 1;
      if (cb) I.callSync(cb, [list.get(i), status]);
    }
  });
}

// 模擬時鐘:os.time / os.clock / workspace:GetServerTimeNow 跟著模擬器的 rt.time 走(不然倒數要等真實時間)
const SIM_EPOCH = 1800000000;
// 類別方法表在第一次建 Runtime 時就攤平快取 → 要在模組載入時就換掉(依 rt.simClock 決定用哪個時間)
// 模擬器的方法是 nat 包裝過的(參數陣列 a,a[0] 是物件本身)
if (R) R.CLASSES.Workspace.methods.GetServerTimeNow = L.nat('GetServerTimeNow', (a) => (a[0].rt.simClock ? SIM_EPOCH + a[0].rt.time : Date.now() / 1000));
function installSimClock(rt) {
  rt.simClock = true;
  const os = rt.I.G.get('os');
  os.frozen = false;
  os.set('time', L.nat('time', () => Math.floor(SIM_EPOCH + rt.time)));
  os.set('clock', L.nat('clock', () => rt.time));
}

function installShims(rt) {
  // Rect.new(x0, y0, x1, y1) → { Min, Max }(只當資料存)
  const rect = new L.LuaTable();
  rect.set('new', L.nat('new', (a) => {
    const r = new L.LuaTable();
    r.set('Min', new R.Vector2(a[0] || 0, a[1] || 0));
    r.set('Max', new R.Vector2(a[2] || 0, a[3] || 0));
    return r;
  }));
  rt.I.G.set('Rect', rect);
}

// 把資料夾變成 Folder + ModuleScript 樹(.luau → ModuleScript,檔名去掉副檔名)
function mountModules(rt, dir, parent) {
  for (const f of fs.readdirSync(dir)) {
    const full = path.join(dir, f);
    if (fs.statSync(full).isDirectory()) {
      const folder = rt.new('Folder');
      folder.p.Name = f;
      folder.rawParent(parent);
      mountModules(rt, full, folder);
    } else if (f.endsWith('.luau')) {
      const m = rt.new('ModuleScript');
      m.p.Name = f.replace(/\.luau$/, '');
      m.source = fs.readFileSync(full, 'utf8');
      m.scriptId = 'm:' + full;
      m.rawParent(parent);
    }
  }
}

// 假的 UiAssets:assets/ui 每張圖一個假 ID(item_ 走 decal、其他走 image);回傳 { source, idToKey }
function fakeUiAssets() {
  const keys = fs.readdirSync(path.join(__dirname, '..', 'assets', 'ui')).filter((f) => f.endsWith('.png')).map((f) => f.replace(/\.png$/, ''));
  let id = 1000;
  const idToKey = {};
  const lines = keys.map((k) => {
    idToKey[id] = k;
    return `\t${k} = { id = ${id++}, kind = "${k.startsWith('item_') ? 'decal' : 'image'}" },`;
  });
  return { source: '--!strict\nreturn {\n' + lines.join('\n') + '\n}\n', idToKey };
}

// 建立模擬器、掛模組、跑假伺服器 + 所有 client 腳本 seconds 秒;回傳 { rt, pg, errors, prints }
// clients=false:不跑 client 腳本;serverModules=true:把 src/server 的 ModuleScript(非 .server)掛到 ServerScriptService.Server
// serverScripts=true:連 src/server 的 *.server.luau 也一起跑(完整伺服器);simClock=true:用模擬時鐘;
// patch = { 模組名: (原始碼) => 新原始碼 }(例:把第一波等待時間改短);clientSource:額外的 LocalScript;dt:每步秒數
function runClient({ uiAssetsSource, serverSource, seconds = 4, clients = true, serverModules = false, serverScripts = false,
  simClock = false, patch = {}, clientSource = null, dt = 1 / 60, onTick = null, preloadOk = false,
  privateServer = "", joinHomeOwner = undefined, viewport = null }) {
  const errors = [];
  const prints = [];
  const rt = new R.Runtime({ output: (k, t) => (k === 'error' ? errors : prints).push(t) });
  installShims(rt);
  if (simClock) installSimClock(rt);
  rt.preloadOk = preloadOk;
  rt.game.p.PrivateServerId = privateServer;
  rt.joinHomeOwner = joinHomeOwner;
  if (viewport) rt.camera.p.ViewportSize = new R.Vector2(viewport[0], viewport[1]); // 模擬小視窗
  const shared = rt.new('Folder');
  shared.p.Name = 'Shared';
  shared.rawParent(rt.game.findChild('ReplicatedStorage'));
  mountModules(rt, path.join(SRC, 'shared'), shared);
  if (uiAssetsSource) shared.findChild('Data').findChild('UiAssets').source = uiAssetsSource;
  if (serverModules || serverScripts) {
    const sf = rt.new('Folder');
    sf.p.Name = 'Server';
    sf.rawParent(rt.game.findChild('ServerScriptService'));
    for (const f of fs.readdirSync(path.join(SRC, 'server'))) {
      if (!f.endsWith('.luau')) continue;
      const isScript = f.includes('.server.');
      if (isScript && !serverScripts) continue;
      const m = rt.new(isScript ? 'Script' : 'ModuleScript');
      m.p.Name = f.replace(/(\.server)?\.luau$/, '');
      m.source = fs.readFileSync(path.join(SRC, 'server', f), 'utf8');
      m.scriptId = 's:' + f;
      m.rawParent(sf);
    }
  }
  // 依模組名改寫原始碼(只影響這次模擬)
  for (const inst of rt.game.descendants()) {
    if ((inst.ClassName === 'ModuleScript' || inst.ClassName === 'Script') && patch[inst.p.Name]) inst.source = patch[inst.p.Name](inst.source);
  }
  const scripts = serverSource ? [{ id: 'fake', name: 'FakeServer', type: 'Script', parent: 'ServerScriptService', source: serverSource }] : [];
  for (const f of clients ? fs.readdirSync(path.join(SRC, 'client')) : []) {
    scripts.push({ id: 'c:' + f, name: f.replace(/\.client\.luau$/, ''), type: 'LocalScript', parent: 'StarterPlayerScripts',
      source: fs.readFileSync(path.join(SRC, 'client', f), 'utf8') });
  }
  if (clientSource) scripts.push({ id: 'fakeClient', name: 'FakeClient', type: 'LocalScript', parent: 'StarterPlayerScripts', source: clientSource });
  rt.load(scripts);
  rt.start();
  const per = Math.max(1, Math.round(1 / dt));
  for (let i = 0; i < seconds / dt; i++) {
    rt.step(dt);
    if (onTick && i % per === 0) onTick(rt, i * dt);
  }
  return { rt, pg: rt.localPlayer.findChild('PlayerGui'), errors, prints };
}

module.exports = { R, L, available: !!R, runClient, fakeUiAssets };
