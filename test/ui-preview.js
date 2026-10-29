// 介面預覽圖:在 Roblox 模擬器跑真的 src/client,把 PlayerGui 的介面樹排版成 HTML,
// 圖片網址換回本機 assets/ui/*.png(= 上傳後在遊戲裡會看到的樣子),再用無頭 Chrome 截圖。
// 用法:node test/ui-preview.js [sprites|fallback|trip] ...   → build/ui-preview-<模式>.png
// 只是「近似」:排版規則照 Roblox(UDim2/AnchorPoint/UIListLayout/UIGridLayout/UIPadding/AutomaticSize),
// 字型與 TextScaled 是估的;ImageColor3 用 CSS 濾鏡近似。
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const H = require('./ui-harness');

const ROOT = path.join(__dirname, '..');
const OUT = path.join(ROOT, 'build');
let W = 1280, H_ = 720; // 預覽視窗大小(可用「模式@寬x高」指定,例 sprites@942x592)
const INSET = 58; // Roblox 頂端工具列高度(ScreenGui 預設不蓋到這裡)

const SCENES = {
  // 母星:資源、任務、裂縫倒數、提示訊息
  home: `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
task.wait(0.3)
local p = game:GetService("Players"):GetPlayers()[1]
workspace:SetAttribute("OwnerUserId", p.UserId) -- 建造面板只有主人看得到
Remotes.get("StateChanged"):FireAllClients({ Inventory = { Ore = 135, Metal = 15, Scrap = 20, Sand = 20, Water = 20, Coal = 20, Copper = 8, Crystal = 1234 }, Slots = {}, Level = 1, N = 12 })
Remotes.get("QuestChanged"):FireClient(p, { id = "q1", text = "蓋一座礦機,開始採礦", progress = 0, target = 1 })
Remotes.get("WaveInfo"):FireAllClients({ index = 1, nextAt = workspace:GetServerTimeNow() + 264, warnSec = 30, boss = false, scale = 1, preview = { { id = "Acid", name = "酸液蟲", count = 3 } } })
task.wait(1.5)
Remotes.get("Notice"):FireClient(p, "資源不夠")
`,
  // 怪獸來襲:預警中 + 開戰前 3 秒自動傳送倒數
  raid: `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
task.wait(0.3)
local p = game:GetService("Players"):GetPlayers()[1]
workspace:SetAttribute("OwnerUserId", p.UserId) -- 建造面板只有主人看得到
Remotes.get("StateChanged"):FireAllClients({ Inventory = { Ore = 95, Metal = 22, Scrap = 20 }, Slots = {}, Level = 1, N = 12 })
Remotes.get("QuestChanged"):FireClient(p, { id = "q3", text = "守住第一波裂縫", progress = 0, target = 1 })
Remotes.get("WaveInfo"):FireAllClients({ index = 1, nextAt = workspace:GetServerTimeNow() + 2.5, warnSec = 30, boss = false, scale = 1, preview = { { id = "AcidWorm", name = "酸液蟲", count = 3 } } })
workspace:SetAttribute("RiftDir", Vector3.new(0, 1, 0))
workspace:SetAttribute("RiftActive", true)
workspace:SetAttribute("RiftAutoWatchAt", workspace:GetServerTimeNow() + 2.5)
`,
  // 穿梭中 + 戰果橫幅
  trip: `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
task.wait(0.3)
local p = game:GetService("Players"):GetPlayers()[1]
workspace:SetAttribute("OwnerUserId", p.UserId) -- 建造面板只有主人看得到
Remotes.get("StateChanged"):FireAllClients({ Inventory = { Ore = 40, Metal = 5 }, Slots = {}, Level = 1, N = 12 })
Remotes.get("QuestChanged"):FireClient(p, { id = "q2", text = "穿梭到別的星球採集 3 次", progress = 1, target = 3 })
Remotes.get("WaveInfo"):FireAllClients({ index = 2, nextAt = workspace:GetServerTimeNow() + 18, warnSec = 30, boss = true, scale = 2, preview = { { id = "Acid", name = "酸液蟲", count = 4 }, { id = "Moth", name = "刃蛾", count = 2 } } })
Remotes.get("TripChanged"):FireClient(p, { expiresAt = workspace:GetServerTimeNow() + 95 })
Remotes.get("CargoChanged"):FireClient(p, { Ore = 12, Ice = 4, Crystal = 2 }, 22, 20)
Remotes.get("GatherState"):FireClient(p, { readyAt = workspace:GetServerTimeNow() + 7, interval = 120, cooling = { Ore = 30 } })
task.wait(0.5)
Remotes.get("WaveResult"):FireAllClients({ won = true, coreLeft = 80, coreMax = 100, reward = { Ore = 30, Crystal = 2 }, index = 1 })
`,
};

