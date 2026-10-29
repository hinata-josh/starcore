// 怪獸來襲完整流程實跑:模擬器裡跑「全部」伺服器腳本 + client 腳本(模擬時鐘,第一波改成 35 秒後)。
// 驗:降落點跟著砲台走、預警紅圈、裂縫傳送門、怪獸模型降落、砲台光束、擊倒、觀戰傳送、開戰前 3 秒自動傳送/取消。
// 用法:node test/wave-check.js
const H = require('./ui-harness');

if (!H.available) {
  console.log('略過:找不到 Roblox 模擬器 roblox.js');
  process.exit(0);
}

let pass = 0, fail = 0;
const check = (name, cond, extra) => {
  if (cond) pass++;
  else { fail++; console.log('  ✗ ' + name + (extra !== undefined ? ':' + extra : '')); }
};

const PATCH = { WaveLogic: (s) => s.replace('WaveLogic.FIRST_WAVE_DELAY = 300', 'WaveLogic.FIRST_WAVE_DELAY = 35') };

// client:北極附近蓋兩座砲台,赤道蓋兩座太陽能板(供電);manual=true 時預警一開始就按「前往防守現場」
const client = (manual) => `
local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS.Shared.Net.Remotes)
local player = game:GetService("Players").LocalPlayer
task.wait(3)
local place = Remotes.get("PlaceBuilding")
for _, b in { { "3_5_5", "PulseTurret" }, { "3_6_5", "PulseTurret" }, { "1_5_5", "SolarPanel" }, { "1_6_5", "SolarPanel" } } do
	place:FireServer(b[1], b[2])
	task.wait(0.4)
end
repeat task.wait(0.5) until workspace:GetAttribute("RiftActive")
local d = workspace:GetAttribute("RiftDir")
print("RIFT_ACTIVE", d.Y)
${manual ? `Remotes.get("RequestWatch"):FireServer()
task.wait(1)
print("WATCH_TP", player:GetAttribute("TeleportSeq"), player:GetAttribute("TeleportLook") ~= nil)` : ''}
`;

function scenario(label, { manual, cancel }) {
  console.log('▶ ' + label);
  const seen = { zone: false, portal: false, monsters: 0, monsterParts: 0, beams: 0, autoPanel: false, cancelled: false };
  const r = H.runClient({
    serverScripts: true, simClock: true, patch: PATCH, clientSource: client(manual), seconds: 95, dt: 1 / 20,
    onTick: (rt, t) => {
      const ws = rt.workspace;
      if (ws.findChild('RiftZone')) seen.zone = true;
      const wm = ws.findChild('WaveMonsters');
      if (wm) {
        if (wm.findChild('RiftPortal')) seen.portal = true;
        const mons = wm.children.filter((c) => c.ClassName === 'Model' && c.p.Name !== 'RiftPortal');
        seen.monsters = Math.max(seen.monsters, mons.length);
        for (const m of mons) seen.monsterParts = Math.max(seen.monsterParts, m.descendants().filter((d) => d.ClassName === 'Part').length);
        // 光束:WaveMonsters 底下細長的 Neon 方塊
        seen.beams = Math.max(seen.beams, wm.children.filter((c) => c.ClassName === 'Part' && c.p.Size.Z > 5 && c.p.Size.X < 1).length);
      }
      // 自動傳送倒數框
      const hud = rt.localPlayer.findChild('PlayerGui') && rt.localPlayer.findChild('PlayerGui').findChild('HudExtras');
      if (hud) {
        // 從「取消傳送」按鈕往上找倒數框(介面都在 Root 底下,不能只看 ScreenGui 的直接子物件)
        const label = hud.descendants().find((d) => d.ClassName === 'TextLabel' && d.p.Text === '取消傳送');
        const btn = label && label.parent; // 按鈕
        const panel = btn && btn.parent; // 倒數框
        if (panel && panel.p.Visible) {
          seen.autoPanel = true;
          if (cancel && !seen.cancelled) {
            btn.fire('Activated', []);
            seen.cancelled = true;
          }
        }
      }
    },
  });
  const log = r.prints.join('\n');
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 4).join(' | '));
  check('預警開始(RiftActive)', /RIFT_ACTIVE/.test(log));
  const y = Number((/RIFT_ACTIVE\s+(-?[\d.]+)/.exec(log) || [])[1]);
  check('降落點在砲台那群(北極,Y > 0.9)', y > 0.9, y);
  check('預警時地面出現紅色降落區', seen.zone);
  check('開戰:裂縫傳送門', seen.portal);
  check('開戰:怪獸出現', seen.monsters >= 1, seen.monsters);
  check('怪獸是多零件模型(≥ 10 個零件)', seen.monsterParts >= 10, seen.monsterParts);
  check('砲台有射出光束', seen.beams >= 1, seen.beams);
  check('伺服器記錄降落點來源 defense', /降落點 3_\d+_\d+.defense/.test(log), (log.match(/降落點[^\n]*/) || [''])[0]);
  check('戰鬥結束:怪獸與傳送門清掉', !r.rt.workspace.findChild('WaveMonsters'));
  check('戰鬥結束:降落區清掉', !r.rt.workspace.findChild('RiftZone'));
  check('戰鬥結束:RiftActive 關閉', !(r.rt.workspace.attrs && r.rt.workspace.attrs.get('RiftActive')));
  return { r, seen, log };
}

