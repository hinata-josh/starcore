local Gather = require("Gather")
local Migrate = require("Migrate")
local PlanetLevels = require("PlanetLevels")

local MAXLV = PlanetLevels.MaxLevel
local function fresh() return Migrate.newPlayerData() end

-- 間隔:Lv1 = 120 秒(上限 2 分鐘),滿級 = 20 秒(下限),中間遞減
check("Lv1 間隔 120 秒", Gather.interval(1, MAXLV), 120)
check("滿級間隔 20 秒", Gather.interval(MAXLV, MAXLV), 20)
check("間隔不低於 20 秒", Gather.interval(99, MAXLV), 20)
check("間隔不高於 120 秒", Gather.interval(0, MAXLV), 120)
local mono = true
for lv = 2, MAXLV do
	if Gather.interval(lv, MAXLV) >= Gather.interval(lv - 1, MAXLV) then mono = false end
end
check("星球等級越高間隔越短", mono, true)
check("Lv5 介於 20~120", Gather.interval(5, MAXLV) > 20 and Gather.interval(5, MAXLV) < 120, true)

-- 間隔檢查
local d = fresh()
check("新存檔第一次可以採", (Gather.check(d, "Ore", 1000, 1, MAXLV)), true)
check("記錄採集(未達上限)", Gather.record(d, "Ore", 1000), false)
local ok, why, wait = Gather.check(d, "Ore", 1060, 1, MAXLV)
check("60 秒後(Lv1)還在間隔內", ok, false)
check("原因是 TooSoon", why, "TooSoon")
check("還要等 60 秒", wait, 60)
check("間隔對所有資源一體適用", select(2, Gather.check(d, "Metal", 1060, 1, MAXLV)), "TooSoon")
check("120 秒後可以再採", (Gather.check(d, "Ore", 1120, 1, MAXLV)), true)
check("星球滿級 20 秒就可以再採", (Gather.check(d, "Ore", 1020, MAXLV, MAXLV)), true)
check("擴建星球縮短等待", select(3, Gather.check(d, "Ore", 1030, 5, MAXLV)) < 60, true)

-- 同一資源 20 次 → 12 小時冷卻
local c = fresh()
local now = 0
local cooled = false
for i = 1, 20 do
	now += 200
	assert(Gather.check(c, "Ore", now, 1, MAXLV))
	cooled = Gather.record(c, "Ore", now)
end
check("第 20 次採集觸發冷卻", cooled, true)
local ok2, why2, wait2 = Gather.check(c, "Ore", now + 200, 1, MAXLV)
check("冷卻中不能採該資源", ok2, false)
check("原因是 Cooldown", why2, "Cooldown")
check("冷卻剩餘約 12 小時 - 200 秒", wait2, 43200 - 200)
check("其他資源不受影響", (Gather.check(c, "Metal", now + 200, 1, MAXLV)), true)
check("11 小時後仍在冷卻", select(2, Gather.check(c, "Ore", now + 11 * 3600, 1, MAXLV)), "Cooldown")
check("12 小時後解除冷卻", (Gather.check(c, "Ore", now + 12 * 3600, 1, MAXLV)), true)
Gather.record(c, "Ore", now + 12 * 3600 + 1)
check("冷卻結束後重新計次(只算 1 次)", c.Gather.Counts.Ore, 1)

-- 第 19 次還不會冷卻
local c2 = fresh()
for i = 1, 19 do Gather.record(c2, "Ice", i * 200) end
check("19 次未冷卻", c2.Gather.CooldownUntil.Ice, nil)

-- 狀態(給 UI)
local c3 = fresh()
local t3 = 0
for i = 1, 20 do
	t3 += 200
	Gather.record(c3, "Ore", t3)
end
local st = Gather.status(c3, t3 + 100, 1, MAXLV)
check("status 有冷卻中的資源", st.cooling.Ore ~= nil, true)
check("status 的 interval", st.interval, 120)
check("status 的 readyIn", st.readyIn, 20)

-- 存檔遷移:v3 → v4 有 Gather 欄位
local old = { Version = 3, Inventory = {}, Friends = {}, Stats = {}, Quests = { Done = {} }, Daily = {} }
Migrate.run(old)
check("v3 遷移後有 Gather", old.Gather ~= nil and old.Gather.Counts ~= nil, true)
check("新存檔有 Gather", fresh().Gather.LastAt, 0)
