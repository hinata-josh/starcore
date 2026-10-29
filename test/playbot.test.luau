-- 機器人玩家「試玩」:用純邏輯從開局一路自動玩,量化體驗(經濟卡關、閒置、勝負曲線)。
-- 規則全部照遊戲:母星只有隨機 5 種資源(2 種高產)、穿梭採集有間隔(取決星球等級)與 20 次冷卻、
-- 50 種建築、升級換材料、擴建星球。機器人 = 合理但不完美的玩家(不會規劃到極致)。
-- 這不是真人手感,只能回答「數字上會不會卡、會不會太無聊/太難」。
local Build = require("Build")
local Trip = require("Trip")
local Combat = require("Combat")
local WaveLogic = require("WaveLogic")
local PlanetGen = require("PlanetGen")
local Inventory = require("Inventory")
local Energy = require("Energy")
local Gather = require("Gather")
local HomePlanet = require("HomePlanet")
local Migrate = require("Migrate")
local Buildings = require("Buildings")
local Monsters = require("Monsters")
local Planets = require("Planets")
local Items = require("Items")
local Warp = require("Warp")
local PlanetLevels = require("PlanetLevels")

local STEP = 5
local HORIZON = 6 * 3600
local WALK_AND_HOLD = 6 -- 走到資源點 + 長按一次(秒)

local VALUE = { common = 1, uncommon = 3, rare = 5, epic = 8 }
local valueOf = {}
for _, it in Items.Types do valueOf[it.id] = VALUE[it.rarity] end

-- 各類建築依「強度」排序,機器人每次挑最強且買得起的
local byCat = {}
for _, b in Buildings.Types do
	byCat[b.category] = byCat[b.category] or {}
	table.insert(byCat[b.category], b)
end
local function sortBy(cat, key)
	table.sort(byCat[cat], function(a, b) return (a[key] or 0) > (b[key] or 0) end)
end
sortBy("Energy", "power")
sortBy("Collect", "yield")
sortBy("Attack", "dps")
local shields, walls, cores = {}, {}, {}
for _, b in byCat.Defense do
	if b.shield then table.insert(shields, b) end
	if b.wallHp then table.insert(walls, b) end
	if b.coreHp then table.insert(cores, b) end
end
table.sort(shields, function(a, b) return a.shield > b.shield end)
table.sort(walls, function(a, b) return a.wallHp > b.wallHp end)
table.sort(cores, function(a, b) return a.coreHp > b.coreHp end)

