--!strict
-- 星球擴建:升到第 N 級的花費(每級換不同的材料,越後面越需要別的星球的稀有資源)。
-- capacity(level) = BASE_CAPACITY + PER_LEVEL × (level-1) 個建築格;等級同時提高存量上限與星核血量。

local PlanetLevels = {
	DataVersion = 1,
	MaxLevel = 10,
	BASE_CAPACITY = 15,
	PER_LEVEL = 8,
	Cost = {
		[2] = { Ore = 100, Metal = 20 },
		[3] = { Metal = 50, Sand = 40, Copper = 20 },
		[4] = { Titanium = 20, Silicon = 30, Water = 40 },
		[5] = { Crystal = 30, Sulfur = 30, Coal = 60 },
		[6] = { Amber = 30, Glowstone = 15, Titanium = 40 },
		[7] = { LavaCore = 20, Plasma = 5, Copper = 60 },
		[8] = { RareGas = 25, Stardust = 5, Silicon = 60 },
		[9] = { DarkMatter = 5, Plasma = 10, Titanium = 80 },
		[10] = { DarkMatter = 10, Stardust = 15, Glowstone = 40 },
	},
}

function PlanetLevels.capacity(level: number): number
	return PlanetLevels.BASE_CAPACITY + PlanetLevels.PER_LEVEL * (level - 1)
end

return PlanetLevels
