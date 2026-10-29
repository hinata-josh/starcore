--!strict
-- 時空穿梭服務(M2):星球主人在母星蓋好「時空門」後可跳躍到種子生成的隨機星球(主人的 Roblox 好友也能用主人的門),
-- 在倒數內採集資源,自己返航或時間到被拉回,再依載重規則結算進背包。
-- 空間在同一個伺服器、遠離母星的位置即時生成(計畫書 §6.3 方案 A),離開即銷毀。
-- 每位玩家各自一趟、各自一顆星球(LANE_GAP 間隔),主人和好友可以同時穿梭;花費、戰利品、採集冷卻都算在自己的存檔。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Trip = require(Shared.Logic.Trip)
local PlanetGen = require(Shared.Logic.PlanetGen)
local Inventory = require(Shared.Logic.Inventory)
local Planets = require(Shared.Data.Planets)
local Items = require(Shared.Data.Items)
local Warp = require(Shared.Data.Warp)
local Gather = require(Shared.Logic.Gather)
local PlanetLevels = require(Shared.Data.PlanetLevels)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)
local QuestService = require(script.Parent.QuestService)
local ScreenFeed = require(script.Parent.ScreenFeed)

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[WarpService]", ...)
	end
end

local TRIP_CENTER = Vector3.new(6000, 300, 0) -- 離母星遠、離原點近(浮點精度安全)
local TYPE_COLORS: { [string]: Color3 } = {
	Rock = Color3.fromRGB(150, 130, 110),
	Ice = Color3.fromRGB(170, 220, 240),
	Crystal = Color3.fromRGB(180, 120, 240),
}
local NODE_COLORS: { [string]: Color3 } = {
	Ore = Color3.fromRGB(200, 160, 90),
	Metal = Color3.fromRGB(190, 190, 200),
	Ice = Color3.fromRGB(150, 230, 255),
	Crystal = Color3.fromRGB(220, 120, 255),
}

local warpEv = Remotes.get("RequestWarp")
local returnEv = Remotes.get("RequestReturn")
local tripEv = Remotes.get("TripChanged")
local cargoEv = Remotes.get("CargoChanged")
local gatherEv = Remotes.get("GatherState")
local stateEv = Remotes.get("StateChanged")
local noticeEv = Remotes.get("Notice")

local itemName: { [string]: string } = {}
for _, it in Items.Types do
	itemName[it.id] = it.name
end

type Active = { trip: any, world: Folder, player: Player, nodeParts: { [number]: Part }, center: Vector3, lane: number }
local active: { [Player]: Active } = {} -- 每位玩家各自一趟
local warping: { [Player]: boolean } = {} -- 防止同一人重入
local LANE_GAP = 1500 -- 每趟穿梭星球之間的距離(互不干擾)
local lanes: { [number]: boolean } = {}
local function takeLane(): number
	for i = 0, 63 do
		if not lanes[i] then
			lanes[i] = true
			return i
		end
	end
	return 0
end

-- 能不能用這台伺服器的時空門:主人,或主人的 Roblox 好友(當下再查一次,剛加好友也算)
local function canUseGate(player: Player): (boolean, Player?)
	local ownerId = workspace:GetAttribute("OwnerUserId")
	local owner = if ownerId then Players:GetPlayerByUserId(ownerId :: number) else nil
	if not owner then
		return false, nil
	end
	if owner == player then
		return true, owner
	end
	local ok, isFriend = pcall(function()
		return owner:IsFriendsWith(player.UserId)
	end)
	local friend = (ok and isFriend) or player:GetAttribute("IsFriendOfOwner") == true
	if ok then
		player:SetAttribute("IsFriendOfOwner", isFriend) -- 順便更新(中途加好友)
	end
	return friend, owner
end

local function hasWarpGate(data: any): boolean
	for _, s in data.Planet.Slots do
		if s.Id == "WarpGate" then
			return true
		end
	end
	return false
end

local function teleport(player: Player, center: Vector3, radius: number)
	player:SetAttribute("GravCenter", center)
	player:SetAttribute("GravRadius", radius)
	player:SetAttribute("TeleportLook", nil) -- 穿梭不指定朝向(清掉觀戰留下的)
	player:SetAttribute("TeleportTo", center + Vector3.new(0, radius + 6, 0))
	player:SetAttribute("TeleportSeq", (player:GetAttribute("TeleportSeq") or 0) + 1)
end

