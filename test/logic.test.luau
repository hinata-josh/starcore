local Rng = require("Rng")
local PlanetGen = require("PlanetGen")
local WaveLogic = require("WaveLogic")
local Energy = require("Energy")
local Migrate = require("Migrate")
local Planets = require("Planets")
local Monsters = require("Monsters")
local Buildings = require("Buildings")
local Items = require("Items")

-- Rng 可重現
local a, b = Rng.new(42), Rng.new(42)
local same = 0
for i = 1, 100 do if Rng.next(a) == Rng.next(b) then same += 1 end end
check("Rng 同 seed 同序列", same, 100)
local r = Rng.new(7)
local inRange = 0
for i = 1, 1000 do local x = Rng.int(r, 3, 6) if x >= 3 and x <= 6 then inRange += 1 end end
check("Rng.int 範圍", inRange, 1000)

-- 資料表一致性:資源 id 都要在 Items 內;每種星球至少一種資源
local itemIds = {}
for _, it in Items.Types do itemIds[it.id] = true end
local badRef = 0
for _, p in Planets.Types do
	if #p.resources < 1 then badRef += 1 end
	for _, res in p.resources do if not itemIds[res.id] then badRef += 1 end end
end
for _, bd in Buildings.Types do
	for id in bd.cost do if not itemIds[id] then badRef += 1 end end
end
check("資料表引用無懸空 id、星球皆有資源", badRef, 0)

-- PlanetGen:確定性 + 每顆至少一種資源 + warpLevel 過濾
local detOk, resOk, filterOk = 0, 0, 0
local typeCount = {}
for seed = 1, 2000 do
	local p1 = PlanetGen.generate(seed, 4, Planets)
	local p2 = PlanetGen.generate(seed, 4, Planets)
	if p1.typeId == p2.typeId and p1.radius == p2.radius and p1.resources[1].amount == p2.resources[1].amount then detOk += 1 end
	if #p1.resources >= 1 and p1.resources[1].amount > 0 then resOk += 1 end
	typeCount[p1.typeId] = (typeCount[p1.typeId] or 0) + 1
	local low = PlanetGen.generate(seed, 1, Planets)
	for _, t in Planets.Types do
		if t.id == low.typeId and t.minWarp <= 1 then filterOk += 1 end
	end
end
check("PlanetGen 確定性", detOk, 2000)
check("每顆星球至少一種資源", resOk, 2000)
check("WarpLv1 只出入門星球", filterOk, 2000)
local kinds = 0
for _ in typeCount do kinds += 1 end
check("WarpLv4 全部星球類型都會出現", kinds, #Planets.Types)

-- WaveLogic
check("第1波強度=基礎值", WaveLogic.threat(1), WaveLogic.BASE_THREAT)
check("強度遞增", WaveLogic.threat(10) > WaveLogic.threat(9), true)
check("第5波是首領波", WaveLogic.isBoss(5, Monsters), true)
check("第4波不是首領波", WaveLogic.isBoss(4, Monsters), false)
local overBudget, boss, firstWaveOk = 0, 0, true
for n = 1, 30 do
	local c = WaveLogic.compose(n, 99, Monsters)
	if c.spent > c.budget + 1e-6 then overBudget += 1 end
	if c.bossId then boss += 1 end
end
check("組波不超出預算", overBudget, 0)
check("30 波內首領波 6 次", boss, 6)
local w1 = WaveLogic.compose(1, 99, Monsters)
check("第1波只有酸液蟲", w1.counts.AcidWorm ~= nil and w1.counts.Behemoth == nil, true)
local w1b = WaveLogic.compose(1, 99, Monsters)
check("組波確定性", w1.counts.AcidWorm, w1b.counts.AcidWorm)
check("倒數秒數落在 10~12 分", WaveLogic.countdownSeconds(30) <= 720 and WaveLogic.countdownSeconds(1) >= 600, true)

-- Energy
local bal = Energy.balance({ { id = "SolarPanel" }, { id = "PulseTurret" }, { id = "EnergyShield" } }, Buildings)
check("發電", bal.generation, 4)
check("耗電", bal.demand, 9)
check("滿足率 4/9", math.abs(bal.satisfaction - 4 / 9) < 1e-9, true)
local full = Energy.balance({ { id = "CrystalReactor" }, { id = "PulseTurret" } }, Buildings)
check("發電夠時滿足率=1", full.satisfaction, 1)
check("無耗電不除以0", Energy.balance({}, Buildings).satisfaction, 1)

-- Migrate
local old = { Version = 1, Inventory = { Ore = 5 } }
check("v1 遷移有變動", Migrate.run(old), true)
check("遷移後版本", old.Version, Migrate.CURRENT)
check("遷移補上 Friends", old.Friends ~= nil, true)
check("重跑不再變動", Migrate.run(old), false)
check("保留原資料", old.Inventory.Ore, 5)
local fresh = Migrate.newPlayerData()
check("新存檔免遷移", Migrate.run(fresh), false)
local ok = pcall(Migrate.run, { Version = 99 })
check("拒絕比程式新的存檔", ok, false)

-- 回歸:連續 seed 不可產生同一種星球(曾因 LCG 首輸出相關,連跳 62 趟全是冰封星)
local seqCount = {}
for seed = 1001, 3000 do
	local p = PlanetGen.generate(seed, 4, Planets)
	seqCount[p.typeId] = (seqCount[p.typeId] or 0) + 1
end
local nonZero, maxShare = 0, 0
for _, c in seqCount do
	nonZero += 1
	maxShare = math.max(maxShare, c / 2000)
end
check("連續 seed 全部星球類型都出現", nonZero, #Planets.Types)
check("連續 seed 沒有單一類型 > 35%", maxShare < 0.35, true)
local wsum, rockW = 0, 0
for _, t in Planets.Types do
	wsum += t.weight
	if t.id == "Rock" then rockW = t.weight end
end
local rockShare = (seqCount.Rock or 0) / 2000
check("岩石星比例接近權重", math.abs(rockShare - rockW / wsum) < 0.05, true)
