--!strict
-- 依 seed 產生穿梭目的地。同 seed + 同 warpLevel → 永遠同一顆星球(好友同行才會看到一樣的)。
-- 資料表由呼叫端傳入(planets = require(Data.Planets)),本模組不依賴其他模組,方便離線測試。

local Rng = require(script.Parent.Rng)

local PlanetGen = {}

export type Resource = { id: string, amount: number }
export type Planet = {
	seed: number,
	typeId: string,
	radius: number,
	hazard: string,
	resources: { Resource },
}

-- forceType:指定類型(新手第一次穿梭保證去岩石星,確保拿到金屬)
function PlanetGen.generate(seed: number, warpLevel: number, planets: any, forceType: string?): Planet
	local rng = Rng.new(seed)
	local candidates = {}
	for _, t in planets.Types do
		if t.minWarp <= warpLevel and (forceType == nil or t.id == forceType) then
			table.insert(candidates, t)
		end
	end
	local t = Rng.weighted(rng, candidates, function(c)
		return c.weight
	end)
	local resources = {}
	for _, r in t.resources do
		table.insert(resources, { id = r.id, amount = Rng.int(rng, r.min, r.max) })
	end
	return {
		seed = seed,
		typeId = t.id,
		radius = Rng.int(rng, t.radius[1], t.radius[2]),
		hazard = t.hazard,
		resources = resources,
	}
end

return PlanetGen