local function sendCargo(a: Active)
	cargoEv:FireClient(a.player, a.trip.loot, Trip.weight(a.trip, Items), a.trip.capacity)
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

local function waitText(sec: number): string
	if sec >= 3600 then
		return ("%.1f 小時"):format(sec / 3600)
	elseif sec >= 60 then
		return ("%d 分鐘"):format(math.ceil(sec / 60))
	end
	return ("%d 秒"):format(math.ceil(sec))
end

local function buildWorld(trip: any, player: Player, center: Vector3): (Folder, { [number]: Part })
	local world = Instance.new("Folder")
	world.Name = "TripWorld"
	local radius = trip.planet.radius
	local ball = Instance.new("Part")
	ball.Name = "TripPlanet"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * radius * 2
	ball.Position = center
	ball.Anchored = true
	ball.Color = TYPE_COLORS[trip.planet.typeId] or Color3.fromRGB(140, 140, 140)
	ball.Material = Enum.Material.Slate
	ball.Parent = world

	local nodeParts: { [number]: Part } = {}
	for i, node in trip.nodes do
		local pos = center + Vector3.new(node.dir.x, node.dir.y, node.dir.z) * radius
		local up = (pos - center).Unit
		local ref = if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
		local part = Instance.new("Part")
		part.Name = "Node_" .. node.id
		part.Anchored = true
		part.CanCollide = false
		part.Size = Vector3.new(4, 4, 4)
		part.Color = NODE_COLORS[node.id] or Color3.fromRGB(255, 255, 255)
		part.Material = Enum.Material.Neon
		part.CFrame = CFrame.lookAt(pos + up * 2, pos + up * 2 + up:Cross(ref).Unit, up)
		part.Parent = world

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "採集"
		prompt.ObjectText = itemName[node.id] or node.id
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = Warp.gatherRange
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function(who)
			local a = active[who]
			if not a or a.world ~= world then
				return -- 只能採自己這趟星球上的點
			end
			-- 距離再驗一次(不信任 client)
			local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or (root.Position - part.Position).Magnitude > Warp.gatherRange + 6 then
				return
			end
			-- 採集節奏:間隔(取決於母星等級)與單一資源 20 次後的 12 小時冷卻
			local pdata = DataService.get(who)
			if not pdata then
				return
			end
			local now = os.time()
			local can, why, wait = Gather.check(pdata, node.id, now, pdata.Planet.Level, PlanetLevels.MaxLevel)
			if not can then
				if why == "Cooldown" then
					noticeEv:FireClient(who, (itemName[node.id] or node.id) .. " 採太多了,還要等 " .. waitText(wait :: number) .. " 才能再採")
				else
					noticeEv:FireClient(who, "採集冷卻中,還要 " .. waitText(wait :: number) .. "(擴建星球可以縮短)")
				end
				sendGather(who)
				return
			end
			local ok, res = Trip.gather(a.trip, i, Items, Warp)
			if ok then
				if Gather.record(pdata, node.id, now) then
					noticeEv:FireClient(who, (itemName[node.id] or node.id) .. " 已採集 " .. Gather.LIMIT .. " 次,進入 12 小時冷卻")
				end
				sendGather(who)
				log("採集", node.id, "+", res, "剩餘點量", node.amount)
				if node.amount <= 0 then
					part:Destroy()
				end
				sendCargo(a)
			elseif res == "Full" then
				noticeEv:FireClient(who, "背包太重了!先返航吧")
			end
		end)
		nodeParts[i] = part
	end
	world.Parent = workspace
	return world, nodeParts
end

