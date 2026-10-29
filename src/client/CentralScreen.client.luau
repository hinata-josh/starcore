--!strict
-- 中央螢幕(星球指揮中心):
--   左:整顆星球展開成 2D 平面的開發地圖(建築依類別著色、裂縫降落點、母星特產資源)
--   右:戰況條(星核/護盾/牆/剩餘怪獸)+ 訊息播放(怪物入侵、好友來訪/採集、穿梭…)
--   下:一行摘要(建築數、電力、火力…)
-- 按 M 或左下角按鈕開關;怪物入侵開始時自動彈出,戰鬥結束幾秒後自動收起。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapView = require(Shared.Logic.MapView)
local Buildings = require(Shared.Data.Buildings)
local Items = require(Shared.Data.Items)
local PlanetLevels = require(Shared.Data.PlanetLevels)
local Remotes = require(Shared.Net.Remotes)
local Skin = require(Shared.UI.Skin)

local player = Players.LocalPlayer
local stateEv = Remotes.get("StateChanged")
local feedEv = Remotes.get("ScreenFeed")
local infoEv = Remotes.get("WaveInfo")

local CELL = 6 -- 地圖每格像素
local N_DEFAULT = 12
local MAX_FEED = 14

local KIND_COLOR: { [string]: Color3 } = {
	energy = Color3.fromRGB(90, 220, 120),
	collect = Color3.fromRGB(240, 200, 70),
	storage = Color3.fromRGB(200, 160, 110),
	attack = Color3.fromRGB(240, 90, 90),
	defense = Color3.fromRGB(90, 160, 245),
	support = Color3.fromRGB(190, 130, 240),
	tech = Color3.fromRGB(245, 245, 245),
	other = Color3.fromRGB(160, 160, 160),
}
local KIND_NAME: { [string]: string } = {
	energy = "能源", collect = "採集", storage = "倉儲", attack = "攻擊", defense = "防禦", support = "輔助", tech = "科技",
}
local FEED_COLOR: { [string]: Color3 } = {
	info = Color3.fromRGB(200, 210, 230),
	good = Color3.fromRGB(120, 235, 150),
	warn = Color3.fromRGB(255, 200, 90),
	danger = Color3.fromRGB(255, 100, 100),
	visitor = Color3.fromRGB(120, 210, 255),
}
local itemName: { [string]: string } = {}
for _, it in Items.Types do
	itemName[it.id] = it.name
end

-- ───────── 介面骨架 ─────────
local gui = Instance.new("ScreenGui")
gui.Name = "CentralScreen"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

-- 左下圖示按鈕(滑過才顯示說明,省畫面空間)
local toggleBtn, toggleText = Skin.iconButton(gui, "📡", "中央螢幕 (M)", "blue", UDim2.new(0, 10, 1, -60))
toggleBtn.Name = "ScreenButton"

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 740, 0, 430)
panel.Position = UDim2.new(0.5, -370, 0.5, -215)
panel.BackgroundColor3 = Color3.fromRGB(10, 14, 28)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(80, 140, 255)
stroke.Thickness = 2
stroke.Parent = panel

local function text(parent: Instance, t: string, pos: UDim2, size: UDim2, sizePx: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = t
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = sizePx
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Position = pos
	l.Size = size
	l.Parent = parent
	return l
end

local title = text(panel, "📡 星球指揮中心", UDim2.new(0, 14, 0, 8), UDim2.new(0, 300, 0, 26), 22)
title.Font = Enum.Font.GothamBold
local waveLabel = text(panel, "", UDim2.new(0, 330, 0, 10), UDim2.new(0, 300, 0, 24), 18, Color3.fromRGB(255, 220, 120))
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 26)
closeBtn.Position = UDim2.new(1, -40, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 50)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Text = "✕"
closeBtn.TextSize = 16
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = panel

