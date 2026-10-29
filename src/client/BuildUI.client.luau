--!strict
-- M1 建造介面:左鍵點格位=蓋選中的建築,右鍵點建築=拆除。顯示資源與提示。
-- 只送意圖給伺服器;畫面以 StateChanged 為準。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Buildings = require(Shared.Data.Buildings)
local Build = require(Shared.Logic.Build)
local Items = require(Shared.Data.Items)
local Remotes = require(Shared.Net.Remotes)

local player = Players.LocalPlayer
local placeEv = Remotes.get("PlaceBuilding")
local removeEv = Remotes.get("RemoveBuilding")
local stateEv = Remotes.get("StateChanged")
local noticeEv = Remotes.get("Notice")

local Skin = require(Shared.UI.Skin)
local TweenService = game:GetService("TweenService")

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[BuildUI]", ...)
	end
end

local itemDef: { [string]: any } = {}
for _, it in Items.Types do
	itemDef[it.id] = it
end

-- 資源圖示(沒上傳素材時:稀有度顏色的圓 + 名稱第一個字)
local function itemIcon(parent: Instance, id: string, size: UDim2, pos: UDim2?): ImageLabel
	local it = itemDef[id]
	local name = if it then it.name else id
	local color = Skin.RARITY_COLOR[if it then it.rarity else "common"]
	return Skin.icon(parent, "item_" .. id, size, pos, utf8.char(utf8.codepoint(name, 1)), color)
end

local function compact(n: number): string
	if n >= 10000 then
		return ("%.0fk"):format(n / 1000)
	elseif n >= 1000 then
		return ("%.1fk"):format(n / 1000)
	end
	return tostring(math.floor(n))
end

local selected = Buildings.Types[1].id
local inventory: { [string]: number } = {}
local owned: { [string]: number } = {} -- 目前星球上每種建築幾座(判斷「只能蓋一座」的已擁有)

local gui = Instance.new("ScreenGui")
gui.Name = "BuildUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- 確認框專用的最上層:Instance.new 的 ScreenGui 預設是 Global ZIndex,
-- 面板設 ZIndex 10 反而把自己的字和按鈕(ZIndex 1)蓋在半透明底下 → 改用 Sibling + 最高 DisplayOrder
local modalGui = Instance.new("ScreenGui")
modalGui.Name = "BuildModal"
modalGui.ResetOnSpawn = false
modalGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
modalGui.DisplayOrder = 20
modalGui.Parent = player:WaitForChild("PlayerGui")

-- ── 資源列(上方中央):有的資源才顯示,圖示 + 數量 ──
local invPanel = Skin.panel(gui, UDim2.new(0, 640, 0, 0), UDim2.new(0.5, 0, 0, 6))
invPanel.AnchorPoint = Vector2.new(0.5, 0)
invPanel.AutomaticSize = Enum.AutomaticSize.Y
local invPad = Instance.new("UIPadding")
invPad.PaddingTop, invPad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
invPad.PaddingLeft, invPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
invPad.Parent = invPanel
local invGrid = Instance.new("UIGridLayout")
invGrid.CellSize = UDim2.fromOffset(70, 26)
invGrid.CellPadding = UDim2.fromOffset(4, 2)
invGrid.SortOrder = Enum.SortOrder.LayoutOrder
invGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
invGrid.Parent = invPanel
local invEmpty = Skin.text(invPanel, "資源:—", UDim2.fromOffset(160, 26), nil, 18)
invEmpty.LayoutOrder = 0
local chips: { [string]: { frame: Frame, num: TextLabel } } = {}
for i, it in Items.Types do
	local chip = Instance.new("Frame")
	chip.BackgroundTransparency = 1
	chip.LayoutOrder = i
	chip.Visible = false
	chip.Parent = invPanel
	itemIcon(chip, it.id, UDim2.fromOffset(24, 24), UDim2.fromOffset(0, 1))
	local num = Skin.text(chip, "0", UDim2.new(1, -27, 1, 0), UDim2.fromOffset(27, 0), 20)
	num.TextXAlignment = Enum.TextXAlignment.Left
	chips[it.id] = { frame = chip, num = num }
end

