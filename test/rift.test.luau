local RT = require("RiftTarget")
local CS = require("CubeSphere")
local Buildings = require("Buildings")
local N = 12

local function dirOf(key)
	local s = CS.parseKey(key, N)
	return CS.direction(s.face, s.u, s.v, N)
end
local function dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

-- 1. 什麼都沒蓋 → 預設方向
local t = RT.pick({}, N, Buildings)
check("空星球:來源 default", t.source, "default")
check("空星球:預設方向", t.dir.x, RT.DEFAULT_DIR.x)

-- 2. 只有能源建築 → 退回看全部建築
t = RT.pick({ ["3_5_5"] = { Id = "SolarPanel", Lv = 1 } }, N, Buildings)
check("只有能源:來源 any", t.source, "any")
check("只有能源:落在那座建築", dot(t.dir, dirOf("3_5_5")) > 0.999, true)

-- 3. 一群砲台(北極,4 座)+ 一座孤立砲台(南極)+ 很多能源(赤道) → 落在北極那群
local slots = {
	["3_5_5"] = { Id = "PulseTurret", Lv = 1 },
	["3_6_5"] = { Id = "PulseTurret", Lv = 1 },
	["3_5_6"] = { Id = "CryoTurret", Lv = 1 },
	["3_6_6"] = { Id = "PulseTurret", Lv = 1 },
	["4_5_5"] = { Id = "PulseTurret", Lv = 1 },
}
for u = 0, 9 do
	slots["1_" .. u .. "_5"] = { Id = "SolarPanel", Lv = 1 }
end
t = RT.pick(slots, N, Buildings)
check("砲台群:來源 defense", t.source, "defense")
check("砲台群:群內 4 座", t.count, 4)
check("砲台群:降落點在北半球上方", t.dir.y > 0.95, true)
check("砲台群:落點是單位向量", math.abs(dot(t.dir, t.dir) - 1) < 1e-9, true)

-- 4. 等級加權:南極 2 座 Lv3(權重 6)勝過北極 3 座 Lv1(權重 3)
t = RT.pick({
	["3_5_5"] = { Id = "PulseTurret", Lv = 1 },
	["3_6_5"] = { Id = "PulseTurret", Lv = 1 },
	["3_5_6"] = { Id = "PulseTurret", Lv = 1 },
	["4_5_5"] = { Id = "PulseTurret", Lv = 3 },
	["4_6_5"] = { Id = "PulseTurret", Lv = 3 },
}, N, Buildings)
check("等級加權:落在南極", t.dir.y < -0.95, true)

-- 5. 確定性:同樣輸入跑兩次結果一樣(同分時取 key 最小)
local a = RT.pick({ ["1_5_5"] = { Id = "PulseTurret", Lv = 1 }, ["2_5_5"] = { Id = "PulseTurret", Lv = 1 } }, N, Buildings)
local b = RT.pick({ ["2_5_5"] = { Id = "PulseTurret", Lv = 1 }, ["1_5_5"] = { Id = "PulseTurret", Lv = 1 } }, N, Buildings)
check("同分:選 key 較小的", a.key, "1_5_5")
check("確定性:兩次一樣", a.dir.x == b.dir.x and a.dir.y == b.dir.y and a.dir.z == b.dir.z, true)

-- 6. 壞掉的 key 被忽略、不會出錯
t = RT.pick({ ["bad"] = { Id = "PulseTurret", Lv = 1 }, ["9_0_0"] = { Id = "PulseTurret", Lv = 1 } }, N, Buildings)
check("壞 key:退回預設", t.source, "default")
