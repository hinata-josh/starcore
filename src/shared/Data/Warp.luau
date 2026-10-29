--!strict
-- 時空穿梭設定。平衡調整只改這裡,DataVersion +1。

local Warp = {
	DataVersion = 1,
	cost = {}, -- 每次跳躍的花費:免費。試玩發現收費(礦石)會讓母星沒礦石的玩家卡死;節奏改由「採集間隔/20次冷卻」(Logic/Gather)控制
	durationSec = 210, -- 空間不穩定倒數(約 3.5 分鐘)
	capacityByLevel = { 90, 130, 180, 240 }, -- 依 WarpLv 的載重上限(採集間隔拉長後,每次採集拿一大份)
	overloadFactor = 1.5, -- 最多可撿到載重的 1.5 倍(貪心空間)
	overflowKeep = 0.5, -- 時間到被強制拉回:超出載重的部分只保留 50%
	nodeSize = 40, -- 每個資源點的資源量(約)——採集間隔拉長後,一次採一個點拿一大份
	gatherPerAction = 40, -- 每次採集拿幾個(受載重上限限制)
	-- 時空門升級:Lv→Lv+1 的花費(解鎖更遠的星球與更大載重;每種資源都有出路)
	upgradeCost = {
		[2] = { Metal = 30, Crystal = 15, Silicon = 10 },
		[3] = { Crystal = 30, Copper = 30, Sulfur = 15, Water = 20 },
		[4] = { RareGas = 15, Titanium = 20, Glowstone = 10, Stardust = 5 },
	},
	gatherRange = 14, -- 採集有效距離(studs)
}

return Warp