-- ── 提示訊息(上方中央,資源列下面)──
local toast = Skin.banner(gui, "btn_white", UDim2.fromOffset(380, 40), UDim2.new(0.5, 0, 0, 72), Skin.BUTTON_COLOR.white)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Visible = false
local toastText = Skin.text(toast, "", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(12, 5), 22)
toastText.TextColor3 = Color3.fromRGB(70, 45, 20)
toastText.TextStrokeTransparency = 1
local toastScale = Instance.new("UIScale")
toastScale.Parent = toast

local toastToken = 0
local function showToast(text: string)
	toastToken += 1
	local my = toastToken
	toastText.Text = text
	toast.Visible = true
	toastScale.Scale = 0.6
	TweenService:Create(toastScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(2.5, function()
		if my == toastToken then
			toast.Visible = false
		end
	end)
end

-- ── 建造面板(下方):類別分頁 + 可左右捲動的建築卡片 ──
local CATEGORIES = {
	{ id = "Energy", name = "能源" },
	{ id = "Collect", name = "採集" },
	{ id = "Storage", name = "倉儲" },
	{ id = "Attack", name = "攻擊" },
	{ id = "Defense", name = "防禦" },
	{ id = "Support", name = "支援" },
	{ id = "Tech", name = "科技" },
}
local CAT_COLOR: { [string]: Color3 } = {
	Energy = Color3.fromRGB(80, 220, 120),
	Collect = Color3.fromRGB(240, 190, 60),
	Storage = Color3.fromRGB(200, 160, 110),
	Attack = Color3.fromRGB(230, 80, 80),
	Defense = Color3.fromRGB(80, 160, 240),
	Support = Color3.fromRGB(190, 130, 240),
	Tech = Color3.fromRGB(230, 230, 240),
}

local CAT_LETTER: { [string]: string } = {}
for _, cat in CATEGORIES do
	CAT_LETTER[cat.id] = utf8.char(utf8.codepoint(cat.name, 1))
end

local DOCK_H = 156
local dock = Skin.panel(gui, UDim2.new(1, -380, 0, DOCK_H), UDim2.new(0.5, 0, 1, -8))
dock.AnchorPoint = Vector2.new(0.5, 1)
-- ── 重建星球(左下,中央螢幕按鈕上方)+ 確認框 ──
local rebuildEv = Remotes.get("RebuildPlanet")
local rebuildBtn = Skin.iconButton(gui, "🔄", "重建星球", "gray", UDim2.new(0, 10, 1, -114))
rebuildBtn.Name = "RebuildButton"
local confirm = Skin.panel(modalGui, UDim2.fromOffset(440, 176), UDim2.new(0.5, 0, 0.5, 0), Color3.fromRGB(255, 120, 90))
confirm.AnchorPoint = Vector2.new(0.5, 0.5)
confirm.Visible = false
Skin.text(confirm, "確定要重建星球嗎?", UDim2.new(1, -24, 0, 36), UDim2.fromOffset(12, 10), 28)
local confirmBody = Skin.text(confirm, "指揮中心以外的建築全部拆掉,\n蓋的和升級花的資源全數退還,可以重新規劃。", UDim2.new(1, -24, 0, 56), UDim2.fromOffset(12, 50), 20)
confirmBody.Font = Skin.FONT_BODY
local okBtn = Skin.button(confirm, "確定重建", "red", UDim2.fromOffset(150, 42), UDim2.new(0.5, -160, 1, -56))
local cancelBtn = Skin.button(confirm, "取消", "gray", UDim2.fromOffset(150, 42), UDim2.new(0.5, 10, 1, -56))
rebuildBtn.Activated:Connect(function()
	confirm.Visible = true
end)
-- 只有星球主人看得到重建鈕(訪客按了也沒用)
local inTrip = false
local function refreshRebuild()
	rebuildBtn.Visible = workspace:GetAttribute("OwnerUserId") == player.UserId and not inTrip
end
workspace:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshRebuild)
refreshRebuild()
cancelBtn.Activated:Connect(function()
	confirm.Visible = false
end)
okBtn.Activated:Connect(function()
	confirm.Visible = false
	log("請求重建星球")
	rebuildEv:FireServer()
end)

