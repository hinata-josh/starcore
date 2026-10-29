local CS = require("CubeSphere")
local N = 12

check("格位總數", CS.slotCount(N), 6 * 12 * 12)

-- 1. 方向為單位向量;2. 往返 direction → fromDirection 回到同格(全部 864 格)
local roundtrip, unit = 0, 0
local seen = {}
for face = 1, 6 do
	for u = 0, N - 1 do
		for v = 0, N - 1 do
			local d = CS.direction(face, u, v, N)
			if math.abs(d.x * d.x + d.y * d.y + d.z * d.z - 1) < 1e-9 then unit += 1 end
			local s = CS.fromDirection(d, N)
			if s.face == face and s.u == u and s.v == v then roundtrip += 1 end
			seen[CS.key(face, u, v)] = true
		end
	end
end
check("方向皆為單位向量", unit, 864)
check("格位往返一致", roundtrip, 864)

-- 3. 各格位置互不重疊:最近兩格中心距離 > 0 且各格大小接近(最大/最小邊長比 < 1.6)
local R = CS.radiusFor(N, 12)
local minD, maxD = 1e9, 0
for face = 1, 6 do
	for u = 0, N - 2 do
		for v = 0, N - 2 do
			local a = CS.position(face, u, v, N, R)
			local b = CS.position(face, u + 1, v, N, R)
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
			minD = math.min(minD, d)
			maxD = math.max(maxD, d)
		end
	end
end
check("格距大小比 < 1.6", maxD / minD < 1.6, true)
check("平均格距約 12 studs(±25%)", math.abs((minD + maxD) / 2 - 12) < 3, true)

-- 4. 鄰格:每格 4 個、互不相同、且不含自己
local bad = 0
for face = 1, 6 do
	for u = 0, N - 1 do
		for v = 0, N - 1 do
			local nb = CS.neighbors(face, u, v, N)
			local set = {}
			local cnt = 0
			for _, s in nb do
				local k = CS.key(s.face, s.u, s.v)
				if k ~= CS.key(face, u, v) and not set[k] then
					set[k] = true
					cnt += 1
				end
			end
			if cnt ~= 4 then bad += 1 end
		end
	end
end
check("每格有 4 個不同鄰格", bad, 0)

-- 5. 鄰格對稱(A 的鄰居含 B ⇒ B 的鄰居含 A),跨面也要成立
local asym = 0
for face = 1, 6 do
	for u = 0, N - 1 do
		for v = 0, N - 1 do
			for _, s in CS.neighbors(face, u, v, N) do
				local back = false
				for _, t in CS.neighbors(s.face, s.u, s.v, N) do
					if t.face == face and t.u == u and t.v == v then back = true end
				end
				if not back then asym += 1 end
			end
		end
	end
end
print("鄰格不對稱數:" .. asym)
check("鄰格對稱", asym, 0)

-- 6. key 解析
local s = CS.parseKey("3_5_7", N)
check("parseKey 面", s.face, 3)
check("parseKey u", s.u, 5)
check("parseKey 非法(越界)", CS.parseKey("3_12_0", N), nil)
check("parseKey 非法(格式)", CS.parseKey("abc", N), nil)