{
  const { seen, log } = scenario('① 預警時手動按「前往防守現場」', { manual: true });
  check('手動傳送成功(TeleportSeq 有值、有指定朝向)', /WATCH_TP\s+1\s+true/.test(log), (log.match(/WATCH_TP[^\n]*/) || [''])[0]);
  check('人已在降落區附近 → 不跳自動倒數', !seen.autoPanel);
}
{
  const { seen, log } = scenario('② 沒按:開戰前 3 秒自動傳送', { manual: false });
  check('跳出自動倒數框', seen.autoPanel);
  check('伺服器通知自動倒數', /通知自動觀戰倒數/.test(log));
  check('倒數結束自動傳送', /觀戰傳送/.test(log));
}
{
  const { seen, log } = scenario('③ 按「取消傳送」', { manual: false, cancel: true });
  check('跳出自動倒數框並取消', seen.autoPanel && seen.cancelled);
  check('取消後沒有傳送', !/觀戰傳送/.test(log));
}

// ④ 新玩家開局有基地 + 砲台模型;重建星球後只剩基地(不改第一波時間 → 不在來襲中)
{
  console.log('▶ ④ 開局贈送 + 重建星球');
  const atStart = {};
  const r = H.runClient({
    serverScripts: true, simClock: true, seconds: 14, dt: 1 / 20,
    clientSource: `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
task.wait(3)
Remotes.get("PlaceBuilding"):FireServer("1_5_5", "SolarPanel")
task.wait(1)
print("BEFORE_REBUILD")
Remotes.get("RebuildPlanet"):FireServer()
task.wait(1)
print("AFTER_REBUILD")
`,
    onTick: (rt, t) => {
      const b = rt.workspace.findChild('Buildings');
      const ids = b ? b.children.map((m) => m.p.Name).sort().join(',') : '';
      if (t >= 2 && t < 2.5) atStart.ids = ids;
      if (/SolarPanel/.test(ids)) atStart.before = ids;
      atStart.last = ids;
    },
  });
  const log = r.prints.join('\n');
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 3).join(' | '));
  check('開局就有指揮中心 + 脈衝砲台 + 時空門模型', atStart.ids === 'CommandCenter,PulseTurret,WarpGate', atStart.ids);
  check('重建前多了太陽能板', /SolarPanel/.test(atStart.before || ''), atStart.before);
  check('伺服器執行重建', /重建星球:拆掉 2 座/.test(log), (log.match(/重建星球[^\n]*/) || [''])[0]);
  check('重建後只剩指揮中心 + 時空門', atStart.last === 'CommandCenter,WarpGate', atStart.last);
}

