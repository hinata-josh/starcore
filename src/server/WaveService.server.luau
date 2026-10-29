--!strict
-- 星門裂縫服務(M3):倒數 → 預警 → 用 Combat.simulate 算出確定性結果 → 把事件「回放」成畫面 → 結算獎勵。
-- 結果由伺服器純邏輯決定,畫面只是回放(client 無法影響勝負)。
-- 只在星球主人在線時計時(離線保護,見計畫書 §3.3);敗北不清存檔:損失 30% 資源,同一波可重打。
-- 裂縫降落點 = 防禦建築最密集的地方(Logic/RiftTarget);預警開始到戰鬥結束,玩家可以一鍵傳送過去看(RequestWatch)。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Build = require(Shared.Logic.Build)
local Combat = require(Shared.Logic.Combat)
local WaveLogic = require(Shared.Logic.WaveLogic)
local Inventory = require(Shared.Logic.Inventory)
local RiftTarget = require(Shared.Logic.RiftTarget)
local Buildings = require(Shared.Data.Buildings)
local Monsters = require(Shared.Data.Monsters)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)
local QuestService = require(script.Parent.QuestService)
local ScreenFeed = require(script.Parent.ScreenFeed)
local MonsterModel = require(script.Parent.MonsterModel)

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[WaveService]", ...)
	end
end

local WARNING_SEC = 30 -- 開戰前幾秒開始預警
local LOSS_KEEP = 0.7
local RIFT_HEIGHT = 70 -- 裂縫傳送門離地高度
local WATCH_ANGLE = math.rad(16) -- 觀戰點離降落中心的角度(太近會被怪擋住視線)

local infoEv = Remotes.get("WaveInfo")
local resultEv = Remotes.get("WaveResult")
local stateEv = Remotes.get("StateChanged")
local noticeEv = Remotes.get("Notice")
local watchEv = Remotes.get("RequestWatch")

local MON_NAME: { [string]: string } = { RiftTitan = Monsters.Boss.name }
local MON_SIZE: { [string]: number } = { AcidWorm = 5, Behemoth = 9, BladeMoth = 6, PlasmaDrake = 9, RiftTitan = 22 }
local MON_SPIT: { [string]: Color3 } = {
	AcidWorm = Color3.fromRGB(170, 255, 80),
	Behemoth = Color3.fromRGB(255, 140, 50),
	BladeMoth = Color3.fromRGB(255, 255, 160),
	PlasmaDrake = Color3.fromRGB(110, 240, 255),
	RiftTitan = Color3.fromRGB(240, 90, 255),
}
local MON_TRAVEL: { [string]: number } = { RiftTitan = Monsters.Boss.travel }
for _, m in Monsters.Types do
	MON_NAME[m.id] = m.name
	MON_TRAVEL[m.id] = m.travel
end
local CATEGORY: { [string]: string } = {}
for _, d in Buildings.Types do
	CATEGORY[d.id] = d.category
end

type MonsterState = {
	m: any,
	id: string,
	spawnT: number,
	travel: number,
	ground: Vector3,
	up: Vector3,
	face: Vector3,
	alive: boolean,
	shown: boolean,
	nextSpit: number,
}

local owner: Player? = nil
local nextAt = 0 -- os.time()
local fighting = false

local function getOwner(): Player?
	local uid = workspace:GetAttribute("OwnerUserId")
	return if uid then Players:GetPlayerByUserId(uid :: number) else nil
end

local function planet(): (Vector3, number)
	return workspace:GetAttribute("PlanetCenter") :: Vector3, workspace:GetAttribute("PlanetRadius") :: number
end

-- 切平面的兩個軸
local function basis(up: Vector3): (Vector3, Vector3)
	local ref = if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local e1 = up:Cross(ref).Unit
	return e1, up:Cross(e1).Unit
end

-- 目前存檔的裂縫降落方向
local function riftDirOf(data: any): (Vector3, any)
	local t = RiftTarget.pick(data.Planet.Slots, data.Planet.N, Buildings)
	return Vector3.new(t.dir.x, t.dir.y, t.dir.z), t
end

