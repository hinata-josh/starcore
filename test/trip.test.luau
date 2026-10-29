local Trip = require("Trip")
local PlanetGen = require("PlanetGen")
local Planets = require("Planets")
local Items = require("Items")
local Warp = require("Warp")

local planet = PlanetGen.generate(123, 1, Planets)

-- 資源點:總量守恆、不在北極、同 seed 一致
local nodes = Trip.spawnNodes(planet, 123, Warp)
local want, got = 0, 0
for _, r in planet.resources do want += r.amount end
for _, n in nodes do got += n.amount end
check("資源點總量 = 星球資源量", got, want)
local pole, unitOk = 0, 0
for _, n in nodes do
	if n.dir.y > 0.92 then pole += 1 end
	if math.abs(n.dir.x ^ 2 + n.dir.y ^ 2 + n.dir.z ^ 2 - 1) < 1e-9 then unitOk += 1 end
end
check("沒有資源點落在北極", pole, 0)
check("資源點方向為單位向量", unitOk, #nodes)
local nodes2 = Trip.spawnNodes(planet, 123, Warp)
check("同 seed 資源點數相同", #nodes2, #nodes)
check("同 seed 資源點位置相同", nodes2[1].dir.x, nodes[1].dir.x)

-- 大量 seed:每顆星球至少有 1 個資源點、每點 amount > 0
local allOk = true
for seed = 1, 500 do
	local p = PlanetGen.generate(seed, 1, Planets)
	local ns = Trip.spawnNodes(p, seed, Warp)
	if #ns < 1 then allOk = false end
	for _, n in ns do if n.amount <= 0 then allOk = false end end
end
check("500 個 seed 都有可採資源點", allOk, true)

-- 載重
local CAP1 = Warp.capacityByLevel[1]
check("Lv1 載重", Trip.capacity(1, Warp), CAP1)
check("Lv99 取最高級", Trip.capacity(99, Warp), Warp.capacityByLevel[#Warp.capacityByLevel])
check("Lv0 視為 Lv1", Trip.capacity(0, Warp), CAP1)

-- 倒數
local t = Trip.start(5, planet, 1000, 1, Warp)
check("剩餘時間", Trip.timeLeft(t, 1010), 200)
check("未到期", Trip.expired(t, 1209), false)
check("到期", Trip.expired(t, 1210), true)
check("剩餘時間不為負", Trip.timeLeft(t, 5000), 0)

-- 採集:每次最多 3 個
local g = Trip.start(5, planet, 0, 1, Warp)
local ok, n = Trip.gather(g, 1, Items, Warp)
check("採集成功", ok, true)
check("單次不超過設定上限", n <= Warp.gatherPerAction, true)
check("loot 增加", g.loot[g.nodes[1].id], n)
check("無效索引", select(2, Trip.gather(g, 9999, Items, Warp)), "BadNode")

-- 抽乾一個點 → Empty
local single = { seed = 1, planet = planet, startedAt = 0, expiresAt = 9, loot = {}, capacity = 30,
	nodes = { { id = "Ore", amount = 2, dir = { x = 1, y = 0, z = 0 } } } }
Trip.gather(single, 1, Items, Warp)
check("抽乾後 Empty", select(2, Trip.gather(single, 1, Items, Warp)), "Empty")

-- 過量上限:載重 30 × 1.5 = 45;Ore 重 1 → 最多撿 45
local big = { seed = 1, planet = planet, startedAt = 0, expiresAt = 9, loot = {}, capacity = 30,
	nodes = { { id = "Ore", amount = 1000, dir = { x = 1, y = 0, z = 0 } } } }
for i = 1, 100 do Trip.gather(big, 1, Items, Warp) end
check("撿到過量上限 45 停止", big.loot.Ore, 45)
check("滿了回 Full", select(2, Trip.gather(big, 1, Items, Warp)), "Full")
check("重量 = 45", Trip.weight(big, Items), 45)

-- 重物品:Crystal 重 2,上限 45 → 最多 22 個(22×2=44,再撿 1 個會 46 > 45)
local heavy = { seed = 1, planet = planet, startedAt = 0, expiresAt = 9, loot = {}, capacity = 30,
	nodes = { { id = "Crystal", amount = 1000, dir = { x = 1, y = 0, z = 0 } } } }
for i = 1, 100 do Trip.gather(heavy, 1, Items, Warp) end
check("重物品不超過過量上限", Trip.weight(heavy, Items) <= 45, true)
check("重物品撿到 22 個", heavy.loot.Crystal, 22)

-- 結算
check("自己返航 → 全帶回", Trip.settle(big, Items, Warp, false).Ore, 45)
-- 超時:重量 45、載重 30 → 保留重量 30 + 15×0.5 = 37.5 → 比例 0.8333 → floor(45×0.8333)=37
check("超時 → 超出部分只留一半", Trip.settle(big, Items, Warp, true).Ore, 37)
local under = { loot = { Ore = 20 }, capacity = 30 }
check("未超載即使超時也全帶回", Trip.settle(under, Items, Warp, true).Ore, 20)
local empty = { loot = {}, capacity = 30 }
local cnt = 0
for _ in Trip.settle(empty, Items, Warp, true) do cnt += 1 end
check("空背包結算為空", cnt, 0)
