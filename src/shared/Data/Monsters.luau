--!strict
-- 怪獸資料表。cost = 組波時消耗的「強度預算」;unlockWave = 第幾波起會出現。

local Monsters = {
	DataVersion = 1,
	Types = {
		{ id = "AcidWorm", name = "酸液蟲", element = "Acid", cost = 20, hp = 60, dmg = 6, travel = 14, unlockWave = 1 },
		{ id = "Behemoth", name = "巨甲獸", element = "Physical", cost = 60, hp = 220, dmg = 22, travel = 20, unlockWave = 3 },
		{ id = "BladeMoth", name = "飛行刃蛾", element = "Air", cost = 35, hp = 90, dmg = 11, travel = 8, unlockWave = 5 },
		{ id = "PlasmaDrake", name = "電漿幼龍", element = "Energy", cost = 80, hp = 260, dmg = 34, travel = 16, unlockWave = 8 },
	},
	-- 每 bossEvery 波出現一次裂縫巨獸
	Boss = { id = "RiftTitan", name = "裂縫巨獸", bossEvery = 5, budgetShare = 0.5, hpPerBudget = 4.0, dmgPerBudget = 0.18, travel = 25 },
	spawnGap = 2.5, -- 怪獸依序從裂縫降落的間隔(秒)
}

return Monsters