local function run(homeSeed, opts)
	opts = opts or {}
	local data = Migrate.newPlayerData()
	HomePlanet.ensure(data, homeSeed, Items)
	local t, wave = 0, 1
	local nextWave = WaveLogic.FIRST_WAVE_DELAY
	local tripEnd, tripLoot = nil, nil
	local slotCounter = 0
	local seedCounter = homeSeed * 1000
	local log = { gained = {}, waves = {}, idle = 0, inTrip = 0, trips = 0, actions = 0, blockedTooSoon = 0,
		firstTurretAt = nil, firstWarpAt = nil, home = data.Planet.Home }
	local consecutiveLoss = 0

	local function nextSlot()
		slotCounter += 1
		local face = (slotCounter - 1) // 144 + 1
		local r = (slotCounter - 1) % 144
		return face .. "_" .. (r // 12) .. "_" .. (r % 12)
	end
	local function count(id)
		local c = 0
		for _, s in data.Planet.Slots do if s.Id == id then c += 1 end end
		return c
	end
	local function try(def)
		local ok = Build.place(data, nextSlot(), def.id, Buildings, PlanetLevels)
		if not ok then slotCounter -= 1 end
		return ok
	end
	local function tryList(list)
		for _, d in list do if try(d) then return d end end
		return nil
	end
	local function sat() return Energy.balance(Build.placedList(data), Buildings).satisfaction end
	local function defense() return Combat.defenseOf(Build.placedList(data), Buildings, data.Planet.Level) end

	local function wantDps()
		local boss = WaveLogic.isBoss(wave, Monsters)
		return WaveLogic.threat(wave) / 7 * (if boss then 3 else 1)
	end
	local function upgradeSome()
		for _, cat in { "Attack", "Defense", "Collect", "Energy" } do
			for k, sl in data.Planet.Slots do
				local d = Build.find(Buildings, sl.Id)
				if d.category == cat and sl.Lv < Buildings.MaxLevel and Build.upgrade(data, k, Buildings) then return true end
			end
		end
		return false
	end

	local function botBuild()
		local did = false
		-- 教學三件
		for _, id in { "Miner", "SolarPanel", "WarpGate" } do
			if count(id) == 0 and try(Build.find(Buildings, id)) then did = true end
		end
		-- 電力不足先補電
		if sat() < 1 and tryList(byCat.Energy) then did = true end
		-- 火力
		local def = defense()
		if def.dps < wantDps() then
			if tryList(byCat.Attack) then
				did = true
				log.firstTurretAt = log.firstTurretAt or t
			end
		end
		-- 擴建星球(格子快滿就擴)
		if Build.slotsUsed(data) >= PlanetLevels.capacity(data.Planet.Level) - 1 and Build.expandPlanet(data, PlanetLevels) then did = true end
		-- 時空門升級、建築升級
		if count("WarpGate") > 0 and Build.upgradeWarp(data, Warp) then did = true end
		if upgradeSome() then did = true end
		-- 護盾、牆、星核、採集機
		def = defense()
		local thr = WaveLogic.threat(wave)
		if def.shield < thr * 0.8 and tryList(shields) then did = true end
		if def.wallHp < thr * 0.8 and tryList(walls) then did = true end
		if count("CoreReinforcer") + count("CoreBulwark") < 2 and tryList(cores) then did = true end
		local miners = 0
		for _, d in byCat.Collect do miners += count(d.id) end
		if miners < 4 and tryList(byCat.Collect) then did = true end
		return did
	end

	local function planTrip()
		seedCounter += 1
		local first = data.Stats.Trips == 0
		local planet = PlanetGen.generate(seedCounter, data.Tech.WarpLv, Planets, if first then "Rock" else nil)
		data.Stats.Trips += 1
		local trip = Trip.start(seedCounter, planet, 0, data.Tech.WarpLv, Warp)
		local spent = 4
		local limit = Warp.durationSec - 20
		while spent < limit do
			-- 挑「價值最高、沒在冷卻、還有量」的資源點
			local bestI, bestV = nil, -1
			for i, n in trip.nodes do
				if n.amount > 0 then
					local cd = data.Gather.CooldownUntil[n.id]
					if not (cd and t + spent < cd) then
						local v = (valueOf[n.id] or 1) * (if (data.Inventory[n.id] or 0) > 300 then 0.2 else 1) -- 庫存很多的就不急著採
						if v > bestV then bestI, bestV = i, v end
					end
				end
			end
			if not bestI then break end
			local node = trip.nodes[bestI]
			local ok, why, wait = Gather.check(data, node.id, t + spent, data.Planet.Level, PlanetLevels.MaxLevel)
			if not ok and why == "TooSoon" then
				if spent + wait + WALK_AND_HOLD > limit then log.blockedTooSoon += 1 break end
				spent += wait
			elseif not ok then
				break
			end
			local g = Trip.gather(trip, bestI, Items, Warp)
			if not g then break end
			Gather.record(data, node.id, t + spent)
			log.actions += 1
			spent += WALK_AND_HOLD
			if Trip.weight(trip, Items) >= trip.capacity then break end
		end
		tripLoot = Trip.settle(trip, Items, Warp, false)
		tripEnd = t + spent + 6
		log.trips += 1
		log.firstWarpAt = log.firstWarpAt or t
	end

	while t < HORIZON do
		t += STEP
		Build.tick(data, STEP, Buildings)

		if tripEnd then
			log.inTrip += STEP
			if t >= tripEnd then
				for id, n in tripLoot do
					Inventory.add(data.Inventory, id, n)
					log.gained[id] = (log.gained[id] or 0) + n
				end
				tripEnd, tripLoot = nil, nil
			end
		elseif count("WarpGate") > 0 and Inventory.canAfford(data.Inventory, Warp.cost) and not opts.noWarp then
			-- 採集間隔還沒到就先在家待著,別空手跑
			local ready = t >= data.Gather.LastAt + Gather.interval(data.Planet.Level, PlanetLevels.MaxLevel) - 30
			if ready then
				Inventory.spend(data.Inventory, Warp.cost)
				planTrip()
			end
		end

		local acted = botBuild()
		if not acted and not tripEnd then log.idle += STEP end

		if t >= nextWave then
			local comp = WaveLogic.compose(wave, 99, Monsters, WaveLogic.mercy(consecutiveLoss))
			local def = defense()
			local res = Combat.simulate(def, comp, Monsters, comp.budget)
			table.insert(log.waves, { n = wave, won = res.won, core = res.coreHpLeft, coreMax = def.coreHp,
				dps = def.dps, shield = def.shield, wall = def.wallHp, threat = WaveLogic.threat(wave), t = t,
				mons = res.total, killed = res.killed, scale = comp.scale, boss = comp.bossId, lv = data.Planet.Level })
			if res.won then
				consecutiveLoss = 0
				for id, n in WaveLogic.reward(wave, Monsters) do Inventory.add(data.Inventory, id, n) end
				wave += 1 -- 贏了才進下一波(真實遊戲:輸了同一波重打)
			else
				consecutiveLoss += 1
				for id, n in data.Inventory do data.Inventory[id] = math.floor(n * 0.7) end
			end
			nextWave = t + WaveLogic.countdownSeconds(wave)
			if consecutiveLoss >= 4 then break end
		end
	end
	log.endT, log.finalWave, log.data = t, wave - 1, data
	return log
end

local function names(list)
	local out = {}
	for _, id in list do
		for _, it in Items.Types do if it.id == id then table.insert(out, it.name) end end
	end
	return table.concat(out, "、")
end

local function report(label, log)
	print(("== %s =="):format(label))
	print(("  母星資源:%s;高產:%s"):format(names(log.home.Resources), names(log.home.Boosted)))
	print(("  總時長 %d 分;守住 %d 波;穿梭 %d 趟(%d%% 時間在外面);採集 %d 次;閒置 %d%%;星球 Lv%d"):format(
		log.endT // 60, log.finalWave, log.trips, math.floor(log.inTrip / log.endT * 100), log.actions,
		math.floor(log.idle / log.endT * 100), log.data.Planet.Level))
	local line = {}
	for _, w in log.waves do table.insert(line, ("%d%s"):format(w.n, w.won and "✓" or "✗")) end
	print("  波次:" .. table.concat(line, " "))
	for _, w in log.waves do
		if w.n <= 2 or not w.won then
			print(("   W%-2d 強度%-5.0f 怪%-2d(擊殺%d)dps %-5.1f 護盾 %-4.0f 牆 %-4.0f 星核 %.0f/%.0f%s @%d分"):format(
				w.n, w.threat, w.mons, w.killed, w.dps, w.shield, w.wall, w.core, w.coreMax, w.boss and " 首領" or "", w.t // 60))
		end
	end
	local bc = {}
	for _, sl in log.data.Planet.Slots do bc[sl.Id] = (bc[sl.Id] or 0) + 1 end
	local bl = {}
	for id, n in bc do table.insert(bl, id .. "×" .. n) end
	table.sort(bl)
	print("  建築:" .. table.concat(bl, " "))
	local kinds = 0
	for _ in log.gained do kinds += 1 end
	print(("  穿梭採到 %d 種資源;首次穿梭 %s 秒;首座砲台 %s 秒"):format(kinds, tostring(log.firstWarpAt), tostring(log.firstTurretAt)))
end

-- 多個母星運氣(不同 seed)
local SEEDS = { 1, 2, 3, 4, 5, 6, 7, 8 }
local results = {}
for _, s in SEEDS do results[s] = run(s) end
report("標準玩家 母星 seed=1", results[1])
report("標準玩家 母星 seed=2", results[2])

local finals, early = {}, 0
for _, s in SEEDS do
	local r = results[s]
	table.insert(finals, r.finalWave)
	local w5 = 0
	for _, w in r.waves do if w.n <= 5 and w.won then w5 += 1 end end
	if w5 < 4 then early += 1 end
end
table.sort(finals)
print(("== 8 種母星運氣:守住波數 %s;中位數 %d;前 5 波受挫的母星 %d/8"):format(table.concat(finals, ","), finals[4], early))
local lazy = run(1, { noWarp = true })
report("不穿梭玩家(只守母星)", lazy)

local lazyFinals = {}
for _, s in SEEDS do table.insert(lazyFinals, run(s, { noWarp = true }).finalWave) end
table.sort(lazyFinals)
print(("== 不穿梭玩家 8 種母星運氣:守住波數 %s;中位數 %d(標準玩家中位數 %d)"):format(table.concat(lazyFinals, ","), lazyFinals[4], finals[4]))

-- 體驗護欄
check("多數母星運氣下前 5 波不受挫(新手友善)", early <= 1, true)
check("標準玩家守住波數中位數 ≥ 10(有長期目標)", finals[4] >= 10, true)
check("沒有任何標準玩家 6 小時內輕鬆通關(有挑戰)", finals[#finals] < 40, true)
check("首次穿梭在 3 分鐘內", results[1].firstWarpAt ~= nil and results[1].firstWarpAt <= 180, true)
check("不穿梭玩家明顯比標準玩家弱(穿梭有必要性)", lazyFinals[4] + 2 <= finals[4], true)
