--!strict
-- 母星服務:本伺服器的「星球主人」=第一位進來的玩家,其他人是訪客(只能走動,不能改存檔,見計畫書 §6.6)。
-- client 只送意圖(PlaceBuilding / RemoveBuilding),規則與存檔變更都在 Logic/Build 內。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local CubeSphere = require(Shared.Logic.CubeSphere)
local Build = require(Shared.Logic.Build)
local Buildings = require(Shared.Data.Buildings)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)
local QuestService = require(script.Parent.QuestService)
local ScreenFeed = require(script.Parent.ScreenFeed)
local BuildingModel = require(script.Parent.BuildingModel)
local HomeOwner = require(script.Parent.HomeOwner)
local HomePlanet = require(Shared.Logic.HomePlanet)
local Items = require(Shared.Data.Items)
local Warp = require(Shared.Data.Warp)

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[PlanetService]", ...)
	end
end

local COLORS = {
	Collect = Color3.fromRGB(240, 190, 60),
	Energy = Color3.fromRGB(80, 220, 120),
	Attack = Color3.fromRGB(230, 80, 80),
	Defense = Color3.fromRGB(80, 160, 240),
	Support = Color3.fromRGB(190, 130, 240),
	Tech = Color3.fromRGB(240, 240, 240),
}

local stateEv = Remotes.get("StateChanged")
local noticeEv = Remotes.get("Notice")
local placeEv = Remotes.get("PlaceBuilding")
local removeEv = Remotes.get("RemoveBuilding")
local upgradeEv = Remotes.get("UpgradeBuilding")
local upgradeWarpEv = Remotes.get("UpgradeWarp")

local ERR_TEXT: { [string]: string } = {
	BadSlot = "這個位置不能蓋",
	UnknownBuilding = "不認識這個建築",
	Occupied = "這格已經有建築了",
	Limit = "這種建築只能蓋一座",
	NoResources = "資源不夠",
	Empty = "這格沒有建築",
	NotOwner = "這是別人的星球,只能參觀",
	MaxLevel = "已經是最高等級了",
	NoGate = "先蓋一座時空門",
	NotBuildable = "這個建築不能自己蓋",
	Permanent = "指揮中心是你的基地,不能拆",
	PlanetFull = "星球格位滿了,先擴建星球",
}

local owner: Player? = nil
local lastAction: { [Player]: number } = {}
local models: { [string]: Instance } = {}

local center = Vector3.zero
local radius = 100
local planetReady = false

local buildingsFolder = Instance.new("Folder")
buildingsFolder.Name = "Buildings"
buildingsFolder.Parent = workspace

local function countSlots(data: any): number
	local c = 0
	for _ in data.Planet.Slots do
		c += 1
	end
	return c
end

local function snapshot(data: any): any
	local slots = {}
	for k, s in data.Planet.Slots do
		slots[k] = { Id = s.Id, Lv = s.Lv }
	end
	return {
		Inventory = data.Inventory, Slots = slots, Level = data.Planet.Level, N = data.Planet.N, Home = data.Planet.Home,
		WarpLv = data.Tech.WarpLv, -- 時空門等級(client 判斷升級鈕要不要出現)
	}
end

local function spawnModel(data: any, slotKey: string, id: string)
	local slot = CubeSphere.parseKey(slotKey, data.Planet.N)
	if not slot then
		return
	end
	local def = Build.find(Buildings, id)
	if not def then
		return
	end
	local p = CubeSphere.position(slot.face, slot.u, slot.v, data.Planet.N, radius)
	local pos = center + Vector3.new(p.x, p.y, p.z)
	local up = (pos - center).Unit
	local ref = if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local base = CFrame.lookAt(pos, pos + up:Cross(ref).Unit, up) -- Y 軸朝外、原點在地表
	local lv = data.Planet.Slots[slotKey].Lv
	local model = BuildingModel.create(def, lv, base, slotKey)
	model.Parent = buildingsFolder
	models[slotKey] = model
end

local function clearModel(slotKey: string)
	local m = models[slotKey]
	if m then
		m:Destroy()
		models[slotKey] = nil
	end
end

local function pushState(data: any)
	stateEv:FireAllClients(snapshot(data))
end