local function previewOf(index: number, data: any)
	local comp = WaveLogic.compose(index, 99, Monsters, WaveLogic.mercy(data.Wave.Losses))
	local list = {}
	for id, n in comp.counts do
		table.insert(list, { id = id, name = MON_NAME[id] or id, count = n })
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	if comp.bossId then
		table.insert(list, { id = comp.bossId, name = MON_NAME[comp.bossId], count = 1 })
	end
	return { index = index, boss = comp.bossId ~= nil, preview = list, scale = comp.scale }
end

local function sendInfo(player: Player, data: any)
	local info = previewOf(data.Wave.Index, data)
	info.nextAt = workspace:GetServerTimeNow() + math.max(0, nextAt - os.time())
	info.warnSec = WARNING_SEC
	infoEv:FireClient(player, info)
end

local function scheduleNext(data: any, first: boolean)
	local idx = data.Wave.Index
	local wait = if first and idx == 1 then WaveLogic.FIRST_WAVE_DELAY else WaveLogic.countdownSeconds(idx)
	nextAt = os.time() + wait
end

-- ── 預警:地面紅色降落區(會跟著降落點移動)──
local zone: Model? = nil
local function showZone(dir: Vector3?)
	if not dir then
		if zone then
			zone:Destroy()
			zone = nil
		end
		return
	end
	local center, radius = planet()
	local e1 = basis(dir)
	local cf = CFrame.fromMatrix(center + dir * (radius + 0.3), dir, e1) -- 圓柱的 X 軸 = 球面法線 → 平貼地面
	if not zone then
		local z = Instance.new("Model")
		z.Name = "RiftZone"
		for i, d in { 46, 30 } do
			local ring = Instance.new("Part")
			ring.Name = "Ring" .. i
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.3, d, d)
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(255, 60, 60)
			ring.Transparency = if i == 1 then 0.75 else 0.55
			ring.Parent = z
		end
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 40)
		gui.StudsOffsetWorldSpace = dir * 18
		gui.AlwaysOnTop = true
		gui.MaxDistance = 1000
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.BuilderSansBold
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(255, 90, 90)
		l.TextStrokeTransparency = 0.3
		l.Text = "⚠ 怪獸降落區"
		l.Parent = gui
		gui.Parent = z:FindFirstChild("Ring1")
		z.Parent = workspace
		zone = z
	end
	local z = zone :: Model
	for _, p in z:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = cf
		end
	end
	local gui = (z:FindFirstChild("Ring1") :: Instance):FindFirstChildOfClass("BillboardGui")
	if gui then
		gui.StudsOffsetWorldSpace = dir * 18
	end
end

-- 降落點周圍的位置:首領在正中央,其他怪用黃金角螺旋散開(不會疊在一起)
local function spotDir(dir: Vector3, i: number, isBoss: boolean): Vector3
	if isBoss then
		return dir
	end
	local e1, e2 = basis(dir)
	local ang = i * 2.39996
	local r = math.rad(3 + 2.2 * math.sqrt(i))
	return (dir * math.cos(r) + (e1 * math.cos(ang) + e2 * math.sin(ang)) * math.sin(r)).Unit
end