// ⑤ 主人穿梭(每人一趟的重構後):蓋時空門 → 穿梭 → 返航
{
  console.log('▶ ⑤ 主人用時空門穿梭');
  const r = H.runClient({
    serverScripts: true, simClock: true, seconds: 12, dt: 1 / 20,
    clientSource: `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
local player = game:GetService("Players").LocalPlayer
task.wait(3)
Remotes.get("PlaceBuilding"):FireServer("1_5_5", "WarpGate")
task.wait(1)
Remotes.get("RequestWarp"):FireServer()
task.wait(2)
print("IN_TRIP", player:GetAttribute("InTrip"), workspace:FindFirstChild("TripWorld") ~= nil)
Remotes.get("RequestReturn"):FireServer()
task.wait(1)
print("AFTER_RETURN", player:GetAttribute("InTrip"), workspace:FindFirstChild("TripWorld") ~= nil)
`,
  });
  const log = r.prints.join('\n');
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 3).join(' | '));
  check('主人穿梭成功(通道 0)', /跳躍到[^\n]*通道 0[^\n]*主人/.test(log), (log.match(/跳躍到[^\n]*/) || [''])[0]);
  check('穿梭中:InTrip + 星球存在', /IN_TRIP true true/.test(log), (log.match(/IN_TRIP[^\n]*/) || [''])[0]);
  check('返航:InTrip 清掉、星球銷毀', /AFTER_RETURN nil false/.test(log), (log.match(/AFTER_RETURN[^\n]*/) || [''])[0]);
}

// ⑥ 不是主人、也不是主人的好友 → 不能用時空門
{
  console.log('▶ ⑥ 陌生訪客不能用時空門');
  const r = H.runClient({
    serverScripts: true, simClock: true, seconds: 8, dt: 1 / 20,
    serverSource: `
task.wait(2.5)
workspace:SetAttribute("OwnerUserId", 424242) -- 假裝主人是別人(不在線上、也不是好友)
`,
    clientSource: `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
Remotes.get("Notice").OnClientEvent:Connect(function(t) print("NOTICE", t) end)
task.wait(4)
Remotes.get("RequestWarp"):FireServer()
task.wait(1)
print("STRANGER_TRIP", game:GetService("Players").LocalPlayer:GetAttribute("InTrip"))
`,
  });
  const log = r.prints.join('\n');
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 3).join(' | '));
  check('被擋下並提示', /只有星球主人和他的好友能使用時空門/.test(log));
  check('沒有進入穿梭', /STRANGER_TRIP nil/.test(log), (log.match(/STRANGER_TRIP[^\n]*/) || [''])[0]);
}

// ⑧ 蓋建築前確認:點格子 → 確認框;取消不蓋;確定才蓋;買不起只提示
{
  console.log('▶ ⑧ 蓋建築前確認框');
  const seen = {};
  const find = (rt, name) => {
    const pg = rt.localPlayer.findChild('PlayerGui');
    return pg && pg.descendants().find((d) => d.p.Name === name);
  };
  const built = (rt) => {
    const b = rt.workspace.findChild('Buildings');
    return b ? b.children.filter((m) => m.p.Name === 'SolarPanel').length : 0;
  };
  const r = H.runClient({
    serverScripts: true, simClock: true, seconds: 12, dt: 1 / 20,
    clientSource: `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
Remotes.get("Notice").OnClientEvent:Connect(function(t) print("NOTICE", t) end)
-- 模擬器不會排隊「listener 還沒接上前」的事件(Roblox 會)→ 先蓋一座礦機,讓伺服器重送背包狀態
task.wait(2)
Remotes.get("PlaceBuilding"):FireServer("4_5_5", "Miner")
`,
    onTick: (rt, t) => {
      const ask = find(rt, 'BuildConfirm');
      if (t === 4) find(rt, 'TestClickSlot').fire('Event', ['1_5_5']); // 預設選中的是太陽能板
      if (t === 5) {
        seen.askAfterClick = ask.p.Visible;
        seen.builtBeforeConfirm = built(rt);
        find(rt, 'CancelBuild').fire('Activated', []);
      }
      if (t === 6) {
        seen.askAfterCancel = ask.p.Visible;
        seen.builtAfterCancel = built(rt);
        find(rt, 'TestClickSlot').fire('Event', ['1_5_5']);
      }
      if (t === 7) find(rt, 'ConfirmBuild').fire('Activated', []);
      if (t === 8) {
        seen.builtAfterConfirm = built(rt);
        seen.askAfterConfirm = ask.p.Visible;
        // 選一張買不起的卡(星塵反應爐)再點格子 → 只提示、不跳框
        const pg = rt.localPlayer.findChild('PlayerGui').findChild('BuildUI');
        const card = pg.descendants().find((d) => d.ClassName === 'ImageButton' && d.descendants().some((x) => x.p.Text === '星塵反應爐'));
        card.fire('Activated', []);
      }
      if (t === 9) find(rt, 'TestClickSlot').fire('Event', ['1_7_5']);
      if (t === 10) seen.askForExpensive = ask.p.Visible;
    },
  });
  const log = r.prints.join('\n');
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 3).join(' | '));
  check('點格子:跳出確認框', seen.askAfterClick === true);
  check('確認前:還沒蓋', seen.builtBeforeConfirm === 0, seen.builtBeforeConfirm);
  check('按取消:框關掉、沒蓋', seen.askAfterCancel === false && seen.builtAfterCancel === 0);
  check('按確定:蓋好了', seen.builtAfterConfirm === 1, seen.builtAfterConfirm);
  check('蓋完框關掉', seen.askAfterConfirm === false);
  check('買不起:不跳確認框', seen.askForExpensive === false);
  check('買不起:有提示', /資源不夠蓋「星塵反應爐」/.test(r.rt.localPlayer.findChild('PlayerGui').findChild('BuildUI').descendants().map((d) => d.p.Text).join('|')));
}

