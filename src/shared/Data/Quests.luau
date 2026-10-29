--!strict
-- 任務鏈(新手引導 + 長期目標)。完成即自動發獎勵。
-- event:build(match 建築 id) / trip(完成穿梭) / waveWon(守住波次) / upgrade(升級建築) / warpUp(時空門升級)
-- 一般任務累計 target 次;waveWon 且 atLeast=true 表示「打到第 N 波」(arg 為波數)。
-- friendGather(在好友的星球採集)。optional=true 的是「選做任務」:不擋主線(沒有好友也能繼續),另外顯示在主線下面。

local Quests = {
	DataVersion = 1,
	Chain = {
		{ id = "q_miner", text = "蓋一座礦機,開始採礦", event = "build", match = "Miner", target = 1, reward = { Ore = 20 } },
		{ id = "q_solar", text = "蓋太陽能板給礦機供電", event = "build", match = "SolarPanel", target = 1, reward = { Ore = 20 } },
		{ id = "q_friend", text = "傳送到好友的星球採集一次", event = "friendGather", target = 1, reward = { Ore = 40, Metal = 10 }, optional = true },
		{ id = "q_trip1", text = "第一次時空穿梭,帶資源回家", event = "trip", target = 1, reward = { Metal = 15 } },
		{ id = "q_turret", text = "再蓋一座脈衝砲台,加強基地防線", event = "build", match = "PulseTurret", target = 1, reward = { Ore = 40 } },
		{ id = "q_wave1", text = "守住第一波裂縫怪獸", event = "waveWon", target = 1, atLeast = true, reward = { Metal = 20, Crystal = 5 } },
		{ id = "q_upgrade", text = "把任一座建築升到 Lv2", event = "upgrade", target = 1, reward = { Ore = 60 } },
		{ id = "q_trip5", text = "完成 5 次穿梭", event = "trip", target = 5, reward = { Crystal = 10 } },
		{ id = "q_wave5", text = "擊退第一隻裂縫巨獸(第 5 波)", event = "waveWon", target = 5, atLeast = true, reward = { Crystal = 20, Metal = 30 } },
		{ id = "q_warp2", text = "把時空門升到 Lv2", event = "warpUp", target = 2, atLeast = true, reward = { Crystal = 15, Metal = 20 } },
		{ id = "q_shield", text = "蓋一座能量護盾", event = "build", match = "EnergyShield", target = 1, reward = { Ore = 80 } },
		{ id = "q_wave10", text = "守住第 10 波", event = "waveWon", target = 10, atLeast = true, reward = { Crystal = 40, Metal = 60 } },
		{ id = "q_trip20", text = "完成 20 次穿梭", event = "trip", target = 20, reward = { Crystal = 30 } },
		{ id = "q_wave20", text = "守住第 20 波 — 傳奇守護者", event = "waveWon", target = 20, atLeast = true, reward = { DarkMatter = 5, Crystal = 80 } },
	},
}

return Quests