local function neonPart(size: Vector3, cf: CFrame, color: Color3, transparency: number, parent: Instance, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Parent = parent
	return p
end

-- 天上的裂縫傳送門:旋轉的光環 + 紫色漩渦 + 粒子 + 一道光柱接到地面
local function makePortal(folder: Instance, center: Vector3, radius: number, dir: Vector3): (number) -> ()
	local e1, e2 = basis(dir)
	local riftPos = center + dir * (radius + RIFT_HEIGHT)
	local baseRot = CFrame.fromMatrix(Vector3.zero, dir, e1)
	local portal = Instance.new("Model")
	portal.Name = "RiftPortal"
	local disk = neonPart(Vector3.new(0.6, 30, 30), CFrame.new(riftPos) * baseRot, Color3.fromRGB(150, 50, 230), 0.3, portal, Enum.PartType.Cylinder)
	neonPart(Vector3.new(0.8, 14, 14), CFrame.new(riftPos) * baseRot, Color3.fromRGB(255, 220, 255), 0.1, portal, Enum.PartType.Cylinder)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(220, 110, 255)
	light.Range = 60
	light.Brightness = 3
	light.Parent = disk
	local fx = Instance.new("ParticleEmitter")
	fx.Color = ColorSequence.new(Color3.fromRGB(255, 160, 255), Color3.fromRGB(120, 60, 255))
	fx.LightEmission = 1
	fx.Rate = 40
	fx.Lifetime = NumberRange.new(1, 2)
	fx.Speed = NumberRange.new(6, 14)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Size = NumberSequence.new(1.2, 0)
	fx.Parent = disk
	-- 外圈 16 片發光碎片
	local ring = {}
	for k = 0, 15 do
		local a = k * math.pi * 2 / 16
		local off = (e1 * math.cos(a) + e2 * math.sin(a)) * 17
		local tangent = -e1 * math.sin(a) + e2 * math.cos(a)
		local p = neonPart(Vector3.new(1.6, 1.6, 6), CFrame.lookAt(riftPos + off, riftPos + off + tangent, dir), if k % 2 == 0 then Color3.fromRGB(255, 120, 230) else Color3.fromRGB(170, 90, 255), 0.05, portal)
		table.insert(ring, { part = p, a = a })
	end
	-- 光柱(傳送門 → 降落區)
	neonPart(Vector3.new(3, RIFT_HEIGHT, 3), CFrame.fromMatrix(center + dir * (radius + RIFT_HEIGHT / 2), e1, dir), Color3.fromRGB(200, 120, 255), 0.82, portal)
	portal.Parent = folder
	-- 每幀:光環旋轉
	return function(t: number)
		for _, r in ring do
			local a = r.a + t * 0.9
			local off = (e1 * math.cos(a) + e2 * math.sin(a)) * 17
			local tangent = -e1 * math.sin(a) + e2 * math.cos(a)
			r.part.CFrame = CFrame.lookAt(riftPos + off, riftPos + off + tangent, dir)
		end
	end
end

-- 降落區附近的攻擊建築(光束從這裡射出);最多取最近的 8 座
local function nearbyTurrets(dir: Vector3, center: Vector3): { Vector3 }
	local list = {}
	local folder = workspace:FindFirstChild("Buildings")
	if not folder then
		return list
	end
	for _, m in folder:GetChildren() do
		local id = m:GetAttribute("BuildingId")
		if m:IsA("Model") and id and CATEGORY[id :: string] == "Attack" then
			local pos = m:GetPivot().Position
			local up = (pos - center).Unit
			table.insert(list, { pos = pos + up * 8, d = -up:Dot(dir) })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for i = 1, math.min(8, #list) do
		out[i] = list[i].pos
	end
	return out
end

local function beam(folder: Instance, from: Vector3, to: Vector3, color: Color3, width: number, life: number)
	local dist = (to - from).Magnitude
	if dist < 0.5 then
		return
	end
	local p = neonPart(Vector3.new(width, width, dist), CFrame.lookAt((from + to) / 2, to), color, 0.1, folder)
	Debris:AddItem(p, life)
	local hit = neonPart(Vector3.one * width * 2.5, CFrame.new(to), Color3.new(1, 1, 1), 0.2, folder, Enum.PartType.Ball)
	TweenService:Create(hit, TweenInfo.new(life * 1.5), { Size = Vector3.one * width * 6, Transparency = 1 }):Play()
	Debris:AddItem(hit, life * 1.6)
end

-- 回放:怪獸從裂縫傳送門降落到防禦最密集的地方 → 砲台開火 → 依事件被擊倒
local function replay(comp: any, result: any, center: Vector3, radius: number, dir: Vector3, coreMax: number, shieldMax: number, wallMax: number)
	local folder = Instance.new("Folder")
	folder.Name = "WaveMonsters"
	folder.Parent = workspace
	local riftPos = center + dir * (radius + RIFT_HEIGHT)
	local spinPortal = makePortal(folder, center, radius, dir)
	local e1 = basis(dir)

	local order = {}
	for id in comp.counts do
		table.insert(order, id)
	end
	table.sort(order)
	local list = {}
	for _, id in order do
		for _ = 1, comp.counts[id] do
			table.insert(list, id)
		end
	end
	if comp.bossId then
		table.insert(list, comp.bossId)
	end

	-- 每隻怪的回放狀態(順序與 Combat.simulate 一致 → kill 事件的 index 對得上)
	local states: { MonsterState } = {}
	local sc = comp.scale or 1
	for i, id in list do
		local isBoss = id == comp.bossId
		local size = (MON_SIZE[id] or 5) * (if isBoss then 1 else math.min(sc, 3) ^ 0.5)
		local label = if isBoss then "👹 " .. (MON_NAME[id] or id) elseif sc > 1 then (MON_NAME[id] or id) .. " ×" .. sc else nil
		local sdir = spotDir(dir, i, isBoss)
		local toCenter = dir - sdir * sdir:Dot(dir)
		states[i] = {
			m = MonsterModel.create(id, size, label), id = id,
			spawnT = (i - 1) * Monsters.spawnGap, travel = MON_TRAVEL[id] or 14,
			ground = center + sdir * radius, up = sdir,
			face = if toCenter.Magnitude > 1e-3 then toCenter.Unit else e1,
			alive = true, shown = false, nextSpit = 0,
		}
	end

	local turrets = nearbyTurrets(dir, center)
	local start = os.clock()
	local nextShot = 0
	local shotIdx = 0
	local conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		spinPortal(t)
		local inRange = {}
		for i, s in states do
			if not s.alive or t < s.spawnT then
				continue
			end
			local m = s.m
			if not s.shown then
				s.shown = true
				m.model.Parent = folder
			end
			-- 由傳送門往下降落(先快後慢),落地後原地蓄勢晃動
			local k = math.clamp((t - s.spawnT) / s.travel, 0, 1)
			local ease = 1 - (1 - k) ^ 2
			local landed = s.ground + s.up * m.flyHeight
			local pos = riftPos:Lerp(landed, ease)
			local up = (pos - center).Unit
			local bob = math.sin(t * (if m.flyHeight > 0 then 4 else 2.5) + i) * m.size * (if m.flyHeight > 0 then 0.08 else 0.03)
			local lunge = if k >= 1 then math.max(0, math.sin(t * 2.2 + i)) * m.size * 0.12 else 0
			pos += up * bob
			local fwd = s.face - up * s.face:Dot(up)
			fwd = if fwd.Magnitude > 1e-3 then fwd.Unit else e1
			pos += fwd * lunge
			m.root.CFrame = CFrame.lookAt(pos, pos + fwd, up)
			MonsterModel.animate(m, t, i)
			if t >= s.spawnT + s.travel - Combat.RANGE_LEAD then
				table.insert(inRange, s)
			end
			-- 落地後朝防線吐攻擊彈
			if k >= 1 and t >= s.nextSpit then
				s.nextSpit = t + 1.2 + (i % 3) * 0.3
				local from = pos + up * m.size * 0.5
				local to = center + dir * (radius + 3)
				local ball = neonPart(Vector3.one * math.max(1, m.size * 0.15), CFrame.new(from), MON_SPIT[s.id] or Color3.new(1, 0.3, 0.3), 0.1, folder, Enum.PartType.Ball)
				TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = to }):Play()
				Debris:AddItem(ball, 0.55)
			end
		end
		-- 砲台輪流開火(純特效;勝負由 Combat.simulate 決定)
		if #turrets > 0 and #inRange > 0 and t >= nextShot then
			nextShot = t + 0.25
			shotIdx += 1
			local s = inRange[(shotIdx % #inRange) + 1]
			local from = turrets[(shotIdx % #turrets) + 1]
			local to = s.m.root.Position + s.m.root.CFrame.UpVector * (s.m.size * 0.5)
			beam(folder, from, to, if shotIdx % 2 == 0 then Color3.fromRGB(255, 230, 90) else Color3.fromRGB(120, 230, 255), 0.6, 0.12)
		end
	end)

	-- 中央螢幕:怪獸降落訊息、戰況幀(星核/護盾/剩餘怪獸)
	local total = #list
	for i, id in list do
		task.delay((i - 1) * Monsters.spawnGap, function()
			ScreenFeed.push(if id == comp.bossId then "danger" else "warn", ("👾 %s 從裂縫降落!"):format(MON_NAME[id] or id))
		end)
	end
	for _, sm in result.samples do
		task.delay(sm.t, function()
			ScreenFeed.push("status", nil, {
				phase = "fight", alive = sm.alive, total = total, core = sm.core, coreMax = coreMax,
				shield = sm.shield, wall = sm.wall, shieldMax = shieldMax, wallMax = wallMax,
			})
		end)
	end
	local killed = 0
	for _, ev in result.events do
		if ev.kind == "kill" and ev.index then
			task.delay(ev.t, function()
				killed += 1
				ScreenFeed.push("good", ("💥 擊倒 %s(剩 %d/%d)"):format(MON_NAME[list[ev.index]] or "怪獸", total - killed, total))
				local s = states[ev.index]
				if s and s.alive then
					s.alive = false
					if s.m.model.Parent then
						MonsterModel.kill(s.m)
					else
						s.m.model:Destroy()
					end
				end
			end)
		end
	end
	local function cleanup()
		conn:Disconnect()
		folder:Destroy()
	end
	return cleanup, result.duration
end

local function fight(player: Player, data: any)
	fighting = true
	local index = data.Wave.Index
	local comp = WaveLogic.compose(index, 99, Monsters, WaveLogic.mercy(data.Wave.Losses))
	local def = Combat.defenseOf(Build.placedList(data), Buildings, data.Planet.Level)
	local result = Combat.simulate(def, comp, Monsters, comp.budget)
	local dir, target = riftDirOf(data)
	workspace:SetAttribute("RiftDir", dir)
	log(("第 %d 波開戰:怪 %d 隻(巨大化×%d)%s;防禦 dps %.1f 護盾 %.0f 牆 %.0f → %s,星核剩 %.0f/%.0f;降落點 %s(%s,群內 %d 座)"):format(
		index, result.total, comp.scale, if comp.bossId then "含首領" else "", def.dps, def.shield, def.wallHp,
		if result.won then "守住" else "失守", result.coreHpLeft, def.coreHp, tostring(target.key), target.source, target.count))

	local center, radius = planet()
	local mlist = {}
	for id, n in comp.counts do
		table.insert(mlist, (MON_NAME[id] or id) .. "×" .. n)
	end
	table.sort(mlist)
	ScreenFeed.push("danger", ("🚨 第 %d 波入侵!%s%s"):format(
		index, table.concat(mlist, "、"), if comp.bossId then "、👹首領 " .. Monsters.Boss.name else ""))
	local cleanup, duration = replay(comp, result, center, radius, dir, def.coreHp, def.shield, def.wallHp)
	task.wait(math.min(duration, Combat.MAX_TIME) + 1.5)
	cleanup()
	showZone(nil)
	workspace:SetAttribute("RiftActive", false)

	local reward: { [string]: number }? = nil
	if result.won then
		reward = WaveLogic.reward(index, Monsters)
		for id, n in reward :: { [string]: number } do
			Inventory.add(data.Inventory, id, n)
		end
		data.Wave.Index = index + 1
		data.Wave.Losses = 0
		data.Stats.WavesWon += 1
		if WaveLogic.isBoss(index, Monsters) then
			data.Wave.BossDefeated = true
		end
	else
		for id, n in data.Inventory do
			data.Inventory[id] = math.floor(n * LOSS_KEEP)
		end
		data.Stats.WavesLost += 1
		data.Wave.Losses += 1
	end
	ScreenFeed.push(if result.won then "good" else "danger",
		if result.won then ("✅ 第 %d 波守住了!星核 %d/%d"):format(index, result.coreHpLeft, def.coreHp)
		else ("💥 第 %d 波失守(擊殺 %d/%d)"):format(index, result.killed, result.total))
	ScreenFeed.push("status", nil, { phase = "idle" })
	resultEv:FireClient(player, {
		won = result.won, coreLeft = result.coreHpLeft, coreMax = def.coreHp, reward = reward, index = index,
		killed = result.killed, total = result.total,
	})
	stateEv:FireClient(player, { Inventory = data.Inventory })
	if result.won then
		QuestService.notify(player, "waveWon", index)
	else
		noticeEv:FireClient(player, "星球被突破了!損失 30% 資源,但建築都還在。補強防禦再迎戰吧")
	end
	DataService.save(player)
	scheduleNext(data, false)
	sendInfo(player, data)
	fighting = false
end

-- 觀戰傳送:送到降落區旁邊(面向降落中心),由 client 的 SphereGravity 執行搬移
local lastWatch: { [Player]: number } = {}
watchEv.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastWatch[player] or 0) < 1.5 then
		return
	end
	lastWatch[player] = now
	if player:GetAttribute("InTrip") then
		noticeEv:FireClient(player, "先返航回母星,才能去防守現場")
		return
	end
	local dir = workspace:GetAttribute("RiftDir") :: Vector3?
	if not workspace:GetAttribute("RiftActive") or not dir then
		noticeEv:FireClient(player, "現在沒有怪獸來襲")
		return
	end
	local center, radius = planet()
	local e1 = basis(dir)
	local side = (dir * math.cos(WATCH_ANGLE) + e1 * math.sin(WATCH_ANGLE)).Unit
	local pos = center + side * (radius + 6)
	local look = (center + dir * (radius + 10)) - pos
	player:SetAttribute("TeleportTo", pos)
	player:SetAttribute("TeleportLook", look.Unit)
	player:SetAttribute("TeleportSeq", ((player:GetAttribute("TeleportSeq") or 0) :: number) + 1)
	noticeEv:FireClient(player, "已傳送到防守現場!")
	log("觀戰傳送", player.Name, "→", pos)
end)
Players.PlayerRemoving:Connect(function(p)
	lastWatch[p] = nil
end)

-- 主迴圈:找到主人 → 排程 → 倒數預警 → 開戰
task.spawn(function()
	local lastWarn = -1
	local lastAuto = -1
	local lastDir: Vector3? = nil
	while true do
		task.wait(1)
		local p = getOwner()
		if p ~= owner then
			owner = p
			lastWarn = -1
			if p then
				local data = DataService.get(p)
				if data then
					scheduleNext(data, true)
					sendInfo(p, data)
					log("星球主人上線,第", data.Wave.Index, "波倒數開始")
				else
					owner = nil
				end
			end
		end
		if owner and not fighting then
			local data = DataService.get(owner)
			if data then
				-- 降落點跟著建築變動(中央螢幕的 ⚠ 標記、預警的紅圈都會跟著移動)
				local dir = riftDirOf(data)
				if not lastDir or (dir - lastDir).Magnitude > 1e-4 then
					lastDir = dir
					workspace:SetAttribute("RiftDir", dir)
				end
				local left = nextAt - os.time()
				if left <= WARNING_SEC and left > 0 then
					workspace:SetAttribute("RiftActive", true)
					showZone(dir)
					if lastWarn ~= data.Wave.Index then
						lastWarn = data.Wave.Index
						noticeEv:FireClient(owner, "⚠ 裂縫即將開啟!按「前往防守現場」去看防線")
						ScreenFeed.push("warn", ("⚠ 第 %d 波裂縫 %d 秒後開啟!降落在防禦最密集的地方"):format(data.Wave.Index, left))
					end
				end
				-- 開戰前 3 秒:通知 client 倒數自動傳送(玩家可取消)
				if left <= 3 and left > 0 and lastAuto ~= data.Wave.Index then
					lastAuto = data.Wave.Index
					workspace:SetAttribute("RiftAutoWatchAt", workspace:GetServerTimeNow() + left)
					log("通知自動觀戰倒數", left, "秒")
				end
				if left <= 0 then
					task.spawn(fight, owner, data)
				end
			end
		elseif not owner then
			if workspace:GetAttribute("RiftActive") then
				workspace:SetAttribute("RiftActive", false)
				showZone(nil)
			end
		end
	end
end)