-- 回傳主人的存檔;不是主人或太頻繁則回 nil
local function guard(player: Player): any?
	if not owner then
		-- 主人存檔還沒載入完(DataStore 讀取中),不是「別人的星球」
		noticeEv:FireClient(player, "星球載入中,請稍等幾秒…")
		log("忽略操作:星球主人尚未載入", player.Name)
		return nil
	end
	if player ~= owner then
		noticeEv:FireClient(player, ERR_TEXT.NotOwner)
		return nil
	end
	if player:GetAttribute("InTrip") then
		noticeEv:FireClient(player, "先返航回母星才能建造")
		return nil
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.1 then
		return nil -- 節流,防連點/外掛洗封包
	end
	lastAction[player] = now
	return DataService.get(player)
end

placeEv.OnServerEvent:Connect(function(player, slotKey, buildingId)
	local data = guard(player)
	if not data or not planetReady then
		return
	end
	local ok, err = Build.place(data, slotKey, buildingId, Buildings)
	if ok then
		log("蓋", buildingId, "於", slotKey, "剩餘礦石", data.Inventory.Ore)
		spawnModel(data, slotKey, buildingId)
		pushState(data)
		QuestService.notify(player, "build", buildingId)
	else
		noticeEv:FireClient(player, ERR_TEXT[err :: string] or "不能這樣做")
	end
end)

removeEv.OnServerEvent:Connect(function(player, slotKey)
	local data = guard(player)
	if not data then
		return
	end
	local ok, err = Build.remove(data, slotKey, Buildings)
	if ok then
		log("拆", slotKey)
		clearModel(slotKey :: string)
		pushState(data)
	else
		noticeEv:FireClient(player, ERR_TEXT[err :: string] or "不能這樣做")
	end
end)

-- 訪客打招呼 + 判斷是不是主人的好友(只有好友能採集/用時空門)
local function greet(player: Player)
	if not owner or player == owner then
		return
	end
	local okF, isFriend = pcall(function()
		return (owner :: Player):IsFriendsWith(player.UserId)
	end)
	local friend = okF and isFriend
	player:SetAttribute("IsFriendOfOwner", friend)
	ScreenFeed.push("visitor", (if friend then "👋 好友 " else "👤 訪客 ") .. player.DisplayName .. " 來到你的星球")
	noticeEv:FireClient(owner, (if friend then "好友 " else "訪客 ") .. player.DisplayName .. " 來到你的星球")
end

local function onPlayer(player: Player)
	-- 私人伺服器:記下這台是誰的星球;正式環境的大廳不載入星球(TravelService 會把人送回家)
	HomeOwner.resolve(player)
	if HomeOwner.isLobby() then
		log("大廳:", player.Name, "不載入星球,等待傳送回自己的星球")
		return
	end
	log("載入存檔中:", player.Name)
	local t0 = os.clock()
	local data = DataService.load(player)
	log(("存檔載入%s,耗時 %.1f 秒"):format(if data then "完成" else "失敗", os.clock() - t0))
	if not data then
		player:Kick("存檔載入失敗,請稍後重試(你的資料沒有受損)")
		return
	end
	HomePlanet.ensure(data, player.UserId, Items) -- 每位玩家的母星資源(隨機 5 種、2 種高產)固定下來
	while not planetReady do
		task.wait(0.1)
	end
	-- 主人:私人伺服器只認 HomeOwnerId(訪客先到也不會變主人);Studio / 沒指定時第一位進來的人
	local designated = workspace:GetAttribute("HomeOwnerId")
	if not owner and (designated == nil or designated == player.UserId) then
		owner = player
		workspace:SetAttribute("OwnerUserId", player.UserId)
		for k, s in data.Planet.Slots do
			spawnModel(data, k, s.Id)
		end
		log("星球主人:", player.Name, "已載入建築數", countSlots(data))
		QuestService.welcome(player) -- 離線收益 + 每日獎勵 + 目前任務
		ScreenFeed.push("info", "🌍 " .. player.DisplayName .. " 的星球上線了")
		-- 比主人早到的訪客:現在才知道是不是好友
		for _, p in Players:GetPlayers() do
			if p ~= player and p:GetAttribute("IsFriendOfOwner") == nil then
				greet(p)
				stateEv:FireClient(p, snapshot(data))
			end
		end
	end
	ScreenFeed.sendHistory(player)
	if player ~= owner then
		if owner then
			-- 訪客:只有主人的 Roblox 好友能採集/互動(計畫書 §6.6);非好友只能看
			greet(player)
		else
			-- 晚一點送:剛進來時 client 介面還沒準備好,提示會漏掉
			task.delay(3, function()
				if player.Parent and not owner then
					noticeEv:FireClient(player, "星球主人還沒回來,等一下或按「🏠 回到我的星球」")
				end
			end)
		end
	end
	player:SetAttribute("GravCenter", center)
	player:SetAttribute("GravRadius", radius)
	local ownerData = DataService.get(owner :: Player)
	if ownerData then
		stateEv:FireClient(player, snapshot(ownerData))
	end
