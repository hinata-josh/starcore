// 介面實跑檢查:用 Roblox 模擬器(tools/roblox.js,來自 K:\Html5\roblox-studio)真的執行 src/client 的 LocalScript,
// 由假伺服器腳本送出各種事件(資源、提示、任務、裂縫、戰果、穿梭),抓執行期錯誤並檢查介面樹。
// 跑兩輪:① 沒上傳圖片(備用樣式)② 假的 UiAssets(素材 + 九宮格路徑)。
// 用法:node test/ui-check.js
const H = require('./ui-harness');

if (!H.available) {
  console.log('略過:找不到 Roblox 模擬器 roblox.js(tools/ 或 K:\\Html5\\roblox-studio)');
  process.exit(0);
}

let pass = 0, fail = 0;
const check = (name, cond, extra) => {
  if (cond) pass++;
  else { fail++; console.log('  ✗ ' + name + (extra ? ':' + extra : '')); }
};

// 假伺服器:依序送出介面會收到的事件
const FAKE_SERVER = `
local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS.Shared.Net.Remotes)
task.wait(0.5)
local p = game:GetService("Players"):GetPlayers()[1]
workspace:SetAttribute("OwnerUserId", p.UserId)
Remotes.get("StateChanged"):FireAllClients({ Inventory = { Ore = 135, Metal = 15, Scrap = 20, Sand = 20, Water = 20, Coal = 20, Crystal = 1234 }, Slots = {}, Level = 1, N = 12 })
Remotes.get("Notice"):FireClient(p, "資源不夠")
Remotes.get("QuestChanged"):FireClient(p, { id = "q1", text = "蓋一座礦機,開始採礦", progress = 0, target = 1 })
Remotes.get("WaveInfo"):FireAllClients({ index = 1, nextAt = workspace:GetServerTimeNow() + 20, warnSec = 30, boss = true, scale = 2, preview = { { id = "Acid", name = "酸液蟲", count = 3 } } })
task.wait(0.3)
Remotes.get("WaveResult"):FireAllClients({ won = true, coreLeft = 80, coreMax = 100, reward = { Ore = 30, Crystal = 2 }, index = 1 })
Remotes.get("TripChanged"):FireClient(p, { expiresAt = workspace:GetServerTimeNow() + 90 })
Remotes.get("CargoChanged"):FireClient(p, { Ore = 12, Ice = 4 }, 20, 15)
Remotes.get("GatherState"):FireClient(p, { readyAt = workspace:GetServerTimeNow() + 5, interval = 120, cooling = { Ore = 30 } })
Remotes.get("ScreenFeed"):FireClient(p, { kind = "danger", text = "怪獸從裂縫降落", t = 0 })
task.wait(0.3)
Remotes.get("WaveResult"):FireAllClients({ won = false, killed = 2, total = 5, index = 2 })
Remotes.get("TripChanged"):FireClient(p, nil)
task.wait(0.2)
print("UPGRADE_BEFORE", #game:GetService("Players"):GetPlayers())
-- 材料夠升時空門 Lv2(金屬30 晶體15 矽10)→ 升級鈕要出現
Remotes.get("StateChanged"):FireAllClients({ Inventory = { Ore = 135, Metal = 50, Scrap = 20, Sand = 20, Water = 20, Coal = 20, Crystal = 1234, Silicon = 10 }, WarpLv = 1 })
print("FAKE_SERVER_DONE")
`;

function runRound(label, uiAssetsSource, preloadOk = false) {
  console.log('▶ ' + label);
  const r = H.runClient({ uiAssetsSource, serverSource: FAKE_SERVER, preloadOk });
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 5).join(' | '));
  check('假伺服器跑完', r.prints.some((t) => t.includes('FAKE_SERVER_DONE')));
  const guis = r.pg ? r.pg.children.map((c) => c.p.Name) : [];
  for (const g of ['BuildUI', 'HudExtras', 'TripUI', 'CentralScreen']) check('有 ' + g, guis.includes(g), guis.join(','));
  check('走路動畫載入成功', r.prints.some((t) => t.includes('走路動畫就緒')), r.prints.filter((t) => t.includes('走路動畫')).join(' | '));
  return r;
}

const all = (inst) => [inst, ...inst.descendants()];

