--!strict
-- 母星資源點:在主人的母星上依「母星自己的 5 種資源」放可採集的點。
-- 主人與主人的好友都能採;採到的資源進採集者「自己」的背包,並受採集者自己的間隔/20 次冷卻限制。
-- 好友採集時會在中央螢幕播出訊息(ScreenFeed)。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local HomeNode = require(Shared.Logic.HomeNode)
local Gather = require(Shared.Logic.Gather)
local Build = require(Shared.Logic.Build)
local Items = require(Shared.Data.Items)
local Warp = require(Shared.Data.Warp)
local Buildings = require(Shared.Data.Buildings)
local PlanetLevels = require(Shared.Data.PlanetLevels)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)
local ScreenFeed = require(script.Parent.ScreenFeed)
local QuestService = require(script.Parent.QuestService)

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[HomeNodes]", ...)
	end
end

local stateEv = Remotes.get("StateChanged")
local noticeEv = Remotes.get("Notice")
local gatherEv = Remotes.get("GatherState")

local itemName: { [string]: string } = {}
local NODE_COLORS: { [string]: Color3 } = {
	common = Color3.fromRGB(210, 190, 120),
	uncommon = Color3.fromRGB(120, 210, 190),
	rare = Color3.fromRGB(170, 140, 255),
	epic = Color3.fromRGB(255, 120, 200),
}
local itemRarity: { [string]: string } = {}
for _, it in Items.Types do
	itemName[it.id] = it.name
	itemRarity[it.id] = it.rarity
end

local folder = Instance.new("Folder")
folder.Name = "HomeNodes"
folder.Parent = workspace

type Live = { node: any, part: Part, prompt: ProximityPrompt }
local live: { Live } = {}

local function waitText(sec: number): string
	if sec >= 3600 then
		return ("%.1f 小時"):format(sec / 3600)
	elseif sec >= 60 then
		return ("%d 分鐘"):format(math.ceil(sec / 60))
	end
	return ("%d 秒"):format(math.ceil(sec))
end

local function sendGather(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local st = Gather.status(data, os.time(), data.Planet.Level, PlanetLevels.MaxLevel)
	gatherEv:FireClient(player, {
		readyAt = workspace:GetServerTimeNow() + st.readyIn,
		interval = st.interval,
		cooling = st.cooling,
	})
end

local function refreshVisual(l: Live)
	local ready = HomeNode.refresh(l.node, os.time()) > 0
	l.part.Transparency = if ready then 0.1 else 0.85
	l.prompt.Enabled = ready
end

local function onTriggered(l: Live, player: Player)
	local ownerUid = workspace:GetAttribute("OwnerUserId")
	local isOwner = ownerUid == player.UserId
	if not isOwner and not player:GetAttribute("IsFriendOfOwner") then
		noticeEv:FireClient(player, "只有星球主人的好友才能採集這顆星球")
		return
	end
	if player:GetAttribute("InTrip") then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local id = l.node.id
	local now = os.time()
	local can, why, wait = Gather.check(data, id, now, data.Planet.Level, PlanetLevels.MaxLevel)
	if not can then
		if why == "Cooldown" then
			noticeEv:FireClient(player, (itemName[id] or id) .. " 採太多了,還要等 " .. waitText(wait :: number))
		else
			noticeEv:FireClient(player, "採集冷卻中,還要 " .. waitText(wait :: number))
		end
		sendGather(player)
		return
	end
	-- 倉庫放不下就不採(不浪費資源點)
	local room = Build.storageCap(data, Buildings) - (data.Inventory[id] or 0)
	if room <= 0 then
		noticeEv:FireClient(player, (itemName[id] or id) .. " 倉庫滿了,先用掉一些或蓋倉庫")
		return
	end
	local taken = HomeNode.harvest(l.node, math.min(Warp.gatherPerAction, room), now)
	if taken <= 0 then
		refreshVisual(l)
		return
	end
	data.Inventory[id] = (data.Inventory[id] or 0) + taken
	local cooled = Gather.record(data, id, now)
	stateEv:FireClient(player, { Inventory = data.Inventory })
	sendGather(player)
	refreshVisual(l)
	log(player.Name, "採集", id, "×", taken, if isOwner then "(主人)" else "(好友)")
	if not isOwner then
		QuestService.notify(player, "friendGather", nil) -- 選做任務:到好友的星球採集
		-- 中央螢幕:好友在你的星球採集
		ScreenFeed.push("visitor", ("⛏ 好友 %s 在你的星球採集了 %s ×%d"):format(player.DisplayName, itemName[id] or id, taken))
		if cooled then
			ScreenFeed.push("visitor", ("😴 %s 的 %s 已採集 %d 次,進入 12 小時冷卻"):format(player.DisplayName, itemName[id] or id, Gather.LIMIT))
		end
	elseif cooled then
		noticeEv:FireClient(player, (itemName[id] or id) .. " 已採集 " .. Gather.LIMIT .. " 次,進入 12 小時冷卻")
	end
end

local function clearAll()
	for _, l in live do
		l.part:Destroy()
	end
	table.clear(live)
end

local function build(ownerPlayer: Player)
	clearAll()
	local data = DataService.get(ownerPlayer)
	if not data or not data.Planet.Home then
		return
	end
	local center = workspace:GetAttribute("PlanetCenter") :: Vector3?
	local radius = workspace:GetAttribute("PlanetRadius") :: number?
	if not center or not radius then
		return
	end
	for _, node in HomeNode.layout(data.Planet.Home, ownerPlayer.UserId) do
		local d = Vector3.new(node.dir.x, node.dir.y, node.dir.z)
		local pos = center + d * (radius + 2)
		local ref = if math.abs(d.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
		local part = Instance.new("Part")
		part.Name = "HomeNode_" .. node.id
		part.Anchored = true
		part.CanCollide = false
		part.Size = Vector3.new(4, 4, 4)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = NODE_COLORS[itemRarity[node.id] or "common"]
		part.CFrame = CFrame.lookAt(pos, pos + d:Cross(ref).Unit, d)
		part.Parent = folder
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "採集"
		prompt.ObjectText = itemName[node.id] or node.id
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = Warp.gatherRange
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		local l: Live = { node = node, part = part, prompt = prompt }
		prompt.Triggered:Connect(function(who)
			onTriggered(l, who)
		end)
		table.insert(live, l)
	end
	log("已放置母星資源點", #live, "個")
end

-- 主人變動(上線/離線)時重建;之後每 5 秒刷新重生
local function onOwnerChanged()
	local uid = workspace:GetAttribute("OwnerUserId")
	if not uid then
		clearAll()
		return
	end
	local p = Players:GetPlayerByUserId(uid :: number)
	if not p then
		return
	end
	while not DataService.get(p) or not workspace:GetAttribute("PlanetCenter") do
		task.wait(0.2)
	end
	build(p)
end
workspace:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
	task.spawn(onOwnerChanged)
end)
task.spawn(onOwnerChanged)

task.spawn(function()
	while true do
		task.wait(5)
		for _, l in live do
			refreshVisual(l)
		end
	end
end)