const hex = (c, a = 1) => (c ? `rgba(${Math.round(c.R * 255)},${Math.round(c.G * 255)},${Math.round(c.B * 255)},${a})` : 'transparent');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const ud = (u, size) => u.Scale * size + u.Offset;
const isGui = (n) => ['Frame', 'TextLabel', 'TextButton', 'ImageLabel', 'ImageButton', 'ScrollingFrame'].includes(n.ClassName);
const kid = (n, cls) => n.children.find((c) => c.ClassName === cls);
const enumName = (e) => (e && e.Name) || '';

function makeRenderer(idToKey) {
  const imgUrl = (img) => {
    const m = /id=?(\d+)/.exec(img) || /rbxassetid:\/\/(\d+)/.exec(img);
    const key = m && idToKey[m[1]];
    return key ? `../assets/ui/${key}.png` : null;
  };

  // 回傳這個節點底下所有子元件的 HTML;w/h 是本身的內容區大小
  function layoutChildren(n, w, h) {
    const pad = kid(n, 'UIPadding');
    const pl = pad ? ud(pad.p.PaddingLeft, w) : 0, pr = pad ? ud(pad.p.PaddingRight, w) : 0;
    const pt = pad ? ud(pad.p.PaddingTop, h) : 0, pb = pad ? ud(pad.p.PaddingBottom, h) : 0;
    const cw = w - pl - pr, ch = h - pt - pb;
    const kids = n.children.filter((c) => isGui(c) && c.p.Visible).sort((a, b) => a.p.LayoutOrder - b.p.LayoutOrder);
    const list = kid(n, 'UIListLayout'), grid = kid(n, 'UIGridLayout');
    const placed = [];
    if (grid) {
      const cs = grid.p.CellSize, cp = grid.p.CellPadding;
      const cwid = ud(cs.X, cw), chei = ud(cs.Y, ch), gx = ud(cp.X, cw), gy = ud(cp.Y, ch);
      const perRow = Math.max(1, Math.floor((cw + gx) / (cwid + gx)));
      const rows = Math.ceil(kids.length / perRow);
      kids.forEach((c, i) => {
        const r = Math.floor(i / perRow), col = i % perRow;
        const inRow = r === rows - 1 ? kids.length - r * perRow : perRow;
        const rowW = inRow * cwid + (inRow - 1) * gx;
        const x0 = enumName(grid.p.HorizontalAlignment) === 'Center' ? (cw - rowW) / 2 : 0;
        placed.push({ c, x: pl + x0 + col * (cwid + gx), y: pt + r * (chei + gy), w: cwid, h: chei });
      });
    } else if (list) {
      const horiz = enumName(list.p.FillDirection) === 'Horizontal';
      const gap = ud(list.p.Padding, horiz ? cw : ch);
      const sizes = kids.map((c) => ({ w: ud(c.p.Size.X, cw), h: ud(c.p.Size.Y, ch) }));
      const total = sizes.reduce((s, z) => s + (horiz ? z.w : z.h), 0) + gap * Math.max(0, kids.length - 1);
      let cur = horiz && enumName(list.p.HorizontalAlignment) === 'Center' ? (cw - total) / 2 : 0;
      kids.forEach((c, i) => {
        const z = sizes[i];
        const cross = horiz && enumName(list.p.VerticalAlignment) === 'Center' ? (ch - z.h) / 2 : 0;
        placed.push(horiz ? { c, x: pl + cur, y: pt + cross, w: z.w, h: z.h } : { c, x: pl, y: pt + cur, w: z.w, h: z.h });
        cur += (horiz ? z.w : z.h) + gap;
      });
    } else {
      for (const c of kids) {
        const sw = ud(c.p.Size.X, cw), sh = ud(c.p.Size.Y, ch);
        placed.push({ c, x: pl + ud(c.p.Position.X, cw) - c.p.AnchorPoint.X * sw, y: pt + ud(c.p.Position.Y, ch) - c.p.AnchorPoint.Y * sh, w: sw, h: sh });
      }
    }
    // AutomaticSize Y:依子元件撐高(資源列)
    let html = '', bottom = 0;
    for (const p of placed) {
      const r = render(p.c, p.x, p.y, p.w, p.h);
      html += r.html;
      bottom = Math.max(bottom, p.y + r.h);
    }
    return { html, autoH: bottom + pb };
  }

  function render(n, x, y, w, h) {
    // AutomaticSize:先排子元件再決定自己的高度
    let inner = layoutChildren(n, w, h);
    if (['Y', 'XY'].includes(enumName(n.p.AutomaticSize))) {
      h = Math.max(h, inner.autoH);
      inner = layoutChildren(n, w, h);
      if (n.p.AnchorPoint.Y) y -= n.p.AnchorPoint.Y * (h - 0);
    }
    const st = [`left:${x}px`, `top:${y}px`, `width:${w}px`, `height:${h}px`];
    const corner = kid(n, 'UICorner'), stroke = kid(n, 'UIStroke'), grad = kid(n, 'UIGradient'), tsc = kid(n, 'UITextSizeConstraint');
    if (n.p.BackgroundTransparency < 1) st.push(`background-color:${hex(n.p.BackgroundColor3, 1 - n.p.BackgroundTransparency)}`);
    if (grad && n.p.BackgroundTransparency < 1) st.push('background-image:linear-gradient(rgba(255,255,255,.18),rgba(0,0,0,.22))');
    if (corner) {
      const cr = corner.p.CornerRadius;
      // Roblox 的圓角最大只到短邊的一半(999 → 膠囊形,不是橢圓)
      const rad = Math.min(cr.Scale * Math.min(w, h) + cr.Offset, Math.min(w, h) / 2);
      st.push(`border-radius:${rad}px`);
    }
    if (stroke && stroke.p.Enabled) st.push(`box-shadow:0 0 0 ${stroke.p.Thickness}px ${hex(stroke.p.Color, 1 - stroke.p.Transparency)}`);
    if (n.ClassName === 'ScrollingFrame' || n.p.ClipsDescendants) st.push('overflow:hidden');
    // UIScale:以元件中心縮放(Skin.autoScale 的 Root 錨點在中心)
    const uisc = kid(n, 'UIScale');
    if (uisc && uisc.p.Scale !== 1 && n.p.Name === 'Root') st.push(`transform:scale(${uisc.p.Scale});transform-origin:50% 50%`);
    if (n.p.ZIndex > 1) st.push(`z-index:${n.p.ZIndex}`);
    let body = '';
    if ((n.ClassName === 'ImageLabel' || n.ClassName === 'ImageButton') && n.p.Image && n.p.ImageTransparency < 1) {
      const url = imgUrl(n.p.Image);
      const tint = n.p.ImageColor3;
      const tinted = tint && (tint.R < 0.99 || tint.G < 0.99 || tint.B < 0.99);
      // ImageColor3(相乘染色)近似:灰階素材 → 依目標色調整色相/飽和
      const filt = tinted ? `filter:sepia(1) saturate(4) hue-rotate(${Math.round(hueOf(tint) - 40)}deg) brightness(.9);` : '';
      if (url && enumName(n.p.ScaleType) === 'Slice' && n.p.SliceCenter) {
        const mn = n.p.SliceCenter.get('Min'), mx = n.p.SliceCenter.get('Max');
        const sz = sizeOf(url);
        const s = n.p.SliceScale || 1;
        const t = mn.Y, l = mn.X, b = sz.h - mx.Y, r = sz.w - mx.X;
        body += `<div class="img" style="${filt}border-style:solid;border-width:${t * s}px ${r * s}px ${b * s}px ${l * s}px;border-image:url(${url}) ${t} ${r} ${b} ${l} fill"></div>`;
      } else if (url) {
        body += `<img class="img" style="${filt}object-fit:${enumName(n.p.ScaleType) === 'Fit' ? 'contain' : 'fill'}" src="${url}">`;
      } else {
        body += `<div class="img missing">?</div>`;
      }
    }
    if (n.ClassName === 'TextLabel' || n.ClassName === 'TextButton') {
      const text = String(n.p.Text);
      const max = tsc ? tsc.p.MaxTextSize : 100;
      const lines = text.split('\n');
      const longest = Math.max(1, ...lines.map((l) => [...l].reduce((s, ch) => s + (ch.charCodeAt(0) > 255 ? 1 : 0.55), 0)));
      const size = n.p.TextScaled ? Math.max(6, Math.min(max, (h / lines.length) * 0.9, (w / longest) * 0.98)) : n.p.TextSize;
      const align = { Left: 'flex-start', Right: 'flex-end' }[enumName(n.p.TextXAlignment)] || 'center';
      const strokeA = 1 - n.p.TextStrokeTransparency;
      const shadow = strokeA > 0 ? `text-shadow:${[-1, 1].flatMap((a) => [-1, 1].map((b) => `${a}px ${b}px 0 ${hex(n.p.TextStrokeColor3, strokeA)}`)).join(',')};` : '';
      // N1 字型(Noto Sans Condensed Bold)當預覽字型;Roblox 實機中文會用內建的 Noto/思源黑體
      const font = "'N1Font','Microsoft JhengHei'";
      body += `<div class="txt" style="justify-content:${align};text-align:${align === 'center' ? 'center' : 'left'};font-size:${size.toFixed(1)}px;font-family:${font};color:${hex(n.p.TextColor3, 1 - n.p.TextTransparency)};${shadow}white-space:${n.p.TextWrapped || n.p.TextScaled ? 'pre-wrap' : 'pre'}">${esc(text)}</div>`;
    }
    return { html: `<div class="g" style="${st.join(';')}">${body}${inner.html}</div>`, h };
  }
  return render;
}