// ── 第一輪:沒有上傳圖片 ──
{
  const { pg, rt } = runRound('① 備用樣式(沒上傳圖片)', null);
  const settle = () => { for (let i = 0; i < 5; i++) rt.step(1 / 60); }; // 事件處理在下一步才執行
  const build = pg && pg.findChild('BuildUI');
  if (build) {
    const nodes = all(build);
    const cards = nodes.filter((n) => n.ClassName === 'ImageButton' && n.parent && n.parent.ClassName === 'ScrollingFrame');
    check('50 張建築卡', cards.length === 50, String(cards.length));
    const visible = cards.filter((c) => c.p.Visible);
    check('預設只顯示能源類(9 張)', visible.length === 9, String(visible.length));
    const glows = nodes.filter((n) => n.p.Name === 'SelectGlow' && n.p.Visible);
    check('只有 1 張卡是選中', glows.length === 1, String(glows.length));
    // 紅點:材料夠的卡片才亮(背包 礦石135 金屬15 → 太陽能板 礦15金5 夠、風力發電機 要銅 不夠)
    const cardByName = (name) => cards.find((c) => c.descendants().some((d) => d.ClassName === 'TextLabel' && d.p.Text === name));
    const badgeOf = (inst) => inst && inst.children.find((c) => c.p.Name === 'Badge');
    check('買得起:太陽能板有紅點', badgeOf(cardByName('太陽能板')) && badgeOf(cardByName('太陽能板')).p.Visible === true);
    check('買不起:風力發電機沒紅點', badgeOf(cardByName('風力發電機')) && badgeOf(cardByName('風力發電機')).p.Visible === false);
    check('紅點數 = 沒變暗的卡片數', cards.filter((c) => badgeOf(c).p.Visible).length === cards.filter((c) => !c.children.some((d) => d.ClassName === 'Frame' && d.p.ZIndex === 2 && d.p.Visible)).length);
    const tabOf = (name) => nodes.find((n) => n.ClassName === 'ImageButton' && n.parent && n.parent.ClassName === 'Frame' && n.children.some((d) => d.ClassName === 'TextLabel' && d.p.Text === name));
    check('能源分頁有紅點(太陽能板買得起)', badgeOf(tabOf('能源')) && badgeOf(tabOf('能源')).p.Visible === true);
    const texts = nodes.filter((n) => n.ClassName === 'TextLabel').map((n) => n.p.Text);
    check('資源列顯示 1.2k(能量晶體 1234)', texts.includes('1.2k'));
    check('資源列顯示 135(礦石)', texts.includes('135'));
    check('提示訊息顯示', texts.includes('資源不夠'));
    const imgs = nodes.filter((n) => (n.ClassName === 'ImageLabel' || n.ClassName === 'ImageButton') && n.p.Image);
    check('備用樣式不引用任何圖片', imgs.length === 0, String(imgs.length));
    // 切換到「攻擊」分頁
    const tabs = nodes.filter((n) => n.ClassName === 'ImageButton' && n.parent && n.parent.ClassName === 'Frame' && n.parent.parent && n.parent.parent.p.Name !== 'BuildUI' && n.descendants().some((d) => d.ClassName === 'TextLabel' && d.p.Text === '攻擊'));
    check('找到攻擊分頁', tabs.length === 1);
    // 建造面板收合 / 展開
    const collapse = nodes.find((n) => n.p.Name === 'CollapseButton');
    const buildBtn = nodes.find((n) => n.p.Name === 'BuildButton');
    const dock = collapse && collapse.parent;
    check('主人:建造面板預設展開', dock && dock.p.Visible === true && buildBtn.p.Visible === false);
    if (collapse && buildBtn) {
      collapse.fire('Activated', []);
      settle();
      check('按 ▼ 收起:面板隱藏、出現建造鈕', dock.p.Visible === false && buildBtn.p.Visible === true);
      buildBtn.fire('Activated', []);
      settle();
      check('按建造鈕:面板展開', dock.p.Visible === true && buildBtn.p.Visible === false);
    }
    if (tabs.length === 1) {
      tabs[0].fire('Activated', []);
      settle();
      const atk = cards.filter((c) => c.p.Visible);
      check('切到攻擊分頁:只顯示 14 張攻擊卡', atk.length === 14, String(atk.length));
    }
  }
  const hud = pg && pg.findChild('HudExtras');
  if (hud) {
    const up = all(hud).find((n) => n.ClassName === 'ImageButton' && n.descendants().some((d) => String(d.p.Text).startsWith('⬆ 時空門')));
    check('材料夠:升級時空門鈕出現', up && up.p.Visible === true);
    check('升級鈕寫目標等級 Lv2', up && up.descendants().some((d) => d.p.Text === '⬆ 時空門 Lv2'));
    check('升級鈕有紅點', up && up.children.some((c) => c.p.Name === 'Badge' && c.p.Visible));
    const texts = all(hud).filter((n) => n.ClassName === 'TextLabel').map((n) => n.p.Text);
    check('任務文字', texts.some((t) => t.includes('蓋一座礦機')));
    check('裂縫倒數有首領', texts.some((t) => t.includes('首領') && t.includes('裂縫')));
    check('戰敗橫幅', texts.some((t) => t.includes('第 2 波失守')));
  }
  const trip = pg && pg.findChild('TripUI');
  if (trip) {
    const texts = all(trip).filter((n) => n.ClassName === 'TextLabel').map((n) => n.p.Text);
    check('穿梭載重顯示超載', texts.some((t) => t.includes('載重 20/15') && t.includes('超載')));
    const ret = all(trip).find((n) => n.ClassName === 'ImageButton' && n.descendants().some((d) => d.p.Text === '返航'));
    check('返航後返航鈕隱藏', ret && ret.p.Visible === false);
  }
}

