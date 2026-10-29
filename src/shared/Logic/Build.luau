--!strict
-- 母星建造規則(伺服器權威):驗證 → 就地修改存檔。client 只送意圖,結果以這裡為準。
-- data = PlayerData(見 Migrate.newPlayerData);defs = Data.Buildings

local CubeSphere = require(script.Parent.CubeSphere)
local Inventory = require(script.Parent.Inventory)
local Energy = require(script.Parent.Energy)

local Build = {}

Build.REFUND_RATIO = 0.5
Build.STORAGE_PER_LEVEL = 600 -- 每種資源的存量上限 = 母星等級 × 此值(要夠大,離線 2 小時的收益才有「賺到」的感覺)
Build.MAX_PER_TYPE = { WarpGate = 1 }

local function find(defs: any, id: string): any?
	for _, d in defs.Types do
		if d.id == id then
			return d
		end
	end
	return nil
end
Build.find = find

-- 不佔建造格數的建築(開局送的基地、時空門)
Build.FREE_SLOT = { CommandCenter = true, WarpGate = true }
-- 重建星球時保留的建築(除了 permanent 以外):時空門是開局送的,重建不該弄丟
Build.KEEP_ON_REBUILD = { WarpGate = true }

function Build.slotsUsed(data: any): number
	local c = 0
	for _, s in data.Planet.Slots do
		if not Build.FREE_SLOT[s.Id] then
			c += 1
		end
	end
	return c
end

local function count(data: any, id: string): number
	local c = 0
	for _, s in data.Planet.Slots do
		if s.Id == id then
			c += 1
		end
	end
	return c
end

-- 回傳 ok, 錯誤碼(失敗時)。錯誤碼:BadSlot / UnknownBuilding / NotBuildable / Occupied / PlanetFull / Limit / NoResources
function Build.canPlace(data: any, slotKey: string, buildingId: string, defs: any, levels: any?): (boolean, string?)
	if type(slotKey) ~= "string" or type(buildingId) ~= "string" then
		return false, "BadSlot"
	end
	if not CubeSphere.parseKey(slotKey, data.Planet.N) then
		return false, "BadSlot"
	end
	local def = find(defs, buildingId)
	if not def then
		return false, "UnknownBuilding"
	end
	if def.hidden then
		return false, "NotBuildable" -- 例:指揮中心只能開局送
	end
	if data.Planet.Slots[slotKey] then
		return false, "Occupied"
	end
	if levels and Build.slotsUsed(data) >= levels.capacity(data.Planet.Level) then
		return false, "PlanetFull"
	end
	local limit = Build.MAX_PER_TYPE[buildingId]
	if limit and count(data, buildingId) >= limit then
		return false, "Limit"
	end
	if not Inventory.canAfford(data.Inventory, def.cost) then
		return false, "NoResources"
	end
	return true, nil
end

function Build.place(data: any, slotKey: string, buildingId: string, defs: any, levels: any?): (boolean, string?)
	local ok, err = Build.canPlace(data, slotKey, buildingId, defs, levels)
	if not ok then
		return false, err
	end
	local def = find(defs, buildingId)
	Inventory.spend(data.Inventory, def.cost)
	data.Planet.Slots[slotKey] = { Id = buildingId, Lv = 1 }
	return true, nil
end

function Build.remove(data: any, slotKey: string, defs: any): (boolean, string?)
	local slot = data.Planet.Slots[slotKey]
	if not slot then
		return false, "Empty"
	end
	local def = find(defs, slot.Id)
	if def and def.permanent then
		return false, "Permanent" -- 基地不能拆
	end
	if def then
		for id, n in Inventory.refund(def.cost, Build.REFUND_RATIO) do
			Inventory.add(data.Inventory, id, n)
		end
	end
	data.Planet.Slots[slotKey] = nil
	return true, nil
end

-- 重建星球:拆掉指揮中心(permanent)與時空門(KEEP_ON_REBUILD)以外的所有建築,建造 + 升級花過的資源 100% 退還(重新規劃不吃虧)。
-- 星球等級、背包、時空門等級不變。回傳 (退還表, 拆掉幾座)
function Build.rebuild(data: any, defs: any): ({ [string]: number }, number)
	local refund: { [string]: number } = {}
	local function addAll(cost: { [string]: number })
		for id, n in cost do
			refund[id] = (refund[id] or 0) + n
		end
	end
	local removed = 0
	for key, s in data.Planet.Slots do
		local def = find(defs, s.Id)
		if not (def and def.permanent) and not Build.KEEP_ON_REBUILD[s.Id] then
			if def then
				addAll(def.cost)
				for lv = 1, (s.Lv or 1) - 1 do
					addAll(Build.upgradeCost(def, lv, defs)) -- 升到 lv+1 時花的
				end
			end
			data.Planet.Slots[key] = nil
			removed += 1
		end
	end
	for id, n in refund do
		Inventory.add(data.Inventory, id, n)
	end
	return refund, removed
end

