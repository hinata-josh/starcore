--!strict
-- 中央螢幕的訊息來源:怪物入侵、好友來訪/採集、穿梭等事件都從這裡推給所有玩家的中央螢幕。
-- kind:info / good / warn / danger / visitor / status(status 是戰況資料幀,不進歷史)。
-- 新加入的玩家會先收到最近的歷史訊息。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)

local feedEv = Remotes.get("ScreenFeed")

local MAX_HISTORY = 40

local ScreenFeed = {}

local history: { any } = {}

function ScreenFeed.push(kind: string, text: string?, data: any?)
	local entry = { kind = kind, text = text, data = data, t = workspace:GetServerTimeNow() }
	if kind ~= "status" then
		table.insert(history, entry)
		if #history > MAX_HISTORY then
			table.remove(history, 1)
		end
	end
	feedEv:FireAllClients(entry)
end

function ScreenFeed.sendHistory(player: Player)
	feedEv:FireClient(player, { kind = "history", list = history })
end

return ScreenFeed
