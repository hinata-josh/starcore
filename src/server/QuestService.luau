--!strict
-- 任務/每日/離線收益的伺服器端接口。其他服務在事件發生時呼叫 QuestService.notify。
-- 登入流程(由 PlanetService 在主人載入後呼叫 welcome):離線收益 → 每日獎勵 → 目前任務。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Quest = require(Shared.Logic.Quest)
local Daily = require(Shared.Logic.Daily)
local Build = require(Shared.Logic.Build)
local Quests = require(Shared.Data.Quests)
local Buildings = require(Shared.Data.Buildings)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)

local noticeEv = Remotes.get("Notice")
local stateEv = Remotes.get("StateChanged")
local questEv = Remotes.get("QuestChanged")

local ITEM_NAME: { [string]: string } = {
	Ore = "礦石", Metal = "金屬", Crystal = "晶體", DarkMatter = "暗物質", Ice = "冰", LavaCore = "熔岩核心",
	Biomass = "生質", Scrap = "廢料", RareGas = "稀有氣體",
}

local function rewardText(r: { [string]: number }): string
	local parts = {}
	for id, n in r do
		table.insert(parts, (ITEM_NAME[id] or id) .. " +" .. n)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

local QuestService = {}

function QuestService.push(player: Player)
	local data = DataService.get(player)
	if data then
		questEv:FireClient(player, Quest.current(data, Quests), Quest.side(data, Quests))
	end
end

function QuestService.notify(player: Player, event: string, arg: any)
	local data = DataService.get(player)
	if not data then
		return
	end
	local done = Quest.notify(data, event, arg, Quests)
	for _, q in done do
		noticeEv:FireClient(player, "🎉 任務完成:" .. q.text .. "(" .. rewardText(q.reward) .. ")")
	end
	if #done > 0 then
		stateEv:FireClient(player, { Inventory = data.Inventory })
	end
	QuestService.push(player)
end

-- 登入歡迎:離線收益 + 每日獎勵(只對星球主人)
function QuestService.welcome(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local secs, gained = Build.offline(data, now, Buildings)
	if gained > 0 then
		noticeEv:FireClient(player, ("歡迎回來!你離開 %d 分鐘,礦機幫你採了 %d 份資源"):format(secs // 60, gained))
	end
	local streak, reward = Daily.claim(data, Daily.dayOf(now))
	if streak and reward then
		task.delay(3, function()
			noticeEv:FireClient(player, ("每日獎勵 第 %d 天:%s"):format(streak, rewardText(reward)))
		end)
	end
	stateEv:FireClient(player, { Inventory = data.Inventory })
	QuestService.push(player)
end

return QuestService
