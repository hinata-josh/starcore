local Build = require("Build")
local Quest = require("Quest")
local Daily = require("Daily")
local Migrate = require("Migrate")
local Buildings = require("Buildings")
local Quests = require("Quests")
local Warp = require("Warp")

local function fresh() return Migrate.newPlayerData() end

-- 建築升級
local d = fresh()
d.Inventory = { Ore = 500, Metal = 100, Copper = 50, Titanium = 50, Crystal = 50 }
Build.place(d, "1_0_0", "PulseTurret", Buildings) -- 30/10
local turret = Build.find(Buildings, "PulseTurret")
check("升級花費 Lv1→2 基本料 = 原價×1.5", Build.upgradeCost(turret, 1, Buildings).Ore, 45)
check("升級花費 Lv1→2 要額外材料 銅", Build.upgradeCost(turret, 1, Buildings).Copper, 8)
check("升級花費 Lv2→3 = 原價×3", Build.upgradeCost(turret, 2, Buildings).Ore, 90)
check("升級花費 Lv2→3 換成更稀有材料(鈦)", Build.upgradeCost(turret, 2, Buildings).Titanium, 6)
check("Lv2→3 不再需要 Lv1→2 的銅", Build.upgradeCost(turret, 2, Buildings).Copper, nil)
check("升級成功", Build.upgrade(d, "1_0_0", Buildings), true)
check("升到 Lv2", d.Planet.Slots["1_0_0"].Lv, 2)
Build.upgrade(d, "1_0_0", Buildings)
check("升到 Lv3", d.Planet.Slots["1_0_0"].Lv, 3)
check("滿級回 MaxLevel", select(2, Build.upgrade(d, "1_0_0", Buildings)), "MaxLevel")
check("空格升級失敗", select(2, Build.upgrade(d, "2_0_0", Buildings)), "Empty")
local poor = fresh()
poor.Inventory = { Ore = 30, Metal = 10 }
Build.place(poor, "1_0_0", "PulseTurret", Buildings)
check("資源不足無法升級", select(2, Build.upgrade(poor, "1_0_0", Buildings)), "NoResources")

-- 時空門升級
local w = fresh()
w.Inventory = { Ore = 200, Metal = 100, Crystal = 50, Silicon = 50 }
check("沒門不能升科技", select(2, Build.upgradeWarp(w, Warp)), "NoGate")
Build.place(w, "1_0_0", "WarpGate", Buildings)
check("WarpLv 1→2", Build.upgradeWarp(w, Warp), true)
check("WarpLv=2", w.Tech.WarpLv, 2)
check("Lv3 需要冷門資源→不足", select(2, Build.upgradeWarp(w, Warp)), "NoResources")
w.Tech.WarpLv = 4
check("滿級", select(2, Build.upgradeWarp(w, Warp)), "MaxLevel")

-- 升級後產出變多(礦機 Lv2 = 2/秒)
local m = fresh()
m.Inventory = { Ore = 100, Metal = 100 }
Build.place(m, "1_0_0", "Miner", Buildings)
Build.place(m, "1_1_0", "SolarPanel", Buildings)
Build.upgrade(m, "1_0_0", Buildings)
local o0 = m.Inventory.Ore
Build.tick(m, 10, Buildings)
check("礦機 Lv2 十秒產 20", m.Inventory.Ore - o0, 20)

-- 離線收益
local off = fresh()
off.Inventory = { Ore = 100, Metal = 100 }
Build.place(off, "1_0_0", "Miner", Buildings)
Build.place(off, "1_1_0", "SolarPanel", Buildings)
off.LastSeen = 1000
local secs, gained = Build.offline(off, 1000 + 600, Buildings)
check("離線 600 秒", secs, 600)
check("離線產出 600(或補到存量上限)", gained, math.min(600, Build.STORAGE_PER_LEVEL - 65))
check("LastSeen 更新", off.LastSeen, 1600)
local s2, g2 = Build.offline(off, 1600 + 999999, Buildings)
check("離線最多算 2 小時", s2, 7200)
check("滿倉不超過存量上限", off.Inventory.Ore <= Build.STORAGE_PER_LEVEL, true)
check("全新存檔(LastSeen=0)不給離線收益", select(2, Build.offline(fresh(), 5000, Buildings)), 0)
check("時鐘倒退不給收益", select(1, Build.offline(off, 10, Buildings)), 0)

