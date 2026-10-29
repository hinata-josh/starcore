--!strict
-- 中央螢幕的 2D 星球開發地圖(純邏輯)。
-- 球面 6 個面各是 N×N 格,攤成十字形的「展開圖」:
--            [ 北極 ]
--   [ 左 ]   [ 前 ]   [ 右 ]   [ 後 ]
--            [ 南極 ]
-- 每面之間留 1 格間隙,方便看出是不同的面。面內座標直接用 (u, v),不保證跨面接縫連續(面板上有標籤)。

local CubeSphere = require(script.Parent.CubeSphere)
local Energy = require(script.Parent.Energy)
local Combat = require(script.Parent.Combat)

local MapView = {}

-- face → { col, row }(以「面」為單位的十字展開位置)
-- 面編號:1=+X 右、2=-X 左、3=+Y 北極、4=-Y 南極、5=+Z 前、6=-Z 後
MapView.FACE_POS = {
	[1] = { 2, 1 },
	[2] = { 0, 1 },
	[3] = { 1, 0 },
	[4] = { 1, 2 },
	[5] = { 1, 1 },
	[6] = { 3, 1 },
}
MapView.FACE_NAME = { [1] = "右", [2] = "左", [3] = "北極", [4] = "南極", [5] = "前", [6] = "後" }
MapView.GAP = 1

-- 整張地圖的格數寬高
function MapView.size(n: number): (number, number)
	local g = MapView.GAP
	return 4 * n + 3 * g, 3 * n + 2 * g
end

-- 某個面左上角在地圖上的格座標
function MapView.faceOrigin(face: number, n: number): (number, number)
	local p = MapView.FACE_POS[face]
	return p[1] * (n + MapView.GAP), p[2] * (n + MapView.GAP)
end

-- 格位 → 地圖格座標 (x, y)(都從 0 開始)
function MapView.cellOf(face: number, u: number, v: number, n: number): (number, number)
	local ox, oy = MapView.faceOrigin(face, n)
	return ox + u, oy + (n - 1 - v) -- v 向上 → y 向下,地圖上方才是「上」
end

-- 建築類別 → 顏色代碼(UI 用;純邏輯裡只存名稱)
MapView.KIND_OF_CATEGORY = {
	Energy = "energy", Collect = "collect", Storage = "storage", Attack = "attack",
	Defense = "defense", Support = "support", Tech = "tech",
}

export type Cell = { x: number, y: number, kind: string, id: string, lv: number, key: string }

-- 已蓋的建築 → 地圖格(稀疏:只列有建築的格)
function MapView.cells(slots: { [string]: any }, n: number, defs: any): { Cell }
	local byId = {}
	for _, d in defs.Types do
		byId[d.id] = d
	end
	local out: { Cell } = {}
	for key, s in slots do
		local slot = CubeSphere.parseKey(key, n)
		if slot then
			local x, y = MapView.cellOf(slot.face, slot.u, slot.v, n)
			local id = if type(s) == "table" then s.Id else s
			local lv = if type(s) == "table" then (s.Lv or 1) else 1
			local d = byId[id]
			table.insert(out, {
				x = x, y = y, key = key, id = id, lv = lv,
				kind = if d then (MapView.KIND_OF_CATEGORY[d.category] or "other") else "other",
			})
		end
	end
	return out
end

-- 裂縫降落點(怪獸入侵方向)在地圖上的格座標
function MapView.riftCell(riftDir: { x: number, y: number, z: number }, n: number): (number, number)
	local len = math.sqrt(riftDir.x ^ 2 + riftDir.y ^ 2 + riftDir.z ^ 2)
	local s = CubeSphere.fromDirection({ x = riftDir.x / len, y = riftDir.y / len, z = riftDir.z / len }, n)
	return MapView.cellOf(s.face, s.u, s.v, n)
end

-- 面板上的文字摘要(建築數/容量、電力、火力、護盾、牆、星核、各類別數量)
function MapView.summary(planet: any, defs: any, levels: any): any
	local placed = {}
	local byKind: { [string]: number } = {}
	local byId = {}
	for _, d in defs.Types do
		byId[d.id] = d
	end
	local used = 0
	for _, s in planet.Slots do
		local id = if type(s) == "table" then s.Id else s
		local lv = if type(s) == "table" then (s.Lv or 1) else 1
		table.insert(placed, { id = id, lv = lv })
		used += 1
		local d = byId[id]
		local kind = if d then (MapView.KIND_OF_CATEGORY[d.category] or "other") else "other"
		byKind[kind] = (byKind[kind] or 0) + 1
	end
	local power = Energy.balance(placed, defs)
	local def = Combat.defenseOf(placed, defs, planet.Level)
	return {
		used = used, capacity = levels.capacity(planet.Level), level = planet.Level,
		generation = power.generation, demand = power.demand, satisfaction = power.satisfaction,
		dps = def.dps, shield = def.shield, wallHp = def.wallHp, coreHp = def.coreHp,
		byKind = byKind,
	}
end

return MapView