local function finish(a: Active, timedOut: boolean)
	if active[a.player] ~= a then
		return
	end
	active[a.player] = nil
	lanes[a.lane] = nil
	local player = a.player
	local kept = Trip.settle(a.trip, Items, Warp, timedOut)
	local data = DataService.get(player)
	if data then
		for id, n in kept do
			Inventory.add(data.Inventory, id, n)
		end
		data.Stats.Trips += 1
		stateEv:FireClient(player, { Inventory = data.Inventory })
		QuestService.notify(player, "trip", nil)
	end
	ScreenFeed.push(if timedOut then "warn" else "good", ("%s %s,帶回了資源"):format(player.DisplayName, if timedOut then "被空間崩塌拉回" else "平安返航"))
	log("返航", if timedOut then "(時間到)" else "(自行返航)", "帶回", kept)
	a.world:Destroy()
	player:SetAttribute("InTrip", nil)
	local hc = workspace:GetAttribute("PlanetCenter") :: Vector3
	local hr = workspace:GetAttribute("PlanetRadius") :: number
	teleport(player, hc, hr)
	tripEv:FireClient(player, nil)
	local parts = {}
	for id, n in kept do
		table.insert(parts, (itemName[id] or id) .. " ×" .. n)
	end
	noticeEv:FireClient(
		player,
		(if timedOut then "空間崩塌!" else "平安返航!") .. (if #parts > 0 then " 帶回:" .. table.concat(parts, " ") else " 這趟空手而回")
	)
end

warpEv.OnServerEvent:Connect(function(player)
	if warping[player] or active[player] then
		return
	end
	local allowed, owner = canUseGate(player)
	if not allowed or not owner then
		noticeEv:FireClient(player, "只有星球主人和他的好友能使用時空門")
		return
	end
	local data = DataService.get(player) -- 花費、戰利品、採集冷卻:用自己的存檔
	local ownerData = DataService.get(owner) -- 時空門與門的等級:用主人星球上的
	if not data or not ownerData then
		return
	end
	if not hasWarpGate(ownerData) then
		noticeEv:FireClient(player, if owner == player then "先蓋一座時空門" else "主人的星球還沒有時空門")
		return
	end
	if workspace:GetAttribute("RiftActive") and owner ~= player then
		-- 好友可以照去;只提醒一下
		noticeEv:FireClient(player, "注意:主人的星球正在被怪獸攻擊")
	end
	if not Inventory.canAfford(data.Inventory, Warp.cost) then
		noticeEv:FireClient(player, "穿梭需要 礦石 " .. (Warp.cost.Ore or 0))
		return
	end
	warping[player] = true
	Inventory.spend(data.Inventory, Warp.cost)
	local seed = os.time() % 100000 * 1000 + player.UserId % 1000
	-- 新手第一次穿梭保證去岩石星(才拿得到金屬,不會空手而回)
	local warpLv = ownerData.Tech.WarpLv
	local planet = PlanetGen.generate(seed, warpLv, Planets, if data.Stats.Trips == 0 then "Rock" else nil)
	local trip = Trip.start(seed, planet, os.time(), warpLv, Warp)
	local lane = takeLane()
	local center = TRIP_CENTER + Vector3.new(0, 0, lane * LANE_GAP)
	local world, nodeParts = buildWorld(trip, player, center)
	local a: Active = { trip = trip, world = world, player = player, nodeParts = nodeParts, center = center, lane = lane }
	active[player] = a
	player:SetAttribute("InTrip", true)
	teleport(player, center, planet.radius)
	stateEv:FireClient(player, { Inventory = data.Inventory })
	tripEv:FireClient(player, {
		name = planet.typeId,
		expiresAt = workspace:GetServerTimeNow() + Warp.durationSec,
		capacity = trip.capacity,
	})
	sendCargo(a)
	sendGather(player)
	warping[player] = nil
	local who = if owner == player then player.DisplayName else "好友 " .. player.DisplayName
	ScreenFeed.push("info", ("🌀 %s 開啟時空門,前往 %s"):format(who, planet.typeId))
	log("跳躍到", planet.typeId, "seed", seed, "半徑", planet.radius, "資源點", #trip.nodes, "通道", lane, if owner == player then "(主人)" else "(好友,用主人的門 Lv" .. warpLv .. ")")
end)

returnEv.OnServerEvent:Connect(function(player)
	local a = active[player]
	if a then
		finish(a, false)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local a = active[player]
	if a then
		a.world:Destroy() -- 玩家離線:這趟戰利品作廢(不寫入存檔),母星資料不受影響
		active[player] = nil
		lanes[a.lane] = nil
	end
	warping[player] = nil
end)

-- 穿梭中角色重生(掉落/死亡)會出生在母星出生點,要把他送回這趟的星球
local function watchRespawn(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		local a = active[player]
		if a then
			teleport(player, a.center, a.trip.planet.radius)
		end
	end)
end
Players.PlayerAdded:Connect(watchRespawn)
for _, p in Players:GetPlayers() do
	watchRespawn(p)
end

task.spawn(function()
	while true do
		task.wait(1)
		local expired = {}
		for _, a in active do
			if Trip.expired(a.trip, os.time()) then
				table.insert(expired, a)
			end
		end
		for _, a in expired do
			finish(a, true)
		end
	end
end)
