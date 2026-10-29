--!strict
-- 存檔結構與版本遷移。每次改存檔欄位:CURRENT +1 並新增一個 steps[舊版本] 函式,另補測試。

local Starter = require(script.Parent.Starter)

local Migrate = {}

Migrate.CURRENT = 6

function Migrate.newPlayerData(): any
	return {
		Version = Migrate.CURRENT,
		Planet = { Level = 1, N = 12, Slots = {} }, -- Slots: ["f_u_v"] = {Id=, Lv=, Hp=}
		Inventory = { Ore = 150, Metal = 40, Scrap = 20, Sand = 20, Water = 20, Coal = 20 }, -- 起始包:夠蓋教學四件,並有幾種基礎資源可以先試別的建築
		Tech = { WarpLv = 1 },
		Wave = { Index = 1, BossDefeated = false, Losses = 0 }, -- Losses:連敗次數(連敗減壓用)
		Settings = { Mode = "Explorer", Lang = "zh-TW" },
		Stats = { Trips = 0, WavesWon = 0, WavesLost = 0 },
		Quests = { Done = {}, Claimed = {} },
		Daily = { Streak = 0, LastDay = 0 },
		LastSeen = 0, -- os.time();離線收益用
		Gather = { LastAt = 0, Counts = {}, CooldownUntil = {} }, -- 採集間隔/冷卻(見 Logic/Gather)
		Friends = {}, -- 只做顯示快取,以 Roblox 好友清單為準(見計畫書 §6.6)
	}
end

local steps: { [number]: (any) -> () } = {
	-- v5 → v6:時空門改成直接送(沒有的補一座;好友才能馬上用主人的門穿梭)
	[5] = function(data)
		Starter.grant(data)
	end,
	-- v4 → v5:老玩家補送指揮中心 + 脈衝砲台(新玩家由 DataService 建檔時送)
	[4] = function(data)
		Starter.grant(data)
	end,
	-- v3 → v4:新增採集間隔/冷卻
	[3] = function(data)
		data.Gather = data.Gather or { LastAt = 0, Counts = {}, CooldownUntil = {} }
		if data.Wave and data.Wave.Losses == nil then
			data.Wave.Losses = 0
		end
	end,
	-- v2 → v3:新增統計/任務/每日/離線時間
	[2] = function(data)
		data.Stats = data.Stats or { Trips = 0, WavesWon = 0, WavesLost = 0 }
		data.Quests = data.Quests or { Done = {}, Claimed = {} }
		data.Daily = data.Daily or { Streak = 0, LastDay = 0 }
		data.LastSeen = data.LastSeen or 0
	end,
	-- v1 → v2:新增 Friends 欄位
	[1] = function(data)
		data.Friends = data.Friends or {}
	end,
}

-- 就地遷移到 CURRENT;回傳是否有變動
function Migrate.run(data: any): boolean
	local from = data.Version or 1
	if from > Migrate.CURRENT then
		error("存檔版本 " .. from .. " 比程式新(" .. Migrate.CURRENT .. "),拒絕覆寫")
	end
	local changed = false
	while from < Migrate.CURRENT do
		local step = steps[from]
		if not step then
			error("缺少 v" .. from .. " 的遷移步驟")
		end
		step(data)
		from += 1
		data.Version = from
		changed = true
	end
	return changed
end

return Migrate