// ⑦ 星球旅行:私人伺服器的主人判定、回家鍵、好友清單、拜訪限制
const TRAVEL_CLIENT = `
local Remotes = require(game:GetService("ReplicatedStorage").Shared.Net.Remotes)
local player = game:GetService("Players").LocalPlayer
Remotes.get("Notice").OnClientEvent:Connect(function(t) print("NOTICE", t) end)
Remotes.get("FriendList").OnClientEvent:Connect(function(l) print("FRIENDS", #l) end)
task.wait(4)
print("OWNER_IS_ME", workspace:GetAttribute("OwnerUserId") == player.UserId)
Remotes.get("RequestFriends"):FireServer()
task.wait(0.5)
Remotes.get("VisitFriend"):FireServer(987654)
task.wait(0.5)
Remotes.get("GoHome"):FireServer()
task.wait(0.5)
`;
const homeVisible = (rt) => {
  const gui = rt.localPlayer.findChild('PlayerGui') && rt.localPlayer.findChild('PlayerGui').findChild('TravelUI');
  const b = gui && gui.descendants().find((d) => d.ClassName === 'ImageButton' && d.p.Name === 'HomeButton');
  return b ? b.p.Visible : 'no-button';
};
{
  console.log('▶ ⑦a 在自己的私人星球');
  let uid;
  const r = H.runClient({ serverScripts: true, simClock: true, seconds: 6, dt: 1 / 20, clientSource: TRAVEL_CLIENT,
    privateServer: 'ps-mine', joinHomeOwner: 1, onTick: (rt) => { uid = rt.localPlayer.p.UserId; } });
  const log = r.prints.join('\n');
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 3).join(' | '));
  check('模擬器玩家 UserId 是 1(測試前提)', uid === 1, uid);
  check('記下這台是誰的星球', r.rt.workspace.attrs && r.rt.workspace.attrs.get('HomeOwnerId') === 1);
  check('自己的星球:我是主人', /OWNER_IS_ME true/.test(log));
  check('自己的星球:沒有回家鍵', homeVisible(r.rt) === false, homeVisible(r.rt));
  check('好友清單有回覆(模擬器 0 位)', /FRIENDS 0/.test(log));
  check('不是好友不能拜訪', /只能拜訪你的 Roblox 好友/.test(log));
  check('已在家:按回家提示', /你已經在自己的星球了/.test(log));
}
{
  console.log('▶ ⑦b 在別人的私人星球(主人不在)');
  const r = H.runClient({ serverScripts: true, simClock: true, seconds: 6, dt: 1 / 20, clientSource: TRAVEL_CLIENT,
    privateServer: 'ps-friend', joinHomeOwner: 424242 });
  const log = r.prints.join('\n');
  check('沒有執行期錯誤', r.errors.length === 0, r.errors.slice(0, 3).join(' | '));
  check('訪客先到不會變主人', /OWNER_IS_ME false/.test(log));
  check('提示主人還沒回來', /星球主人還沒回來/.test(log));
  check('顯示回家鍵', homeVisible(r.rt) === true, homeVisible(r.rt));
  check('Studio 按回家:提示不能傳送', /Studio 不能傳送/.test(log));
}

console.log('');
console.log(`通過 ${pass},失敗 ${fail}`);
process.exit(fail > 0 ? 1 : 0);