-- 地圖
local mapW, mapH = MapView.size(N_DEFAULT)
local mapFrame = Instance.new("Frame")
mapFrame.Position = UDim2.new(0, 14, 0, 62)
mapFrame.Size = UDim2.new(0, mapW * CELL, 0, mapH * CELL)
mapFrame.BackgroundColor3 = Color3.fromRGB(16, 20, 38)
mapFrame.BorderSizePixel = 0
mapFrame.Parent = panel
text(panel, "星球展開圖(6 個面)", UDim2.new(0, 14, 0, 38), UDim2.new(0, 300, 0, 20), 15, Color3.fromRGB(160, 175, 210))

for face = 1, 6 do
	local ox, oy = MapView.faceOrigin(face, N_DEFAULT)
	local bg = Instance.new("Frame")
	bg.Position = UDim2.new(0, ox * CELL, 0, oy * CELL)
	bg.Size = UDim2.new(0, N_DEFAULT * CELL, 0, N_DEFAULT * CELL)
	bg.BackgroundColor3 = Color3.fromRGB(34, 42, 72)
	bg.BorderSizePixel = 0
	bg.Parent = mapFrame
	local tag = text(bg, MapView.FACE_NAME[face], UDim2.new(0, 2, 0, 0), UDim2.new(1, 0, 0, 12), 11, Color3.fromRGB(110, 125, 170))
	tag.TextTransparency = 0.3
end

local cellLayer = Instance.new("Folder")
cellLayer.Name = "Cells"
cellLayer.Parent = mapFrame
local riftMark = Instance.new("TextLabel")
riftMark.BackgroundTransparency = 1
riftMark.Text = "⚠"
riftMark.TextColor3 = Color3.fromRGB(255, 80, 80)
riftMark.TextSize = 18
riftMark.Font = Enum.Font.GothamBold
riftMark.Size = UDim2.new(0, 20, 0, 20)
riftMark.ZIndex = 5
riftMark.Parent = mapFrame
-- 裂縫降落點會跟著「防禦最密集的地方」移動(伺服器算好放在 workspace 屬性 RiftDir)
local function placeRiftMark()
	local d = workspace:GetAttribute("RiftDir") :: Vector3?
	local v = if d then { x = d.X, y = d.Y, z = d.Z } else { x = 1, y = 0.35, z = 0 }
	local rx, ry = MapView.riftCell(v, N_DEFAULT)
	riftMark.Position = UDim2.new(0, rx * CELL - 7, 0, ry * CELL - 8)
end
placeRiftMark()
workspace:GetAttributeChangedSignal("RiftDir"):Connect(placeRiftMark)

-- 圖例
local legendY = 62 + mapH * CELL + 6
local lx = 14
for _, k in { "energy", "collect", "storage", "attack", "defense", "support", "tech" } do
	local sw = Instance.new("Frame")
	sw.Size = UDim2.new(0, 10, 0, 10)
	sw.Position = UDim2.new(0, lx, 0, legendY + 4)
	sw.BackgroundColor3 = KIND_COLOR[k]
	sw.BorderSizePixel = 0
	sw.Parent = panel
	text(panel, KIND_NAME[k], UDim2.new(0, lx + 13, 0, legendY), UDim2.new(0, 36, 0, 18), 13, Color3.fromRGB(190, 200, 225))
	lx += 48
end
text(panel, "⚠ 裂縫降落點", UDim2.new(0, lx, 0, legendY), UDim2.new(0, 100, 0, 18), 13, Color3.fromRGB(255, 130, 130))

local homeLabel = text(panel, "", UDim2.new(0, 14, 0, legendY + 24), UDim2.new(0, mapW * CELL, 0, 36), 14, Color3.fromRGB(255, 225, 150))
homeLabel.TextWrapped = true

