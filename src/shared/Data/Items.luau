--!strict
-- 資源/物品定義(共 20 種)。weight = 背包載重;rarity 決定母星自產速率倍率(rate)。
-- 母星只會隨機擁有其中 5 種(其中 2 種高產),其餘必須穿梭到別的星球採集(見 Logic/HomePlanet)。

local Items = {
	DataVersion = 2,
	Types = {
		-- 常見
		{ id = "Ore", name = "礦石", weight = 1, rarity = "common", rate = 1 },
		{ id = "Metal", name = "金屬", weight = 2, rarity = "common", rate = 1 },
		{ id = "Ice", name = "冰", weight = 1, rarity = "common", rate = 1 },
		{ id = "Biomass", name = "生質", weight = 1, rarity = "common", rate = 1 },
		{ id = "Scrap", name = "廢料零件", weight = 1, rarity = "common", rate = 1 },
		{ id = "Sand", name = "沙", weight = 1, rarity = "common", rate = 1 },
		{ id = "Water", name = "水", weight = 1, rarity = "common", rate = 1 },
		{ id = "Coal", name = "煤", weight = 1, rarity = "common", rate = 1 },
		-- 少見
		{ id = "Copper", name = "銅", weight = 2, rarity = "uncommon", rate = 0.7 },
		{ id = "Silicon", name = "矽", weight = 2, rarity = "uncommon", rate = 0.7 },
		{ id = "Sulfur", name = "硫磺", weight = 2, rarity = "uncommon", rate = 0.7 },
		{ id = "Amber", name = "琥珀", weight = 2, rarity = "uncommon", rate = 0.7 },
		{ id = "Titanium", name = "鈦", weight = 3, rarity = "uncommon", rate = 0.7 },
		-- 稀有
		{ id = "Crystal", name = "能量晶體", weight = 2, rarity = "rare", rate = 0.45 },
		{ id = "LavaCore", name = "熔岩核心", weight = 3, rarity = "rare", rate = 0.45 },
		{ id = "Glowstone", name = "螢光石", weight = 2, rarity = "rare", rate = 0.45 },
		{ id = "RareGas", name = "稀有氣體", weight = 2, rarity = "rare", rate = 0.45 },
		-- 傳說
		{ id = "Plasma", name = "電漿", weight = 3, rarity = "epic", rate = 0.2 },
		{ id = "Stardust", name = "星塵", weight = 3, rarity = "epic", rate = 0.2 },
		{ id = "DarkMatter", name = "暗物質", weight = 4, rarity = "epic", rate = 0.2 },
	},
}

return Items
