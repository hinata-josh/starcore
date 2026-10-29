--!strict
-- 可重現的亂數(seed 相同 → 序列相同)。星球生成、怪獸組成都靠它,伺服器與測試結果一致。
-- 用 LCG,乘積 < 2^53 不會失精度。

local Rng = {}
Rng.__index = Rng

local MOD = 4294967296

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number): Rng
	-- 連續的 seed 直接進 LCG,第一個輸出幾乎一樣(差 0.0004)→ 先打散再暖機
	local self = setmetatable({ state = (math.floor(seed) * 2654435 + 97531) % MOD }, Rng)
	for _ = 1, 8 do
		Rng.next(self)
	end
	return self
end

-- [0, 1)
function Rng.next(self: Rng): number
	self.state = (self.state * 1664525 + 1013904223) % MOD
	return self.state / MOD
end

-- lo..hi 的整數(含兩端)
function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(Rng.next(self) * (hi - lo + 1))
end

-- 依 weight 欄位加權抽選
function Rng.weighted<T>(self: Rng, list: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, item in list do
		total += weightOf(item)
	end
	local roll = Rng.next(self) * total
	for _, item in list do
		roll -= weightOf(item)
		if roll < 0 then
			return item
		end
	end
	return list[#list]
end

return Rng