-- ── 建造面板收合(省畫面空間):面板右上「▼」或鍵盤 B 收起;收起後下方只剩「🔨 建造 (B)」──
local dockOpen = true
local buildBtn = Skin.button(gui, "🔨 建造 (B)", "orange", UDim2.fromOffset(170, 46), UDim2.new(0.5, -85, 1, -58))
buildBtn.Name = "BuildButton"
local collapseBtn = Skin.button(dock, "▼", "gray", UDim2.fromOffset(38, 30), UDim2.new(1, -46, 0, 9))
collapseBtn.Name = "CollapseButton"
-- 說明浮框(滑過卡片 / 剛展開時才出現,不常駐佔空間)
local infoBox = Skin.panel(gui, UDim2.fromOffset(560, 30), UDim2.new(0.5, 0, 1, -(DOCK_H + 14)))
infoBox.AnchorPoint = Vector2.new(0.5, 1)
infoBox.Visible = false
local info = Skin.text(infoBox, "", UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3), 16)
info.Font = Skin.FONT_BODY
info.TextColor3 = Color3.fromRGB(255, 236, 190)
local HINT = "左鍵點格子蓋選中的建築 · 右鍵點建築拆除 · Shift+左鍵升級 · B 收起"
local hintToken = 0
local function showHint()
	hintToken += 1
	local my = hintToken
	info.Text = HINT
	infoBox.Visible = dock.Visible
	task.delay(4, function()
		if my == hintToken then
			infoBox.Visible = false
		end
	end)
end
-- 只有在自己的星球、不在穿梭中才能蓋(伺服器也會擋)
local function refreshDock()
	local can = workspace:GetAttribute("OwnerUserId") == player.UserId and not inTrip
	dock.Visible = can and dockOpen
	buildBtn.Visible = can and not dockOpen
	if not dock.Visible then
		infoBox.Visible = false
	end
end
local function setDock(open: boolean)
	dockOpen = open
	refreshDock()
	if open then
		showHint()
	end
	log("建造面板", if open then "展開" else "收起")
end
buildBtn.Activated:Connect(function()
	setDock(true)
end)
collapseBtn.Activated:Connect(function()
	setDock(false)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B and workspace:GetAttribute("OwnerUserId") == player.UserId and not inTrip then
		setDock(not dockOpen)
	end
end)
workspace:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshDock)
refreshDock()

-- 穿梭中不能蓋(伺服器也會擋):收起建造面板與重建按鈕,畫面留給採集
Remotes.get("TripChanged").OnClientEvent:Connect(function(info)
	inTrip = info ~= nil
	refreshDock()
	refreshRebuild()
	if info then
		confirm.Visible = false
	end
end)


local tabRow = Instance.new("Frame")
tabRow.BackgroundTransparency = 1
tabRow.Size = UDim2.new(1, -20, 0, 34)
tabRow.Position = UDim2.fromOffset(10, 8)
tabRow.Parent = dock
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.Size = UDim2.new(1, -16, 0, 110)
scroller.Position = UDim2.fromOffset(8, 44)
scroller.ScrollingDirection = Enum.ScrollingDirection.X
scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
scroller.CanvasSize = UDim2.new()
scroller.ScrollBarThickness = 6
scroller.ScrollBarImageColor3 = Color3.fromRGB(255, 214, 120)
scroller.Parent = dock
local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Horizontal
cardLayout.Padding = UDim.new(0, 8)
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
cardLayout.Parent = scroller
local cardPad = Instance.new("UIPadding")
cardPad.PaddingLeft, cardPad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
cardPad.Parent = scroller

type Card = { def: any, button: ImageButton, glow: GuiObject, dim: Frame, badge: Frame }
local cards: { Card } = {}
local tabBadges: { [string]: Frame } = {} -- 分頁右上角紅點:這一類有任何一張買得起
local currentCat = Buildings.Types[1].category

local function atLimit(def: any): boolean
	local limit = Build.MAX_PER_TYPE[def.id]
	return limit ~= nil and (owned[def.id] or 0) >= limit
end

local function canAfford(def: any): boolean
	for id, n in def.cost do
		if (inventory[id] or 0) < n then
			return false
		end
	end
	return true
end

local function refreshCards()
	for _, c in cards do
		c.button.Visible = c.def.category == currentCat
		c.glow.Visible = c.def.id == selected
		local ok = canAfford(c.def) and not atLimit(c.def) -- 已擁有(例:送的時空門)不亮紅點
		c.dim.Visible = not ok
		c.badge.Visible = ok -- 材料夠:右上角紅點
	end
	-- 分頁紅點:這一類只要有一張買得起就亮
	local any: { [string]: boolean } = {}
	for _, c in cards do
		if c.badge.Visible then
			any[c.def.category] = true
		end
	end
	for cat, d in tabBadges do
		d.Visible = any[cat] == true
	end