// ── 第二輪:圖片已上傳但「還不能載入」(審核中/被拒)→ 一定要維持備用樣式,不能變透明 ──
{
  const { pg, rt } = runRound('② 已上傳、還在審核(載入失敗)', H.fakeUiAssets().source, false);
  const nodes = pg ? all(pg) : [];
  const imgs = nodes.filter((n) => (n.ClassName === 'ImageLabel' || n.ClassName === 'ImageButton') && n.p.Image);
  check('有檢查圖片能不能載入', (rt.preloadCount || 0) > 0, rt.preloadCount);
  check('有引用圖片', imgs.length > 50, String(imgs.length));
  check('按鈕走九宮格', imgs.some((n) => n.ClassName === 'ImageButton' && n.p.ScaleType && n.p.ScaleType.Name === 'Slice'));
  check('資源圖示(decal)不走九宮格', imgs.filter((n) => String(n.p.Image).startsWith('rbxthumb://')).every((n) => n.p.ScaleType.Name === 'Fit'));
  check('資源圖示用縮圖網址(decal)', imgs.some((n) => String(n.p.Image).startsWith('rbxthumb://type=Asset&id=')));
  check('建築卡用 rbxassetid', imgs.some((n) => /^rbxassetid:\/\/\d+$/.test(String(n.p.Image))));
  check('紫色按鈕用灰色素材染色', imgs.some((n) => n.ClassName === 'ImageButton' && n.descendants().some((d) => String(d.p.Text).startsWith('⬆ 時空門')) && n.p.ImageColor3 && n.p.ImageColor3.R < 0.7));
  check('沒載入的圖全部隱形', imgs.every((n) => n.p.ImageTransparency === 1), imgs.filter((n) => n.p.ImageTransparency !== 1).length);
  check('沒載入的元件都還有色塊底(不會變透明)', imgs.every((n) => n.p.BackgroundTransparency < 1), imgs.filter((n) => n.p.BackgroundTransparency >= 1).map((n) => n.p.Name).slice(0, 3).join(','));
}

// ── 第三輪:圖片載入成功 → 換成素材、收掉備用樣式 ──
{
  const { pg } = runRound('③ 圖片載入成功', H.fakeUiAssets().source, true);
  const nodes = pg ? all(pg) : [];
  const imgs = nodes.filter((n) => (n.ClassName === 'ImageLabel' || n.ClassName === 'ImageButton') && n.p.Image);
  check('圖片全部顯示', imgs.length > 50 && imgs.every((n) => n.p.ImageTransparency === 0), imgs.filter((n) => n.p.ImageTransparency !== 0).length);
  check('備用色塊收掉', imgs.every((n) => n.p.BackgroundTransparency === 1), imgs.filter((n) => n.p.BackgroundTransparency !== 1).length);
  check('備用圓角移除(不裁素材)', imgs.every((n) => !n.children.some((c) => c.ClassName === 'UICorner')));
  check('圖示上的備用文字隱藏', nodes.filter((n) => n.p.Name === 'FallbackText').every((n) => !n.p.Visible));
  const tabs = imgs.filter((n) => n.descendants().some((d) => d.ClassName === 'TextLabel' && ['能源', '攻擊'].includes(d.p.Text)));
  check('分頁按鈕也換成素材', tabs.length >= 2 && tabs.every((n) => n.p.ImageTransparency === 0));
}

console.log('');
console.log(`通過 ${pass},失敗 ${fail}`);
process.exit(fail > 0 ? 1 : 0);
