--!strict
-- 星球之間的旅行:拜訪好友的星球、回到自己的星球、大廳自動送回家(機制見 HomeOwner.luau)。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared.Net.Remotes)
local HomeOwner = require(script.Parent.HomeOwner)

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[TravelService]", ...)
	end
end

local noticeEv = Remotes.get("Notice")
local friendsEv = Remotes.get("RequestFriends")
local listEv = Remotes.get("FriendList")
local visitEv = Remotes.get("VisitFriend")
local homeEv = Remotes.get("GoHome")

-- 防連點:每個動作各自計時(共用的話,查完好友清單馬上按「前往」會被吃掉)
local last: { [Player]: { [string]: number } } = {}
local function throttled(player: Player, action: string, sec: number): boolean
	local now = os.clock()
	local t = last[player]
	if not t then
		t = {}
		last[player] = t
	end
	if now - (t[action] or -math.huge) < sec then
		return true
	end
	t[action] = now
	return false
end

-- 正在玩這個遊戲的線上好友
friendsEv.OnServerEvent:Connect(function(player)
	if throttled(player, "friends", 2) then
		return
	end
	local list = {}
	local ok, entries = pcall(function()
		return player:GetFriendsOnline(200)
	end)
	if ok and type(entries) == "table" then
		for _, e in entries do
			if e.PlaceId == game.PlaceId and type(e.VisitorId) == "number" then
				table.insert(list, { userId = e.VisitorId, name = e.DisplayName or e.UserName or tostring(e.VisitorId) })
			end
		end
	end
	log(player.Name, "查好友:", if ok then #list .. " 位在線上" else "查詢失敗 " .. tostring(entries))
	listEv:FireClient(player, list)
end)

visitEv.OnServerEvent:Connect(function(player, friendId)
	if throttled(player, "visit", 3) or type(friendId) ~= "number" then
		return
	end
	if player:GetAttribute("InTrip") then
		noticeEv:FireClient(player, "先返航,才能去好友的星球")
		return
	end
	local okF, isFriend = pcall(function()
		return player:IsFriendsWith(friendId)
	end)
	if not (okF and isFriend) then
		noticeEv:FireClient(player, "只能拜訪你的 Roblox 好友")
		return
	end
	noticeEv:FireClient(player, "正在前往好友的星球…")
	local ok, why = HomeOwner.teleportTo(player, friendId)
	if not ok then
		noticeEv:FireClient(player, why or "傳送失敗")
	end
end)

homeEv.OnServerEvent:Connect(function(player)
	if throttled(player, "home", 3) then
		return
	end
	if player:GetAttribute("InTrip") then
		noticeEv:FireClient(player, "先返航,才能回家")
		return
	end
	if workspace:GetAttribute("HomeOwnerId") == player.UserId then
		noticeEv:FireClient(player, "你已經在自己的星球了")
		return
	end
	noticeEv:FireClient(player, "正在回到你的星球…")
	local ok, why = HomeOwner.teleportTo(player, player.UserId)
	if not ok then
		noticeEv:FireClient(player, why or "傳送失敗")
	end
end)

-- 大廳(正式環境的公開伺服器):進來就送回自己的星球
Players.PlayerAdded:Connect(function(player)
	if not HomeOwner.isLobby() then
		return
	end
	task.wait(2) -- 等 client 介面起來,才看得到提示
	if not player.Parent then
		return
	end
	noticeEv:FireClient(player, "正在前往你的星球…")
	local ok, why = HomeOwner.teleportTo(player, player.UserId)
	if not ok then
		noticeEv:FireClient(player, (why or "傳送失敗") .. "(重新進入遊戲再試一次)")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)