end

local function describe(def: any): string
	local bits = { def.name, "T" .. (def.tier or 1) }
	if def.power > 0 then
		table.insert(bits, "⚡發電 +" .. def.power)
	elseif def.power < 0 then
		table.insert(bits, "⚡耗電 " .. -def.power)
	end
	if def.dps then
		table.insert(bits, "攻擊 " .. def.dps)
	end
	if def.shield then
		table.insert(bits, "護盾 " .. def.shield)
	end
	if def.wallHp then
		table.insert(bits, "城牆 " .. def.wallHp)
	end
	if def.yield then
		table.insert(bits, "採集 ×" .. def.yield)
	end
	if atLimit(def) then
		table.insert(bits, "(已擁有,只能有一座)")
	elseif not canAfford(def) then
		table.insert(bits, "(資源不夠)")
	end
	return table.concat(bits, "  ·  ")
end

for i, def in Buildings.Types do
	if def.hidden then
		continue -- 指揮中心等開局贈送的建築不能自己蓋
	end
	local card = Skin.card(scroller, def.tier or 1, UDim2.fromOffset(100, 104))
	card.LayoutOrder = i
	Skin.icon(card, "cat_" .. def.category, UDim2.fromOffset(40, 40), UDim2.new(0.5, -20, 0, 4), CAT_LETTER[def.category], CAT_COLOR[def.category])
	local name = Skin.text(card, def.name, UDim2.new(1, -8, 0, 20), UDim2.fromOffset(4, 45), 17)
	name.ZIndex = 2
	-- 花費:小圖示 + 數字,最多 5 種排兩行
	local cost = Instance.new("Frame")
	cost.BackgroundTransparency = 1
	cost.Size = UDim2.new(1, -8, 0, 36)
	cost.Position = UDim2.fromOffset(4, 66)
	cost.Parent = card
	local cg = Instance.new("UIGridLayout")
	cg.CellSize = UDim2.fromOffset(44, 17)
	cg.CellPadding = UDim2.fromOffset(2, 1)
	cg.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cg.Parent = cost
	for id, n in def.cost do
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Parent = cost
		itemIcon(cell, id, UDim2.fromOffset(16, 16))
		local t = Skin.text(cell, tostring(n), UDim2.new(1, -18, 1, 0), UDim2.fromOffset(18, 0), 15)
		t.TextXAlignment = Enum.TextXAlignment.Left
	end
	-- 買不起:蓋一層暗色(仍可選,點格子時伺服器會提示資源不夠)
	local dim = Instance.new("Frame")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.55
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 2
	dim.Visible = false
	dim.Parent = card
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(0, 12)
	dc.Parent = dim
	local glow = Skin.selectGlow(card)
	local badge = Skin.badge(card)
	card.Activated:Connect(function()
		selected = def.id
		log("選擇建築", def.id)
		refreshCards()
	end)
	card.MouseEnter:Connect(function()
		hintToken += 1
		info.Text = describe(def)
		infoBox.Visible = true
	end)
	card.MouseLeave:Connect(function()
		infoBox.Visible = false
	end)
	table.insert(cards, { def = def, button = card, glow = glow, dim = dim, badge = badge })
end

local tabButtons: { [string]: ImageButton } = {}
local function refreshTabs()
	for id, b in tabButtons do
		Skin.tab(b, id == currentCat)
	end
