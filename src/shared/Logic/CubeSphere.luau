--!strict
-- 球面格位數學(純 Luau,不碰 Roblox API,可離線測試)
-- 立方體展開成球:6 面 × N × N 格。格位邏輯座標 (face, u, v),u/v ∈ [0, N-1]。
-- 向量一律用 {x=,y=,z=} 純表,轉 Roblox 時再包成 Vector3。

export type Vec = { x: number, y: number, z: number }
export type Slot = { face: number, u: number, v: number }

local CubeSphere = {}

-- n=面法線,a/b=該面的兩個切線軸
local FACES = {
	{ n = { x = 1, y = 0, z = 0 }, a = { x = 0, y = 0, z = -1 }, b = { x = 0, y = 1, z = 0 } },
	{ n = { x = -1, y = 0, z = 0 }, a = { x = 0, y = 0, z = 1 }, b = { x = 0, y = 1, z = 0 } },
	{ n = { x = 0, y = 1, z = 0 }, a = { x = 1, y = 0, z = 0 }, b = { x = 0, y = 0, z = -1 } },
	{ n = { x = 0, y = -1, z = 0 }, a = { x = 1, y = 0, z = 0 }, b = { x = 0, y = 0, z = 1 } },
	{ n = { x = 0, y = 0, z = 1 }, a = { x = 1, y = 0, z = 0 }, b = { x = 0, y = 1, z = 0 } },
	{ n = { x = 0, y = 0, z = -1 }, a = { x = -1, y = 0, z = 0 }, b = { x = 0, y = 1, z = 0 } },
}

local QUARTER_PI = math.pi / 4

local function dot(p: Vec, q: Vec): number
	return p.x * q.x + p.y * q.y + p.z * q.z
end

local function normalize(p: Vec): Vec
	local len = math.sqrt(dot(p, p))
	return { x = p.x / len, y = p.y / len, z = p.z / len }
end

function CubeSphere.slotCount(n: number): number
	return 6 * n * n
end

-- 格位中心的單位方向(用 tan 修正,讓各格大小接近一致)
function CubeSphere.direction(face: number, u: number, v: number, n: number): Vec
	local f = FACES[face]
	local s = math.tan((2 * (u + 0.5) / n - 1) * QUARTER_PI)
	local t = math.tan((2 * (v + 0.5) / n - 1) * QUARTER_PI)
	return normalize({
		x = f.n.x + f.a.x * s + f.b.x * t,
		y = f.n.y + f.a.y * s + f.b.y * t,
		z = f.n.z + f.a.z * s + f.b.z * t,
	})
end

function CubeSphere.position(face: number, u: number, v: number, n: number, radius: number): Vec
	local d = CubeSphere.direction(face, u, v, n)
	return { x = d.x * radius, y = d.y * radius, z = d.z * radius }
end

-- 反查:任意方向 → 所屬格位
function CubeSphere.fromDirection(dir: Vec, n: number): Slot
	local ax, ay, az = math.abs(dir.x), math.abs(dir.y), math.abs(dir.z)
	local face
	if ax >= ay and ax >= az then
		face = dir.x >= 0 and 1 or 2
	elseif ay >= az then
		face = dir.y >= 0 and 3 or 4
	else
		face = dir.z >= 0 and 5 or 6
	end
	local f = FACES[face]
	local dn = dot(dir, f.n)
	local s = math.atan(dot(dir, f.a) / dn) / QUARTER_PI
	local t = math.atan(dot(dir, f.b) / dn) / QUARTER_PI
	local u = math.clamp(math.floor((s + 1) / 2 * n), 0, n - 1)
	local v = math.clamp(math.floor((t + 1) / 2 * n), 0, n - 1)
	return { face = face, u = u, v = v }
end

-- 上下左右四個鄰格(跨面也能找到)
function CubeSphere.neighbors(face: number, u: number, v: number, n: number): { Slot }
	local f = FACES[face]
	local result = {}
	for _, step in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local s = math.tan((2 * (u + step[1] + 0.5) / n - 1) * QUARTER_PI)
		local t = math.tan((2 * (v + step[2] + 0.5) / n - 1) * QUARTER_PI)
		local p = {
			x = f.n.x + f.a.x * s + f.b.x * t,
			y = f.n.y + f.a.y * s + f.b.y * t,
			z = f.n.z + f.a.z * s + f.b.z * t,
		}
		table.insert(result, CubeSphere.fromDirection(normalize(p), n))
	end
	return result
end

function CubeSphere.key(face: number, u: number, v: number): string
	return face .. "_" .. u .. "_" .. v
end

function CubeSphere.parseKey(key: string, n: number): Slot?
	local f, u, v = string.match(key, "^(%d+)_(%d+)_(%d+)$")
	if not f then
		return nil
	end
	local face, uu, vv = tonumber(f) :: number, tonumber(u) :: number, tonumber(v) :: number
	if face < 1 or face > 6 or uu >= n or vv >= n then
		return nil
	end
	return { face = face, u = uu, v = vv }
end

-- 格位邊長約 cell studs 時,N 格的球半徑
function CubeSphere.radiusFor(n: number, cell: number): number
	return n * cell * 2 / math.pi
end

return CubeSphere