const sizeCache = {};
function sizeOf(url) {
  if (sizeCache[url]) return sizeCache[url];
  const b = fs.readFileSync(path.join(OUT, url));
  return (sizeCache[url] = { w: b.readUInt32BE(16), h: b.readUInt32BE(20) });
}
function hueOf(c) {
  const mx = Math.max(c.R, c.G, c.B), mn = Math.min(c.R, c.G, c.B), d = mx - mn;
  if (!d) return 0;
  let h = mx === c.R ? ((c.G - c.B) / d) % 6 : mx === c.G ? (c.B - c.R) / d + 2 : (c.R - c.G) / d + 4;
  return (h * 60 + 360) % 360;
}

function preview(modeArg) {
  const [mode, size] = modeArg.split('@');
  if (size) [W, H_] = size.split('x').map(Number); else [W, H_] = [1280, 720];
  const useSprites = mode !== 'fallback';
  const fake = H.fakeUiAssets();
  const r = H.runClient({ uiAssetsSource: useSprites ? fake.source : null, serverSource: SCENES[SCENES[mode] ? mode : 'home'], seconds: 2.2, preloadOk: useSprites, viewport: [W, H_ - INSET] });
  if (r.errors.length) console.log('  ! 執行期錯誤:' + r.errors.slice(0, 3).join(' | '));
  const render = makeRenderer(fake.idToKey);
  const guis = r.pg.children.filter((g) => g.ClassName === 'ScreenGui').sort((a, b) => a.p.DisplayOrder - b.p.DisplayOrder);
  let html = '';
  for (const g of guis) html += render(g, 0, INSET, W, H_ - INSET).html.replace(/^<div class="g" style="[^"]*"/, `<div class="g" style="left:0;top:${INSET}px;width:${W}px;height:${H_ - INSET}px"`);
  const n1Font = 'K:/N1Project/N1-Pro/Client/Assets/design/ui/font/font01.ttf';
  const page = `<!doctype html><meta charset="utf-8"><style>
${fs.existsSync(n1Font) ? `@font-face{font-family:'N1Font';src:url('file:///${n1Font}')}` : ''}
body{margin:0;width:${W}px;height:${H_}px;overflow:hidden;position:relative;font-family:'Microsoft JhengHei';
 background:radial-gradient(ellipse 140% 70% at 50% 120%,#2f9e5a 0 55%,#55c46f 56%,transparent 57%),linear-gradient(#8fc7f2,#d7ecfb 70%)}
.topbar{position:absolute;left:0;top:0;width:${W}px;height:${INSET}px;background:rgba(0,0,0,.25)}
.g{position:absolute;box-sizing:border-box}
.img{position:absolute;left:0;top:0;width:100%;height:100%;box-sizing:border-box}
.missing{background:#f0f;color:#fff;font:bold 12px sans-serif;display:flex;align-items:center;justify-content:center}
.txt{position:absolute;inset:0;display:flex;align-items:center;line-height:1.05;font-weight:bold;overflow:visible}
</style><div class="topbar"></div>${html}`;
  fs.mkdirSync(OUT, { recursive: true });
  const tag = mode + (size ? '-' + size : '');
  const htmlPath = path.join(OUT, `ui-preview-${tag}.html`);
  fs.writeFileSync(htmlPath, page);
  const png = path.join(OUT, `ui-preview-${tag}.png`);
  const chrome = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
  execFileSync(chrome, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files', '--force-device-scale-factor=1',
    `--window-size=${W},${H_}`, `--screenshot=${png}`, 'file:///' + htmlPath.replace(/\\/g, '/')], { stdio: 'ignore' });
  console.log(`[ui-preview] ${tag} → ${png}`);
}

const modes = process.argv.slice(2);
for (const m of modes.length ? modes : ['sprites', 'fallback', 'trip']) preview(m);