end
for i, cat in CATEGORIES do
	local b = Instance.new("ImageButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(92, 34)
	b.LayoutOrder = i
	b.Parent = tabRow
	Skin.icon(b, "cat_" .. cat.id, UDim2.fromOffset(26, 26), UDim2.fromOffset(6, 4), nil, CAT_COLOR[cat.id])
	Skin.text(b, cat.name, UDim2.new(1, -40, 1, -6), UDim2.fromOffset(36, 3), 20)
	b.Activated:Connect(function()
		currentCat = cat.id
		scroller.CanvasPosition = Vector2.zero
		refreshTabs()
		refreshCards()
	end)
	tabButtons[cat.id] = b
	tabBadges[cat.id] = Skin.badge(b)
end
refreshTabs()
refreshCards()

stateEv.OnClientEvent:Connect(function(s)
	inventory = s.Inventory
	if s.Slots then
		owned = {}
		for _, slot in s.Slots do
			owned[slot.Id] = (owned[slot.Id] or 0) + 1
		end
	end
	local any = false
	for id, chip in chips do
		local n = s.Inventory[id] or 0
		chip.frame.Visible = n > 0
		chip.num.Text = compact(n)
		any = any or n > 0
	end
	invEmpty.Visible = not any
	refreshCards()
end)
noticeEv.OnClientEvent:Connect(showToast)

-- ── 蓋建築前確認(避免點錯就把資源花掉)──
local defById: { [string]: any } = {}
for _, d in Buildings.Types do
	defById[d.id] = d
end
-- 放畫面正中(原本 0.3 會壓到左上聊天列/語音麥克風,那是 CoreGui,永遠在最上層)
local buildAsk = Skin.panel(modalGui, UDim2.fromOffset(420, 196), UDim2.new(0.5, 0, 0.5, 0), Color3.fromRGB(120, 220, 140))
buildAsk.Name = "BuildConfirm"
buildAsk.AnchorPoint = Vector2.new(0.5, 0.5)
buildAsk.Visible = false
local askTitle = Skin.text(buildAsk, "", UDim2.new(1, -24, 0, 34), UDim2.fromOffset(12, 10), 26)
local askCost = Instance.new("Frame")
askCost.BackgroundTransparency = 1
askCost.Size = UDim2.new(1, -24, 0, 30)
askCost.Position = UDim2.fromOffset(12, 50)
askCost.Parent = buildAsk
local askLayout = Instance.new("UIListLayout")
askLayout.FillDirection = Enum.FillDirection.Horizontal
askLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
askLayout.Padding = UDim.new(0, 12)
askLayout.Parent = askCost
local askSkip = Instance.new("TextButton")
askSkip.Name = "SkipConfirm"
askSkip.BackgroundTransparency = 1
askSkip.Size = UDim2.new(1, -24, 0, 24)
askSkip.Position = UDim2.fromOffset(12, 86)
askSkip.Font = Skin.FONT_BODY
askSkip.TextSize = 15
askSkip.TextColor3 = Color3.fromRGB(200, 210, 235)
askSkip.Text = "☐ 之後不用再確認(這次遊戲中)"
askSkip.Parent = buildAsk
local askOk = Skin.button(buildAsk, "確定建造", "green", UDim2.fromOffset(150, 42), UDim2.new(0.5, -160, 1, -54))
askOk.Name = "ConfirmBuild"
local askNo = Skin.button(buildAsk, "取消", "gray", UDim2.fromOffset(150, 42), UDim2.new(0.5, 10, 1, -54))
askNo.Name = "CancelBuild"

local pendingKey: string? = nil
local pendingId: string? = nil
local highlight: Instance? = nil
local skipConfirm = false

local function closeAsk()
	buildAsk.Visible = false
	pendingKey, pendingId = nil, nil
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

-- 左鍵點空格:材料夠就跳確認框(並把那一格框亮),不夠/已擁有直接提示
local function askBuild(key: string, marker: Instance)
	local def = defById[selected]
	if not def then
		return
	end
	if atLimit(def) then
		showToast("已經有「" .. def.name .. "」了,只能有一座")
		return
	end
	if not canAfford(def) then
		showToast("資源不夠蓋「" .. def.name .. "」")
		return
	end
	if skipConfirm then
		placeEv:FireServer(key, selected)
		return
	end
	closeAsk()
	pendingKey, pendingId = key, selected
	askTitle.Text = ("要在這裡蓋「%s」嗎?"):format(def.name)
	for _, c in askCost:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for id, n in def.cost do
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.fromOffset(78, 28)
		cell.Parent = askCost
		itemIcon(cell, id, UDim2.fromOffset(26, 26), UDim2.fromOffset(0, 1))
		local t = Skin.text(cell, "-" .. n, UDim2.new(1, -30, 1, 0), UDim2.fromOffset(30, 0), 20)
		t.TextXAlignment = Enum.TextXAlignment.Left
	end
	-- 框亮要蓋的格子(只在自己畫面)
	pcall(function()
		local h = Instance.new("Highlight")
		h.FillColor = Color3.fromRGB(120, 255, 150)
		h.FillTransparency = 0.35
		h.OutlineColor = Color3.new(1, 1, 1)
		h.Adornee = marker
		h.Parent = marker
		highlight = h
	end)
	buildAsk.Visible = true
	log("確認建造?", def.id, "@", key)
end

askOk.Activated:Connect(function()
	if pendingKey and pendingId then
		log("確定建造", pendingId, "@", pendingKey)
		placeEv:FireServer(pendingKey, pendingId)
	end
	closeAsk()
end)
askNo.Activated:Connect(closeAsk)
askSkip.Activated:Connect(function()
	skipConfirm = not skipConfirm
	askSkip.Text = (if skipConfirm then "☑" else "☐") .. " 之後不用再確認(這次遊戲中)"
end)
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape and buildAsk.Visible then
		closeAsk()
	end
end)