-- 戰況條
local barX = 14 + mapW * CELL + 18
local rightW = 740 - barX - 14
local function makeBar(label: string, y: number, color: Color3)
	text(panel, label, UDim2.new(0, barX, 0, y), UDim2.new(0, 60, 0, 18), 14)
	local back = Instance.new("Frame")
	back.Position = UDim2.new(0, barX + 58, 0, y + 2)
	back.Size = UDim2.new(0, rightW - 58, 0, 14)
	back.BackgroundColor3 = Color3.fromRGB(30, 34, 54)
	back.BorderSizePixel = 0
	back.Parent = panel
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	local num = text(back, "", UDim2.new(0, 4, 0, -2), UDim2.new(1, -4, 1, 4), 12)
	num.TextYAlignment = Enum.TextYAlignment.Center
	return fill, num
end
text(panel, "戰況", UDim2.new(0, barX, 0, 38), UDim2.new(0, 100, 0, 20), 15, Color3.fromRGB(160, 175, 210))
local coreFill, coreNum = makeBar("星核", 62, Color3.fromRGB(240, 90, 90))
local shieldFill, shieldNum = makeBar("護盾", 84, Color3.fromRGB(90, 160, 245))
local wallFill, wallNum = makeBar("牆", 106, Color3.fromRGB(200, 170, 110))
local monFill, monNum = makeBar("怪獸", 128, Color3.fromRGB(190, 90, 230))

-- 訊息播放
text(panel, "訊息", UDim2.new(0, barX, 0, 154), UDim2.new(0, 100, 0, 20), 15, Color3.fromRGB(160, 175, 210))
local feedFrame = Instance.new("Frame")
feedFrame.Position = UDim2.new(0, barX, 0, 176)
feedFrame.Size = UDim2.new(0, rightW, 0, 196)
feedFrame.BackgroundColor3 = Color3.fromRGB(14, 18, 34)
feedFrame.BorderSizePixel = 0
feedFrame.ClipsDescendants = true
feedFrame.Parent = panel
local feedLayout = Instance.new("UIListLayout")
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
feedLayout.Padding = UDim.new(0, 1)
feedLayout.Parent = feedFrame

local summaryLabel = text(panel, "", UDim2.new(0, 14, 1, -28), UDim2.new(1, -28, 0, 22), 14, Color3.fromRGB(190, 205, 235))

-- ───────── 狀態 ─────────
local planet: any = { Slots = {}, Level = 1, N = N_DEFAULT }
local nextAt: number? = nil
local waveIndex, waveBoss = 1, false
local order = 0
local autoOpened = false
local idleToken = 0

local function setOpen(open: boolean)
	panel.Visible = open
	toggleText.Text = if open then "  收起中央螢幕 (M)  " else "  中央螢幕 (M)  "
	if not open then
		autoOpened = false
	end
end

local function addFeed(kind: string, msg: string)
	order += 1
	local l = text(feedFrame, msg, UDim2.new(), UDim2.new(1, -8, 0, 0), 14, FEED_COLOR[kind] or FEED_COLOR.info)
	l.LayoutOrder = order
	l.TextWrapped = true
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, -8, 0, 0)
	local kids = feedFrame:GetChildren()
	local labels = {}
	for _, c in kids do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	table.sort(labels, function(a, b)
		return (a :: TextLabel).LayoutOrder < (b :: TextLabel).LayoutOrder
	end)
	while #labels > MAX_FEED do
		labels[1]:Destroy()
		table.remove(labels, 1)
	end
end

local function setBar(fill: Frame, num: TextLabel, value: number, max: number, label: string?)
	local frac = if max > 0 then math.clamp(value / max, 0, 1) else 0
	TweenService:Create(fill, TweenInfo.new(0.4), { Size = UDim2.new(frac, 0, 1, 0) }):Play()
	num.Text = label or ("%d / %d"):format(math.floor(value + 0.5), math.floor(max + 0.5))
end

