--!strict
-- 穿梭目的地類型(10 種,涵蓋全部 20 種資源;每種至少一種資源)。改數值時 DataVersion +1。
-- resources:可採集的資源 id 與豐富度範圍。

local Planets = {
	DataVersion = 2,
	Types = {
		{ id = "Rock", name = "岩石星", weight = 22, minWarp = 1, radius = { 60, 90 }, hazard = "None",
			resources = { { id = "Ore", min = 20, max = 40 }, { id = "Metal", min = 8, max = 18 }, { id = "Copper", min = 5, max = 12 } } },
		{ id = "Ice", name = "冰封星", weight = 14, minWarp = 1, radius = { 60, 100 }, hazard = "Cold",
			resources = { { id = "Ice", min = 20, max = 40 }, { id = "Water", min = 15, max = 30 } } },
		{ id = "Crystal", name = "晶體星", weight = 11, minWarp = 1, radius = { 50, 80 }, hazard = "Resonance",
			resources = { { id = "Crystal", min = 8, max = 20 }, { id = "Silicon", min = 8, max = 18 } } },
		{ id = "Desert", name = "沙漠星", weight = 12, minWarp = 1, radius = { 70, 110 }, hazard = "Heat",
			resources = { { id = "Sand", min = 20, max = 40 }, { id = "Amber", min = 5, max = 14 } } },
		{ id = "Lava", name = "熔岩星", weight = 9, minWarp = 2, radius = { 60, 100 }, hazard = "Burn",
			resources = { { id = "LavaCore", min = 6, max = 16 }, { id = "Sulfur", min = 8, max = 18 } } },
		{ id = "Forest", name = "森林星", weight = 10, minWarp = 2, radius = { 70, 110 }, hazard = "None",
			resources = { { id = "Biomass", min = 20, max = 40 }, { id = "Coal", min = 15, max = 30 } } },
		{ id = "Debris", name = "殘骸帶", weight = 8, minWarp = 2, radius = { 40, 70 }, hazard = "FloatingPlatforms",
			resources = { { id = "Scrap", min = 15, max = 35 }, { id = "Titanium", min = 4, max = 10 } } },
		{ id = "Cavern", name = "螢光洞窟星", weight = 6, minWarp = 3, radius = { 60, 90 }, hazard = "Dark",
			resources = { { id = "Glowstone", min = 5, max = 12 }, { id = "Water", min = 10, max = 20 } } },
		{ id = "GasGiant", name = "氣態巨星", weight = 5, minWarp = 3, radius = { 90, 130 }, hazard = "StationOnly",
			resources = { { id = "RareGas", min = 5, max = 12 }, { id = "Plasma", min = 2, max = 6 } } },
		{ id = "Nebula", name = "星雲裂隙", weight = 3, minWarp = 4, radius = { 50, 90 }, hazard = "HighRisk",
			resources = { { id = "DarkMatter", min = 2, max = 6 }, { id = "Stardust", min = 3, max = 8 } } },
	},
}

return Planets