-- 測試掛勾(只在 Studio / 離線模擬器建立):模擬「左鍵點了某一格」,test/wave-check.js 用它驗證確認框流程
if game:GetService("RunService"):IsStudio() then
	local hook = Instance.new("BindableEvent")
	hook.Name = "TestClickSlot"
	hook.Event:Connect(function(key: string)
		local markers = workspace:FindFirstChild("SlotMarkers")
		local m = markers and markers:FindFirstChild(key)
		if m then
			askBuild(key, m)
		end
	end)
	hook.Parent = gui
end

-- 點擊:對 SlotMarkers(空格)與 Buildings(已蓋)做射線
local function pick(position: Vector2): Instance?
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(position.X, position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include = {}
	local markers = workspace:FindFirstChild("SlotMarkers")
	local built = workspace:FindFirstChild("Buildings")
	if markers then
		table.insert(include, markers)
	end
	if built then
		table.insert(include, built)
	end
	params.FilterDescendantsInstances = include
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	return if hit then hit.Instance else nil
end

-- 由被點到的建築反查它所在的格位:找最近的 marker
local function slotKeyOf(inst: Instance): string?
	local model = inst:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("SlotKey") then
		return model:GetAttribute("SlotKey") :: string
	end
	local markers = workspace:FindFirstChild("SlotMarkers")
	if not markers then
		return nil
	end
	if inst.Parent == markers then
		return inst.Name
	end
	if inst:IsA("BasePart") then
		local best, bestD = nil, math.huge
		for _, m in markers:GetChildren() do
			local d = ((m :: BasePart).Position - inst.Position).Magnitude
			if d < bestD then
				best, bestD = m.Name, d
			end
		end
		return best
	end
	return nil
end

-- 右鍵同時是「拖曳轉視角」(SphereGravity):放開時沒拖動才算「點一下拆除」
local rmbStart: Vector2? = nil
local rmbDragged = false
local rmbMoved = 0
local DRAG_PX = 6

local function onClick(isLeft: boolean, isRight: boolean, at: Vector2)
	local hit = pick(at)
	if not hit then
		return
	end
	local key = slotKeyOf(hit)
	if not key then
		return
	end
	if isLeft and hit.Parent and hit.Parent.Name == "SlotMarkers" then
		askBuild(key, hit) -- 先確認,不直接花資源
	elseif isRight and workspace:FindFirstChild("Buildings") and hit:IsDescendantOf(workspace.Buildings :: Instance) then
		removeEv:FireServer(key)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		onClick(true, false, UserInputService:GetMouseLocation())
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		rmbStart = UserInputService:GetMouseLocation()
		rmbDragged = false
		rmbMoved = 0
	end
end)

UserInputService.InputChanged:Connect(function(input)
	-- 右鍵按住時滑鼠被鎖住不動,只能從 Delta 判斷有沒有拖
	if rmbStart and input.UserInputType == Enum.UserInputType.MouseMovement then
		rmbMoved += input.Delta.Magnitude
		rmbDragged = rmbMoved > DRAG_PX -- 累積移動超過幾像素才算拖(小抖動不算)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and rmbStart then
		local at = rmbStart :: Vector2
		rmbStart = nil
		if not rmbDragged then
			onClick(false, true, at)
		end
	end
end)

-- 依視窗大小等比縮放整個介面(小視窗不擠、不超出)
Skin.autoScale(gui)