-- 任務
local q = fresh()
q.Inventory = { Ore = 0 }
local done = Quest.notify(q, "build", "Miner", Quests)
check("蓋礦機完成第 1 個任務", #done, 1)
check("任務獎勵入帳", q.Inventory.Ore, 20)
check("重複觸發不重複發獎", #Quest.notify(q, "build", "Miner", Quests), 0)
check("別的建築不算", #Quest.notify(q, "build", "Radar", Quests), 0)
check("目前任務前進到第 2 個", Quest.current(q, Quests).id, "q_solar")
Quest.notify(q, "trip", nil, Quests)
check("穿梭 q_trip1 完成", q.Quests.Done.q_trip1, true)
check("5 次穿梭任務累計(已有 1 次)", Quest.current(q, Quests).id, "q_solar")
for i = 1, 4 do Quest.notify(q, "trip", nil, Quests) end
check("累計 5 次完成 q_trip5", q.Quests.Done.q_trip5, true)
-- atLeast:打到第 10 波一次完成 wave1/5/10
local wv = Quest.notify(q, "waveWon", 10, Quests)
check("守住第 10 波一次完成 3 個波次任務", #wv, 3)
check("q_wave10 完成", q.Quests.Done.q_wave10, true)
check("所有任務 id 不重複", (function()
	local seen, ok = {}, true
	for _, def in Quests.Chain do if seen[def.id] then ok = false end seen[def.id] = true end
	return ok
end)(), true)

-- 每日獎勵
local dd = fresh()
dd.Inventory = {}
local streak, rew = Daily.claim(dd, 100)
check("第一天 streak=1", streak, 1)
check("第一天獎勵 Ore 40", dd.Inventory.Ore, 40)
check("同一天不能重領", Daily.claim(dd, 100), nil)
check("隔天連續 → streak 2", (Daily.claim(dd, 101)), 2)
check("斷一天重算 streak=1", (Daily.claim(dd, 105)), 1)
for day = 106, 111 do Daily.claim(dd, day) end
check("連續第 7 天", dd.Daily.Streak, 7)
check("第 8 天循環回第 1 天獎勵", select(2, Daily.available(dd, 112)).Ore, 40)
check("available 不改動資料", dd.Daily.LastDay, 111)

-- 舊存檔(v2)遷移後有新欄位
local v2 = { Version = 2, Inventory = {}, Friends = {} }
Migrate.run(v2)
check("v2→v3 有 Stats", v2.Stats ~= nil and v2.Quests ~= nil and v2.Daily ~= nil, true)

-- 選做任務(好友星球採集):不擋主線、單獨顯示、完成發獎勵
local fq = { Quests = { Done = {}, Claimed = {} }, Inventory = {} }
check("選做任務不在主線", Quest.current(fq, Quests).id, "q_miner")
check("選做任務單獨顯示", Quest.side(fq, Quests) and Quest.side(fq, Quests).id, "q_friend")
Quest.notify(fq, "build", "Miner", Quests)
Quest.notify(fq, "build", "SolarPanel", Quests)
check("沒做選做任務,主線照樣前進", Quest.current(fq, Quests).id, "q_trip1")
local fin = Quest.notify(fq, "friendGather", nil, Quests)
check("好友星球採集完成選做任務", fq.Quests.Done.q_friend, true)
check("選做任務發獎勵", fq.Inventory.Metal, 10)
check("回傳完成清單", fin[1] and fin[1].id, "q_friend")
check("選做任務做完就不顯示", Quest.side(fq, Quests), nil)
