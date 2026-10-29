local Build = require("Build")
local Combat = require("Combat")
local HomePlanet = require("HomePlanet")
local Migrate = require("Migrate")
local Buildings = require("Buildings")
local Items = require("Items")
local Planets = require("Planets")
local Warp = require("Warp")
local PlanetLevels = require("PlanetLevels")

local itemIds = {}
for _, it in Items.Types do itemIds[it.id] = true end

-- ── 規模:20 種資源、50 種建築 ──
check("資源共 20 種", #Items.Types, 20)
check("建築共 51 種(含開局贈送的指揮中心)", #Buildings.Types, 51)
local seen, dup = {}, 0
for _, b in Buildings.Types do
	if seen[b.id] then dup += 1 end
	seen[b.id] = true
end
check("建築 id 不重複", dup, 0)

-- ── 引用完整性 ──
local bad = 0
local used = {}
local function useAll(cost)
	for id in cost do
		if not itemIds[id] then bad += 1 end
		used[id] = true
	end
end
for _, b in Buildings.Types do
	useAll(b.cost)
	if b.power == nil then bad += 1 end
end
for _, cat in Buildings.UpgradeLadder do
	for _, cost in cat do useAll(cost) end
end
for _, cost in Warp.upgradeCost do useAll(cost) end
for _, cost in PlanetLevels.Cost do useAll(cost) end
check("所有花費引用的資源 id 都存在", bad, 0)
local unused = {}
for id in itemIds do if not used[id] then table.insert(unused, id) end end
if #unused > 0 then print("沒有任何用途的資源:" .. table.concat(unused, ",")) end
check("每種資源都至少有一個用途", #unused, 0)

local ladderOk, nc = 0, 0
local cats = {}
for _, b in Buildings.Types do cats[b.category] = true end
for cat in cats do
	nc += 1
	local l = Buildings.UpgradeLadder[cat]
	if l and l[2] and l[3] then ladderOk += 1 end
end
check("每個建築類別都有 Lv2/Lv3 升級材料", ladderOk, nc)

local obtainable = {}
for _, p in Planets.Types do
	if #p.resources < 1 then bad += 1 end
	for _, r in p.resources do obtainable[r.id] = true end
end
local missing = 0
for id in itemIds do if not obtainable[id] then missing += 1 end end
check("20 種資源都能在某種星球採到", missing, 0)

-- ── 母星資源:隨機 5 種、2 種高產 ──
local det, shapeOk, boostOk, epicOk, rateOk = 0, 0, 0, 0, 0
local appear = {}
local N = 3000
local rateOf = {}
for _, it in Items.Types do rateOf[it.id] = it.rate end
for seed = 1, N do
	local h = HomePlanet.generate(seed, Items)
	local h2 = HomePlanet.generate(seed, Items)
	if table.concat(h.Resources, ",") == table.concat(h2.Resources, ",") then det += 1 end
	local set, distinct = {}, 0
	for _, id in h.Resources do
		if itemIds[id] and not set[id] then set[id] = true distinct += 1 end
		appear[id] = (appear[id] or 0) + 1
	end
	if #h.Resources == 5 and distinct == 5 then shapeOk += 1 end
	local inSet = #h.Boosted == 2
	local isBoost = {}
	for _, id in h.Boosted do
		isBoost[id] = true
		if not set[id] then inSet = false end
	end
	if inSet then boostOk += 1 end
	local epics = 0
	for _, it in Items.Types do
		if it.rarity == "epic" and set[it.id] then epics += 1 end
	end
	if epics <= 1 then epicOk += 1 end
	-- 去掉稀有度倍率後:高產/一般 = BOOST_RATE/NORMAL_RATE
	local ok = true
	for _, id in h.Resources do
		local base = h.Rates[id] / rateOf[id]
		local want = if isBoost[id] then HomePlanet.BOOST_RATE else HomePlanet.NORMAL_RATE
		if math.abs(base - want) > 1e-9 then ok = false end
	end
	if ok then rateOk += 1 end
end
check("母星資源確定性", det, N)
check("母星剛好 5 種不重複的有效資源", shapeOk, N)
check("母星 2 種高產且在 5 種之內", boostOk, N)
check("母星傳說級最多 1 種", epicOk, N)
check("高產/一般產量比例正確", rateOk, N)
local minApp, maxApp = 1e9, 0
for id in itemIds do
	local c = appear[id] or 0
	minApp = math.min(minApp, c)
	maxApp = math.max(maxApp, c)
end
check("每種資源都有機會出現在母星", minApp > 0, true)
print(("   母星出現率:最少 %.1f%%、最多 %.1f%%(理想 25%%)"):format(minApp / N * 100, maxApp / N * 100))
check("母星資源 ≠ 全部(必須穿梭採集)", 20 - HomePlanet.COUNT, 15)

-- 母星產出:只產自己的 5 種
local d = Migrate.newPlayerData()
d.Inventory = { Ore = 100, Metal = 100 }
HomePlanet.ensure(d, 777, Items)
local home = d.Planet.Home
Build.place(d, "1_0_0", "Miner", Buildings)
Build.place(d, "1_1_0", "SolarPanel", Buildings)
local before = {}
for k, v in d.Inventory do before[k] = v end
Build.tick(d, 600, Buildings)
local outside, gotTypes = 0, 0
for id, v in d.Inventory do
	if not home.Rates[id] and v ~= (before[id] or 0) then outside += 1 end
end
for id in home.Rates do
	if d.Inventory[id] - (before[id] or 0) > 0 then gotTypes += 1 end
end
check("採集機只產母星的 5 種", outside, 0)
check("母星資源有產出", gotTypes >= 4, true) -- 傳說級產量極低,10 分鐘可能不足 1 個
check("ensure 不覆蓋已有的母星", HomePlanet.ensure(d, 12345, Items) == home, true)

-- ── 採集倍率 / 倉儲 / 星核加成 ──
local y = Migrate.newPlayerData()
y.Inventory = { Ore = 100, Metal = 100, Copper = 50, Scrap = 50 }
Build.place(y, "1_0_0", "HeavyDrill", Buildings)
Build.place(y, "1_1_0", "SolarPanel", Buildings)
local y0 = y.Inventory.Ore
Build.tick(y, 10, Buildings) -- 無母星 → 後備產 Ore;重型鑽機 yield 1.8
check("重型鑽機(yield 1.8)十秒產 18 礦", y.Inventory.Ore - y0, 18)

local st = Migrate.newPlayerData()
st.Inventory = { Metal = 100, Sand = 100 }
local cap0 = Build.storageCap(st, Buildings)
Build.place(st, "1_0_0", "Warehouse", Buildings)
check("倉庫提高存量上限 +400", Build.storageCap(st, Buildings) - cap0, 400)
st.Planet.Slots["1_0_0"].Lv = 2
check("倉庫升級後加成翻倍", Build.storageCap(st, Buildings) - cap0, 800)

local c0 = Combat.defenseOf({}, Buildings, 1).coreHp
local c1 = Combat.defenseOf({ { id = "CoreReinforcer", lv = 1 } }, Buildings, 1).coreHp
check("星核強化裝置 +150 星核血量", c1 - c0, 150)

-- ── 星球擴建 ──
local e = Migrate.newPlayerData()
check("Lv1 可蓋 15 格", PlanetLevels.capacity(1), 15)
check("Lv10 可蓋 87 格", PlanetLevels.capacity(10), 87)
e.Inventory = { Ore = 100000 }
local placed, lastErr = 0, nil
for i = 0, 29 do
	local ok, err = Build.place(e, "1_" .. (i // 12) .. "_" .. (i % 12), "StoneWall", Buildings, PlanetLevels)
	if ok then placed += 1 else lastErr = err break end
end
check("Lv1 只能蓋滿 15 格", placed, 15)
check("滿格錯誤碼", lastErr, "PlanetFull")
e.Inventory = {}
check("沒材料不能擴建", select(2, Build.expandPlanet(e, PlanetLevels)), "NoResources")
e.Inventory = { Ore = 100, Metal = 20 }
check("擴建到 Lv2", Build.expandPlanet(e, PlanetLevels), true)
check("星球等級 2", e.Planet.Level, 2)
check("擴建扣材料", e.Inventory.Ore, 0)
check("擴建後可蓋 23 格", PlanetLevels.capacity(e.Planet.Level), 23)
e.Inventory = { Ore = 100 }
check("擴建後又能蓋了", Build.place(e, "2_0_0", "StoneWall", Buildings, PlanetLevels), true)
local nextCost = PlanetLevels.Cost[3]
check("Lv3 擴建要換材料(沙+銅)", nextCost.Sand ~= nil and nextCost.Copper ~= nil, true)
e.Planet.Level = 10
check("滿級不能再擴建", select(2, Build.expandPlanet(e, PlanetLevels)), "MaxLevel")

-- ── 越強的建築,需要的資源種類越多 ──
local function typeCount(cost)
	local n = 0
	for _ in cost do n += 1 end
	return n
end
local tierBad, tierMissing = 0, 0
local maxTier = #Buildings.MinTypesByTier
for _, b in Buildings.Types do
	if not b.tier or b.tier < 1 or b.tier > maxTier then
		tierMissing += 1
	elseif typeCount(b.cost) < Buildings.MinTypesByTier[b.tier] then
		tierBad += 1
		print("   資源種類不足:" .. b.id .. " T" .. b.tier .. " 只有 " .. typeCount(b.cost) .. " 種")
	end
end
check("每個建築都有 tier(1~5)", tierMissing, 0)
check("T1~T5 的資源種類 ≥ 1~5 種", tierBad, 0)

-- 同類別、同一項主要數值:數值越高,tier 不能更低
local metrics = {
	Energy = { "power" }, Collect = { "yield" }, Attack = { "dps" }, Storage = { "storage" },
	Defense = { "shield", "wallHp", "coreHp" },
}
local orderBad = 0
for cat, keys in metrics do
	for _, key in keys do
		local list = {}
		for _, b in Buildings.Types do
			if b.category == cat and b[key] and not b.control then table.insert(list, b) end
		end
		table.sort(list, function(a, c) return a[key] < c[key] end)
		for i = 2, #list do
			if list[i].tier < list[i - 1].tier then
				orderBad += 1
				print("   強度與 tier 倒置:" .. list[i - 1].id .. "(T" .. list[i - 1].tier .. ") → " .. list[i].id .. "(T" .. list[i].tier .. ")")
			end
		end
	end
end
check("同類別數值越高 tier 不會更低", orderBad, 0)

-- 最強的 tier 需要的種類確實比最弱的多
local minT1, maxT5 = 99, 0
for _, b in Buildings.Types do
	if b.tier == 1 then minT1 = math.min(minT1, typeCount(b.cost)) end
	if b.tier == 5 then maxT5 = math.max(maxT5, typeCount(b.cost)) end
end
check("T5 建築至少要 5 種資源", maxT5 >= 5, true)
local tierCount = {}
for _, b in Buildings.Types do tierCount[b.tier] = (tierCount[b.tier] or 0) + 1 end
print(("   各 tier 建築數:T1=%d T2=%d T3=%d T4=%d T5=%d"):format(tierCount[1] or 0, tierCount[2] or 0, tierCount[3] or 0, tierCount[4] or 0, tierCount[5] or 0))
check("每個 tier 都有建築", #tierCount, 5)
