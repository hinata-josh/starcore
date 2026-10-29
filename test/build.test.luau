local Build = require("Build")
local Inventory = require("Inventory")
local Migrate = require("Migrate")
local Buildings = require("Buildings")
local Items = require("Items")

local function fresh(extra)
	local d = Migrate.newPlayerData()
	d.Inventory = { Ore = 50, Metal = 10 } -- 固定測試基準,不跟遊戲開局數值綁定
	for id, n in (extra or {}) do d.Inventory[id] = n end
	return d
end

-- 背包
local inv = { Ore = 10, Metal = 3 }
check("買得起", Inventory.canAfford(inv, { Ore = 10 }), true)
check("買不起", Inventory.canAfford(inv, { Ore = 11 }), false)
check("載重 10×1+3×2", Inventory.totalWeight(inv, Items), 16)
check("退款取整", Inventory.refund({ Ore = 15, Metal = 5 }, 0.5).Ore, 7)

-- 建造:成功扣資源
local d = fresh()
local ok, err = Build.place(d, "1_0_0", "Miner", Buildings)
check("蓋礦機成功", ok, true)
check("扣 20 礦石", d.Inventory.Ore, 30)
check("格位寫入", d.Planet.Slots["1_0_0"].Id, "Miner")

-- 失敗情境(且失敗不得改動存檔)
ok, err = Build.place(d, "1_0_0", "Miner", Buildings)
check("重複蓋→Occupied", err, "Occupied")
ok, err = Build.place(d, "9_0_0", "Miner", Buildings)
check("面編號越界→BadSlot", err, "BadSlot")
ok, err = Build.place(d, "1_12_0", "Miner", Buildings)
check("格座標越界→BadSlot", err, "BadSlot")
ok, err = Build.place(d, "1_1_0", "Nope", Buildings)
check("未知建築", err, "UnknownBuilding")
ok, err = Build.place(d, "1_1_0", "WarpGate", Buildings)
check("資源不足", err, "NoResources")
check("失敗不扣資源", d.Inventory.Ore, 30)
ok, err = Build.place(d, nil, "Miner", Buildings)
check("惡意 nil 參數不當機", ok, false)
ok, err = Build.place(d, "1_2_0", {}, Buildings)
check("惡意 table 參數不當機", ok, false)

-- 數量上限
local g = fresh({ Metal = 200, Crystal = 100 })
check("第一座時空門", Build.place(g, "2_0_0", "WarpGate", Buildings), true)
local _, e2 = Build.place(g, "2_1_0", "WarpGate", Buildings)
check("第二座時空門被擋", e2, "Limit")

-- 拆除退 50%
local r = fresh()
Build.place(r, "1_0_0", "Miner", Buildings)
check("拆除成功", Build.remove(r, "1_0_0", Buildings), true)
check("退款 10", r.Inventory.Ore, 30 + 10)
check("格位清空", r.Planet.Slots["1_0_0"], nil)
check("拆空格失敗", Build.remove(r, "1_0_0", Buildings), false)

-- 產出:礦機耗電 2、沒發電 → 滿足率 0 → 不產出
local p = fresh({ Ore = 100, Metal = 50 })
Build.place(p, "1_0_0", "Miner", Buildings)
local before = p.Inventory.Ore
Build.tick(p, 10, Buildings)
check("沒電不產出", p.Inventory.Ore, before)
-- 加太陽能板(發電4 ≥ 礦機耗電2)→ 滿速 1/秒
Build.place(p, "1_1_0", "SolarPanel", Buildings)
before = p.Inventory.Ore
local got = Build.tick(p, 10, Buildings)
check("有電 10 秒產 10 礦", p.Inventory.Ore - before, 10)
check("tick 回傳入帳量", got, 10)

-- 小數累積:每次 0.4 秒,3 次共 1.2 → 入帳 1
local q = fresh({ Ore = 100, Metal = 50 })
Build.place(q, "1_0_0", "Miner", Buildings)
Build.place(q, "1_1_0", "SolarPanel", Buildings)
local b2 = q.Inventory.Ore
for i = 1, 3 do Build.tick(q, 0.4, Buildings) end
check("小數累積後入帳 1", q.Inventory.Ore - b2, 1)

-- 存量上限:Lv1 = STORAGE_PER_LEVEL,滿倉不再增加
local CAP = Build.STORAGE_PER_LEVEL
local c = fresh({ Ore = CAP - 5, Metal = 50 })
Build.place(c, "1_0_0", "Miner", Buildings) -- 扣 20 → 175
Build.place(c, "1_1_0", "SolarPanel", Buildings) -- 再扣 15 → 160
Build.tick(c, 1000, Buildings)
check("滿倉卡在上限", c.Inventory.Ore, CAP)
Build.tick(c, 1000, Buildings)
check("滿倉不溢出", c.Inventory.Ore, CAP)

-- 通過 Migrate 後的新存檔格式能被 Build 使用
check("新存檔 N=12", Migrate.newPlayerData().Planet.N, 12)

-- 新手流程不卡關:全新存檔 → 蓋礦機+太陽能板 → 會開始產礦
local n = Migrate.newPlayerData()
check("新手蓋礦機", Build.place(n, "1_0_0", "Miner", Buildings), true)
check("新手蓋太陽能板", Build.place(n, "1_1_0", "SolarPanel", Buildings), true)
local ore0 = n.Inventory.Ore
Build.tick(n, 5, Buildings)
check("新手 5 秒後有產礦", n.Inventory.Ore - ore0, 5)

-- 新手完整路徑不死結:礦機+太陽能板+時空門都蓋得起,電力剛好滿足,且付得起第一次穿梭(Ore 10)
local Warp = require("Warp")
local Energy = require("Energy")
local st = Migrate.newPlayerData()
check("新手蓋礦機", Build.place(st, "1_0_0", "Miner", Buildings), true)
check("新手蓋太陽能板", Build.place(st, "1_1_0", "SolarPanel", Buildings), true)
check("新手蓋時空門", Build.place(st, "1_2_0", "WarpGate", Buildings), true)
check("電力滿足率=1", Energy.balance(Build.placedList(st), Buildings).satisfaction, 1)
check("付得起第一次穿梭", Inventory.canAfford(st.Inventory, Warp.cost), true)
