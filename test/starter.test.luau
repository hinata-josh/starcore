local Starter = require("Starter")
local Migrate = require("Migrate")
local Build = require("Build")
local Buildings = require("Buildings")
local Combat = require("Combat")
local Energy = require("Energy")
local PlanetLevels = require("PlanetLevels")

local function countId(d, id)
	local c = 0
	for _, s in d.Planet.Slots do
		if s.Id == id then c += 1 end
	end
	return c
end

-- 1. 新存檔:送基地 + 脈衝砲台,放在預設位置
local d = Migrate.newPlayerData()
check("空白範本沒有建築", next(d.Planet.Slots) == nil, true)
local placed = Starter.grant(d)
check("送了指揮中心", countId(d, "CommandCenter"), 1)
check("送了脈衝砲台", countId(d, "PulseTurret"), 1)
check("基地在預設格", d.Planet.Slots[Starter.BASE_KEY] and d.Planet.Slots[Starter.BASE_KEY].Id, "CommandCenter")
check("砲台在預設格", d.Planet.Slots[Starter.DEFENSE_KEY] and d.Planet.Slots[Starter.DEFENSE_KEY].Id, "PulseTurret")
check("回傳放下 3 座(基地+砲台+時空門)", (function() local c = 0 for _ in placed do c += 1 end return c end)(), 3)

-- 2. 基地的電力夠讓送的砲台運作(不用先蓋太陽能板)
local e = Energy.balance(Build.placedList(d), Buildings)
check("開局電力滿足", e.satisfaction, 1)
local def = Combat.defenseOf(Build.placedList(d), Buildings, d.Planet.Level)
check("開局就有火力(脈衝砲台 dps 12)", def.dps, 12)
check("基地加星核血量 +100", def.coreHp, Combat.coreHp(1) + 100)

-- 3. 基地不佔建造格數、不能自己蓋、不能拆
check("格數只算砲台", Build.slotsUsed(d), 1)
check("不能自己蓋指揮中心", select(2, Build.place(d, "1_1_1", "CommandCenter", Buildings, PlanetLevels)), "NotBuildable")
check("不能拆指揮中心", select(2, Build.remove(d, Starter.BASE_KEY, Buildings)), "Permanent")
check("基地還在", countId(d, "CommandCenter"), 1)
check("送的砲台可以拆", Build.remove(d, Starter.DEFENSE_KEY, Buildings), true)

-- 4. 不重複送
Starter.grant(d)
Starter.grant(d)
check("已有基地:不再送基地", countId(d, "CommandCenter"), 1)
check("已有基地:不再送砲台", countId(d, "PulseTurret"), 0)

-- 5. 預設格被佔:找最近的空格
local o = Migrate.newPlayerData()
o.Planet.Slots[Starter.BASE_KEY] = { Id = "Miner", Lv = 1 }
o.Planet.Slots[Starter.DEFENSE_KEY] = { Id = "SolarPanel", Lv = 1 }
Starter.grant(o)
check("佔用時:基地放別格", countId(o, "CommandCenter"), 1)
check("佔用時:原建築不被覆蓋", o.Planet.Slots[Starter.BASE_KEY].Id, "Miner")
check("佔用時:砲台也放別格", countId(o, "PulseTurret"), 1)
local baseKey
for k, s in o.Planet.Slots do
	if s.Id == "CommandCenter" then baseKey = k end
end
check("佔用時:基地還在北極那一面", string.sub(baseKey, 1, 2), "3_")

-- 6. 舊存檔(v4)遷移:補送基地與砲台,原有建築不動
local old = Migrate.newPlayerData()
old.Version = 4
old.Planet.Slots["1_5_5"] = { Id = "Miner", Lv = 2 }
Migrate.run(old)
check("遷移到最新版", old.Version, Migrate.CURRENT)
check("遷移:補送基地", countId(old, "CommandCenter"), 1)
check("遷移:補送砲台", countId(old, "PulseTurret"), 1)
check("遷移:原建築保留", old.Planet.Slots["1_5_5"].Lv, 2)

-- 7. 建造選單看不到指揮中心
local visible = 0
for _, b in Buildings.Types do
	if not b.hidden then visible += 1 end
end
check("建造選單 50 種", visible, 50)

-- 8. 重建星球:拆掉基地以外全部建築,建造 + 升級花費全數退還
local rb = Migrate.newPlayerData()
Starter.grant(rb)
rb.Inventory = { Ore = 1000, Metal = 1000, Copper = 200, Scrap = 200, Sand = 200 }
local before = table.clone(rb.Inventory)
Build.place(rb, "1_1_1", "Miner", Buildings, PlanetLevels)
Build.place(rb, "1_2_1", "SolarPanel", Buildings, PlanetLevels)
Build.place(rb, "1_3_1", "Warehouse", Buildings, PlanetLevels)
Build.upgrade(rb, "1_1_1", Buildings) -- 礦機升 Lv2(要額外 Metal)
check("重建前:蓋了也升了", rb.Planet.Slots["1_1_1"].Lv, 2)
local refund, removed = Build.rebuild(rb, Buildings)
check("重建:拆掉 3 座 + 送的砲台", removed, 4)
check("重建:只剩基地", Build.slotsUsed(rb), 0)
check("重建:基地還在", countId(rb, "CommandCenter"), 1)
-- 自己花的全部拿回來;另外多了送的砲台的價值(Ore 30 / Metal 10)
check("重建:礦石全數退還(含送的砲台)", rb.Inventory.Ore, before.Ore + 30)
check("重建:金屬全數退還(含升級材料)", rb.Inventory.Metal, before.Metal + 10)
check("重建:沙全數退還", rb.Inventory.Sand, before.Sand)
local n0 = 0
for _ in refund do n0 += 1 end
check("重建:回傳退還表", n0 >= 2, true)
check("重建兩次:沒東西可拆", select(2, Build.rebuild(rb, Buildings)), 0)

-- 9. 時空門直接送:新存檔有門、不佔格數、重建保留;v5 舊存檔(已有基地)只補門
local g = Migrate.newPlayerData()
Starter.grant(g)
check("送了時空門", countId(g, "WarpGate"), 1)
check("時空門在預設格", g.Planet.Slots[Starter.GATE_KEY] and g.Planet.Slots[Starter.GATE_KEY].Id, "WarpGate")
check("時空門不佔格數(只算砲台)", Build.slotsUsed(g), 1)
check("已有門:不能再蓋一座", select(2, Build.place(g, "1_1_1", "WarpGate", Buildings, PlanetLevels)), "Limit")
Build.rebuild(g, Buildings)
check("重建後時空門還在", countId(g, "WarpGate"), 1)
local v5 = Migrate.newPlayerData()
v5.Version = 5
v5.Planet.Slots["3_5_7"] = { Id = "CommandCenter", Lv = 1 }
Migrate.run(v5)
check("v5→v6:補送時空門", countId(v5, "WarpGate"), 1)
check("v5→v6:不重複送砲台", countId(v5, "PulseTurret"), 0)
check("v5→v6:不重複送基地", countId(v5, "CommandCenter"), 1)