end

upgradeEv.OnServerEvent:Connect(function(player, slotKey)
	local data = guard(player)
	if not data then
		return
	end
	local ok, err = Build.upgrade(data, slotKey, Buildings)
	if ok then
		log("升級", slotKey, "→ Lv", data.Planet.Slots[slotKey].Lv)
		clearModel(slotKey :: string)
		spawnModel(data, slotKey :: string, data.Planet.Slots[slotKey].Id)
		pushState(data)
		noticeEv:FireClient(player, "升級成功!")
		if data.Planet.Slots[slotKey].Lv >= 2 then
			QuestService.notify(player, "upgrade", slotKey)
		end
	else
		noticeEv:FireClient(player, ERR_TEXT[err :: string] or "不能這樣做")
	end
end)

-- 重建星球:拆掉指揮中心以外全部建築、資源全數退還(怪獸來襲中不行,免得拆光防線躲戰鬥)
local rebuildEv = Remotes.get("RebuildPlanet")
rebuildEv.OnServerEvent:Connect(function(player)
	local data = guard(player)
	if not data or not planetReady then
		return
	end
	if workspace:GetAttribute("RiftActive") then
		noticeEv:FireClient(player, "怪獸來襲中,打完再重建")
		return
	end
	local refund, removed = Build.rebuild(data, Buildings)
	if removed == 0 then
		noticeEv:FireClient(player, "星球上沒有可以拆的建築")
		return
	end
	for k in models do
		if not data.Planet.Slots[k] then
			clearModel(k)
		end
	end
	local parts = {}
	for id, n in refund do
		table.insert(parts, id .. "+" .. n)
	end
	log("重建星球:拆掉", removed, "座,退還", table.concat(parts, " "))
	pushState(data)
	noticeEv:FireClient(player, ("星球已清空:拆掉 %d 座,資源全數退還"):format(removed))
	ScreenFeed.push("info", "🔄 " .. player.DisplayName .. " 重建了星球(拆掉 " .. removed .. " 座)")
	DataService.save(player)
end)

upgradeWarpEv.OnServerEvent:Connect(function(player)
	local data = guard(player)
	if not data then
		return
	end
	local ok, err = Build.upgradeWarp(data, Warp)
	if ok then
		log("時空門升級到 Lv", data.Tech.WarpLv)
		pushState(data)
		noticeEv:FireClient(player, "時空門升到 Lv" .. data.Tech.WarpLv .. "!能去更遠的星球,載重也變大")
		QuestService.notify(player, "warpUp", data.Tech.WarpLv)
	else
		noticeEv:FireClient(player, ERR_TEXT[err :: string] or "資源不夠")
	end
end)

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end

Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
	if player ~= owner and player:GetAttribute("IsFriendOfOwner") ~= nil then
		ScreenFeed.push("visitor", "🚪 " .. player.DisplayName .. " 離開了星球")
	end
	if player == owner then
		owner = nil
		workspace:SetAttribute("OwnerUserId", nil)
		for k in models do
			clearModel(k)
		end
		for _, p in Players:GetPlayers() do
			if p ~= player then
				p:SetAttribute("IsFriendOfOwner", nil)
				noticeEv:FireClient(p, "星球主人離開了,按「🏠 回到我的星球」回家")
			end
		end
	end
end)

-- 等 PlanetDemo 設好星球參數
task.spawn(function()
	while not workspace:GetAttribute("PlanetCenter") do
		task.wait(0.1)
	end
	center = workspace:GetAttribute("PlanetCenter") :: Vector3
	radius = workspace:GetAttribute("PlanetRadius") :: number
	planetReady = true
end)

-- 每秒產出
task.spawn(function()
	while true do
		task.wait(1)
		if owner then
			local data = DataService.get(owner)
			if data and Build.tick(data, 1, Buildings) > 0 then
				pushState(data)
			end
		end
	end
end)