-- 升級時空門等級;回傳 ok, 錯誤碼(MaxLevel / NoResources / NoGate)
function Build.upgradeWarp(data: any, warp: any): (boolean, string?)
	local nextLv = data.Tech.WarpLv + 1
	local cost = warp.upgradeCost[nextLv]
	if not cost then
		return false, "MaxLevel"
	end
	if count(data, "WarpGate") == 0 then
		return false, "NoGate"
	end
	if not Inventory.canAfford(data.Inventory, cost) then
		return false, "NoResources"
	end
	Inventory.spend(data.Inventory, cost)
	data.Tech.WarpLv = nextLv
	return true, nil
end

Build.MAX_BUILDING_LV = 3
Build.OFFLINE_MAX_SEC = 2 * 3600 -- 離線收益最多算 2 小時(鼓勵每天回來,不鼓勵掛機)

-- 升級花費:Lv→Lv+1 = 原價 × 1.5 × 目前等級(無條件進位) + 該類別「目標等級」的額外材料(越高級越需要稀有資源)
function Build.upgradeCost(def: any, lv: number, defs: any?): { [string]: number }
	local cost = {}
	for id, n in def.cost do
		cost[id] = math.ceil(n * 1.5 * lv)
	end
	local ladder = defs and defs.UpgradeLadder and defs.UpgradeLadder[def.category]
	local extra = ladder and ladder[lv + 1]
	if extra then
		for id, n in extra do
			cost[id] = (cost[id] or 0) + n
		end
	end
	return cost
end

-- 升級建築;回傳 ok, 錯誤碼(Empty / MaxLevel / UnknownBuilding / NoResources)
function Build.upgrade(data: any, slotKey: string, defs: any): (boolean, string?)
	local slot = data.Planet.Slots[slotKey]
	if not slot then
		return false, "Empty"
	end
	if slot.Lv >= (defs.MaxLevel or Build.MAX_BUILDING_LV) then
		return false, "MaxLevel"
	end
	local def = find(defs, slot.Id)
	if not def then
		return false, "UnknownBuilding"
	end
	local cost = Build.upgradeCost(def, slot.Lv, defs)
	if not Inventory.canAfford(data.Inventory, cost) then
		return false, "NoResources"
	end
	Inventory.spend(data.Inventory, cost)
	slot.Lv += 1
	return true, nil
end

-- 星球擴建:升一級 → 可蓋格數變多、存量上限與星核血量上升;花費每級換不同材料(Data/PlanetLevels)
function Build.expandPlanet(data: any, levels: any): (boolean, string?)
	local nextLv = data.Planet.Level + 1
	local cost = levels.Cost[nextLv]
	if not cost or nextLv > levels.MaxLevel then
		return false, "MaxLevel"
	end
	if not Inventory.canAfford(data.Inventory, cost) then
		return false, "NoResources"
	end
	Inventory.spend(data.Inventory, cost)
	data.Planet.Level = nextLv
	return true, nil
end

-- 每種資源的存量上限:星球等級 × STORAGE_PER_LEVEL + 倉儲建築加成
function Build.storageCap(data: any, defs: any): number
	local cap = data.Planet.Level * Build.STORAGE_PER_LEVEL
	for _, s in data.Planet.Slots do
		local def = find(defs, s.Id)
		if def and def.storage then
			cap += def.storage * s.Lv
		end
	end
	return cap
end

-- 離線收益:依上次離線時間補算產出(上限 OFFLINE_MAX_SEC);回傳 秒數, 入帳總量
function Build.offline(data: any, now: number, defs: any): (number, number)
	local last = data.LastSeen or 0
	data.LastSeen = now
	if last <= 0 or now <= last then
		return 0, 0
	end
	local secs = math.min(now - last, Build.OFFLINE_MAX_SEC)
	local gained = 0
	local left = secs
	while left > 0 do
		local dt = math.min(60, left)
		gained += Build.tick(data, dt, defs)
		left -= dt
	end
	return secs, gained
end

function Build.placedList(data: any): { { id: string, lv: number } }
	local list = {}
	for _, s in data.Planet.Slots do
		table.insert(list, { id = s.Id, lv = s.Lv })
	end
	return list
end

-- 經過 dt 秒:採集建築依電力滿足率產出,存入背包(小數累積在 Planet.Acc,滿 1 才入帳)
-- 回傳這次入帳的總量(供測試/通知用)
function Build.tick(data: any, dt: number, defs: any): number
	local sat = Energy.balance(Build.placedList(data), defs).satisfaction
	local acc = data.Planet.Acc
	if not acc then
		acc = {}
		data.Planet.Acc = acc
	end
	local cap = Build.storageCap(data, defs)
	local credited = 0
	for _, s in data.Planet.Slots do
		local def = find(defs, s.Id)
		if def and def.produces then
			-- 有母星資料 → 產母星自己的 5 種資源(高產的快);沒有 → 用建築定義的後備產物
			local rates = if data.Planet.Home then data.Planet.Home.Rates else def.produces
			for id, rate in rates do
				acc[id] = (acc[id] or 0) + rate * (def.yield or 1) * s.Lv * sat * dt
			end
		end
	end
	for id, v in acc do
		local whole = math.floor(v)
		if whole >= 1 then
			local room = math.max(0, cap - (data.Inventory[id] or 0))
			local gain = math.min(whole, room)
			Inventory.add(data.Inventory, id, gain)
			credited += gain
			acc[id] = if gain < whole then 0 else v - whole -- 滿倉時不再累積溢出
		end
	end
	return credited
end

return Build
