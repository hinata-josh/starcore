--!strict
-- 裂縫降落點(純邏輯):怪獸要往「防禦建築蓋得最密集的地方」降落 —— 玩家把防線集中在哪,戰鬥就在哪,
-- 看得到砲台火力、也逼玩家思考布陣。
-- 作法:每座防禦建築(攻擊/防禦類)當候選中心,算 RADIUS_DEG 度內的防禦建築權重(等級越高越重),
-- 取分數最高的那群,降落點 = 群內建築方向的加權平均。沒有防禦建築就看全部建築;都沒有就用預設方向。
-- 分數相同時取 key 字典序最小者,保證每次結果一樣(伺服器、中央螢幕、測試一致)。

local CubeSphere = require(script.Parent.CubeSphere)

local RiftTarget = {}

RiftTarget.RADIUS_DEG = 30
RiftTarget.DEFAULT_DIR = { x = 0.9438798, y = 0.3303579, z = 0 } -- 舊版固定方向 (1, 0.35, 0) 正規化
RiftTarget.DEFENSE = { Attack = true, Defense = true }

export type Vec = { x: number, y: number, z: number }
export type Target = { dir: Vec, key: string?, count: number, source: string }

local function norm(v: Vec): Vec
	local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	if l < 1e-9 then
		return RiftTarget.DEFAULT_DIR
	end
	return { x = v.x / l, y = v.y / l, z = v.z / l }
end

-- slots = data.Planet.Slots({ [key] = { Id, Lv } });n = 每面格數;defs = Data/Buildings
function RiftTarget.pick(slots: { [string]: any }, n: number, defs: any): Target
	local cat: { [string]: string } = {}
	for _, d in defs.Types do
		cat[d.id] = d.category
	end
	local function collect(onlyDefense: boolean)
		local list = {}
		for key, s in slots do
			if not onlyDefense or RiftTarget.DEFENSE[cat[s.Id] or ""] then
				local slot = CubeSphere.parseKey(key, n)
				if slot then
					table.insert(list, { key = key, dir = CubeSphere.direction(slot.face, slot.u, slot.v, n), w = s.Lv or 1 })
				end
			end
		end
		table.sort(list, function(a, b)
			return a.key < b.key
		end)
		return list
	end
	local list = collect(true)
	local source = "defense"
	if #list == 0 then
		list = collect(false)
		source = "any"
	end
	if #list == 0 then
		return { dir = RiftTarget.DEFAULT_DIR, key = nil, count = 0, source = "default" }
	end

	local cosR = math.cos(math.rad(RiftTarget.RADIUS_DEG))
	local best, bestScore = list[1], -1
	for _, c in list do
		local score = 0
		for _, o in list do
			if c.dir.x * o.dir.x + c.dir.y * o.dir.y + c.dir.z * o.dir.z >= cosR then
				score += o.w
			end
		end
		if score > bestScore then -- 嚴格大於:同分保留 key 較小的(list 已排序)
			best, bestScore = c, score
		end
	end
	local sum = { x = 0, y = 0, z = 0 }
	local count = 0
	for _, o in list do
		if best.dir.x * o.dir.x + best.dir.y * o.dir.y + best.dir.z * o.dir.z >= cosR then
			sum.x += o.dir.x * o.w
			sum.y += o.dir.y * o.w
			sum.z += o.dir.z * o.w
			count += 1
		end
	end
	return { dir = norm(sum), key = best.key, count = count, source = source }
end

return RiftTarget
