local MapView = require("MapView")
local HomeNode = require("HomeNode")
local Combat = require("Combat")
local WaveLogic = require("WaveLogic")
local HomePlanet = require("HomePlanet")
local CubeSphere = require("CubeSphere")
local Migrate = require("Migrate")
local Build = require("Build")
local Buildings = require("Buildings")
local Monsters = require("Monsters")
local Items = require("Items")
local PlanetLevels = require("PlanetLevels")

local N = 12

-- ── 2D 展開圖:864 格一一對應、不重疊、在範圍內 ──
local W, H = MapView.size(N)
check("地圖寬 = 4×12 + 3 間隙", W, 51)
check("地圖高 = 3×12 + 2 間隙", H, 38)
local seen, dup, oob = {}, 0, 0
for face = 1, 6 do
	for u = 0, N - 1 do
		for v = 0, N - 1 do
			local x, y = MapView.cellOf(face, u, v, N)
			if x < 0 or x >= W or y < 0 or y >= H then oob += 1 end
			local k = x .. "," .. y
			if seen[k] then dup += 1 end
			seen[k] = true
		end
	end
end
check("864 格都在地圖範圍內", oob, 0)
check("沒有兩格畫在同一個位置", dup, 0)

-- 六個面的十字位置不重疊
local faceSeen, faceDup = {}, 0
for face = 1, 6 do
	local ox, oy = MapView.faceOrigin(face, N)
	local k = ox .. "," .. oy
	if faceSeen[k] then faceDup += 1 end
	faceSeen[k] = true
end
check("六個面位置互不重疊", faceDup, 0)
local nx, ny = MapView.faceOrigin(3, N)
local fx, fy = MapView.faceOrigin(5, N)
check("北極在「前」的正上方", nx == fx and ny < fy, true)
local sx, sy = MapView.faceOrigin(4, N)
check("南極在「前」的正下方", sx == fx and sy > fy, true)

-- v 往上 → y 變小(地圖上方)
local _, yLow = MapView.cellOf(5, 0, 0, N)
local _, yHigh = MapView.cellOf(5, 0, N - 1, N)
check("v 越大畫得越上面", yHigh < yLow, true)

-- ── 建築格 ──
local d = Migrate.newPlayerData()
d.Inventory = { Ore = 500, Metal = 200 }
Build.place(d, "5_3_4", "Miner", Buildings)
Build.place(d, "5_4_4", "SolarPanel", Buildings)
Build.place(d, "1_0_0", "PulseTurret", Buildings)
local cells = MapView.cells(d.Planet.Slots, N, Buildings)
check("3 棟建築 → 3 個地圖格", #cells, 3)
local kinds = {}
for _, c in cells do kinds[c.id] = c.kind end
check("採集機 → collect", kinds.Miner, "collect")
check("太陽能板 → energy", kinds.SolarPanel, "energy")
check("砲台 → attack", kinds.PulseTurret, "attack")
local mx, my = MapView.cellOf(5, 3, 4, N)
local found = false
for _, c in cells do if c.id == "Miner" and c.x == mx and c.y == my then found = true end end
check("地圖格座標正確", found, true)
-- 存檔精簡格式(slotKey → id 字串)也能畫
local lite = MapView.cells({ ["5_3_4"] = "Miner" }, N, Buildings)
check("精簡格式(只有 id)可畫", #lite, 1)
check("壞掉的 key 被略過", #MapView.cells({ ["9_9_9"] = "Miner" }, N, Buildings), 0)

-- 裂縫降落點
local rx, ry = MapView.riftCell({ x = 1, y = 0.35, z = 0 }, N)
check("裂縫點在地圖內", rx >= 0 and rx < W and ry >= 0 and ry < H, true)
local rs = CubeSphere.fromDirection({ x = 1 / 1.0594, y = 0.35 / 1.0594, z = 0 }, N)
check("裂縫點落在右面(+X)", rs.face, 1)

-- ── 摘要 ──
local sum = MapView.summary(d.Planet, Buildings, PlanetLevels)
check("已蓋 3 / 容量 15", sum.used .. "/" .. sum.capacity, "3/15")
check("發電 4", sum.generation, 4)
check("耗電 = 採集機2 + 砲台3 = 5", sum.demand, 5)
check("滿足率 0.8", math.abs(sum.satisfaction - 0.8) < 1e-9, true)
check("火力 = 12 × 0.8", math.abs(sum.dps - 9.6) < 1e-9, true)
check("各類別計數", sum.byKind.attack == 1 and sum.byKind.energy == 1 and sum.byKind.collect == 1, true)
check("摘要星核血量", sum.coreHp, Combat.coreHp(1))

-- ── 戰況取樣(中央螢幕播放) ──
local def = Combat.defenseOf({ { id = "PulseTurret", lv = 1 } }, Buildings, 1)
local comp = WaveLogic.compose(1, 99, Monsters)
local res = Combat.simulate(def, comp, Monsters, comp.budget)
check("有戰況取樣", #res.samples >= 2, true)
check("第一筆是開戰前(全部存活)", res.samples[1].alive, res.total)
check("最後一筆時間 = 戰鬥結束", res.samples[#res.samples].t, res.duration)
local mono = true
for i = 2, #res.samples do
	if res.samples[i].t < res.samples[i - 1].t then mono = false end
	if res.samples[i].alive > res.samples[i - 1].alive then mono = false end
end
check("取樣時間遞增、存活數只減不增", mono, true)
check("取樣間隔約 2 秒", math.abs((res.samples[2].t - res.samples[1].t) - Combat.SAMPLE_EVERY) < 0.6, true)

-- ── 母星資源點(好友也能採) ──
local home = HomePlanet.generate(42, Items)
local nodes = HomeNode.layout(home, 42)
check("每種母星資源 2 個點 = 10 個", #nodes, 10)
local poleBad, idOk = 0, true
local want = {}
for _, id in home.Resources do want[id] = true end
for _, n in nodes do
	if n.dir.y > 0.9 then poleBad += 1 end
	if not want[n.id] then idOk = false end
end
check("資源點避開北極", poleBad, 0)
check("資源點只有母星自己的資源", idOk, true)
check("同 seed 位置固定", HomeNode.layout(home, 42)[1].dir.x, nodes[1].dir.x)
local n1 = nodes[1]
check("採集拿 25", HomeNode.harvest(n1, 25, 100), 25)
check("剩 15", n1.amount, HomeNode.AMOUNT - 25)
check("再採 25 只拿到剩下的 15", HomeNode.harvest(n1, 25, 101), 15)
check("採光後再採 = 0", HomeNode.harvest(n1, 25, 102), 0)
check("重生前仍是空的", HomeNode.refresh(n1, 101 + HomeNode.RESPAWN - 1), 0)
check("重生後恢復", HomeNode.refresh(n1, 101 + HomeNode.RESPAWN), HomeNode.AMOUNT)
check("重生後可再採", HomeNode.harvest(n1, 10, 101 + HomeNode.RESPAWN), 10)