local function redrawMap()
	cellLayer:ClearAllChildren()
	local n = planet.N or N_DEFAULT
	for _, c in MapView.cells(planet.Slots, n, Buildings) do
		local f = Instance.new("Frame")
		f.Position = UDim2.new(0, c.x * CELL, 0, c.y * CELL)
		f.Size = UDim2.new(0, CELL - 1, 0, CELL - 1)
		f.BackgroundColor3 = KIND_COLOR[c.kind] or KIND_COLOR.other
		f.BorderSizePixel = 0
		-- 等級越高越亮的外框(Lv2、Lv3)
		if c.lv >= 2 then
			local s = Instance.new("UIStroke")
			s.Color = Color3.new(1, 1, 1)
			s.Thickness = c.lv - 1
			s.Parent = f
		end
		f.Parent = cellLayer
	end
	local sum = MapView.summary({ Slots = planet.Slots, Level = planet.Level }, Buildings, PlanetLevels)
	summaryLabel.Text = ("🌍 星球 Lv%d  建築 %d/%d   ⚡電力 %d/%d   🔫火力 %.0f   🛡護盾 %.0f   🧱牆 %.0f   ❤星核 %d"):format(
		sum.level, sum.used, sum.capacity, sum.generation, sum.demand, sum.dps, sum.shield, sum.wallHp, sum.coreHp)
	-- 母星特產
	if planet.Home then
		local boosted = {}
		for _, id in planet.Home.Boosted do
			boosted[id] = true
		end
		local parts = {}
		for _, id in planet.Home.Resources do
			table.insert(parts, (if boosted[id] then "★" else "") .. (itemName[id] or id))
		end
		homeLabel.Text = "母星特產:" .. table.concat(parts, " ") .. "(★高產,其餘 15 種要去別的星球採)"
	end
end

-- ───────── 事件 ─────────
stateEv.OnClientEvent:Connect(function(s)
	if s.Slots then
		planet.Slots = s.Slots
		planet.Level = s.Level or planet.Level
		planet.N = s.N or planet.N
		planet.Home = s.Home or planet.Home
		redrawMap()
	end
end)

infoEv.OnClientEvent:Connect(function(info)
	nextAt = info.nextAt
	waveIndex = info.index
	waveBoss = info.boss
end)

local function handleStatus(d: any)
	if d.phase == "fight" then
		setBar(coreFill, coreNum, d.core, d.coreMax)
		setBar(shieldFill, shieldNum, d.shield, math.max(d.shieldMax, 1))
		setBar(wallFill, wallNum, d.wall, math.max(d.wallMax, 1))
		setBar(monFill, monNum, d.alive, math.max(d.total, 1), ("%d / %d"):format(d.alive, d.total))
		if not panel.Visible then
			autoOpened = true
			setOpen(true)
		end
		idleToken += 1
	else
		-- 戰鬥結束:8 秒後若是自動彈出的就收起
		idleToken += 1
		local my = idleToken
		task.delay(8, function()
			if my == idleToken and autoOpened then
				setOpen(false)
			end
		end)
	end
end

feedEv.OnClientEvent:Connect(function(e)
	if e.kind == "history" then
		for _, h in e.list do
			addFeed(h.kind, h.text or "")
		end
	elseif e.kind == "status" then
		handleStatus(e.data)
	else
		addFeed(e.kind, e.text or "")
		-- 怪物入侵 / 好友來訪,播放的當下提醒玩家(沒開面板時按鈕閃一下)
		if (e.kind == "danger" or e.kind == "visitor") and not panel.Visible then
			Skin.recolor(toggleBtn, if e.kind == "danger" then "red" else "green")
			task.delay(2.5, function()
				Skin.recolor(toggleBtn, "blue")
			end)
		end
	end
end)

toggleBtn.Activated:Connect(function()
	setOpen(not panel.Visible)
end)
closeBtn.Activated:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.M then
		setOpen(not panel.Visible)
	end
end)

RunService.RenderStepped:Connect(function()
	if panel.Visible and nextAt then
		local left = math.floor(math.max(0, nextAt - workspace:GetServerTimeNow())) -- %d 只吃整數
		waveLabel.Text = ("%s第 %d 波裂縫 %d:%02d"):format(if waveBoss then "👹首領 " else "", waveIndex, left // 60, left % 60)
	end
end)

redrawMap()

-- 依視窗大小等比縮放整個介面(小視窗不擠、不超出)
Skin.autoScale(gui)
