--!strict
-- 介面外觀:統一做按鈕 / 面板 / 卡片 / 圖示。
-- 每個元件一律先畫「備用樣式」(圓角 + 描邊 + 漸層);有上傳的圖(Data/UiAssets,由 publish/upload-assets.ps1 產生)
-- 會先設好但保持隱形,等 ContentProvider 確認「真的載入成功」才換成 N1 素材、收掉備用樣式。
-- → 圖片還在 Roblox 審核中、被拒、或網路慢時,介面仍是完整的色塊樣式,不會變透明。
-- 載入失敗會每 RETRY_SEC 秒重試(審核通過後自動換上素材,不用重進遊戲)。
-- 只給 client 用(會建 GuiObject);伺服器不要 require。

local ContentProvider = game:GetService("ContentProvider")
local UiAssets = require(script.Parent.Parent.Data.UiAssets) :: any

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[Skin]", ...)
	end
end

local Skin = {}

-- 字型對齊 N1(Noto Sans Condensed Bold):Roblox 不能上傳自訂字型,英數用最接近的粗黑體,
-- 中文本來就由 Roblox 內建的 Noto/思源黑體顯示。
Skin.FONT = Enum.Font.BuilderSansBold
Skin.FONT_BODY = Enum.Font.BuilderSansBold
Skin.TEXT_SCALE = 0.78 -- 所有文字上限的縮放(中文字小一點,比較像 N1 的介面)
Skin.STROKE_COLOR = Color3.fromRGB(7, 7, 7) -- N1 文字外框:近黑、半透明
Skin.STROKE_TRANSPARENCY = 0.45
Skin.RETRY_SEC = 60 -- 圖片載入失敗(多半是還在審核)多久後再試
Skin.MAX_RETRY = 60 -- 最多重試幾次(約一小時)

-- 按鈕顏色:有對應素材 btn_<名稱>;沒有素材的顏色(purple)用灰色素材染色
local BUTTON_COLOR: { [string]: Color3 } = {
	blue = Color3.fromRGB(40, 140, 235),
	green = Color3.fromRGB(60, 190, 80),
	red = Color3.fromRGB(225, 60, 70),
	orange = Color3.fromRGB(245, 150, 30),
	gold = Color3.fromRGB(240, 190, 60),
	gray = Color3.fromRGB(120, 128, 150),
	white = Color3.fromRGB(250, 246, 235),
	purple = Color3.fromRGB(140, 90, 235),
}
Skin.BUTTON_COLOR = BUTTON_COLOR

-- 建築 tier → 卡片底色(對應 card_t1~t5:灰/綠/藍/紫/金)
Skin.TIER_COLOR = {
	Color3.fromRGB(170, 176, 190),
	Color3.fromRGB(70, 185, 120),
	Color3.fromRGB(50, 150, 220),
	Color3.fromRGB(175, 95, 225),
	Color3.fromRGB(230, 185, 50),
}

-- 資源稀有度 → 備用圖示底色
Skin.RARITY_COLOR = {
	common = Color3.fromRGB(130, 140, 160),
	uncommon = Color3.fromRGB(70, 180, 110),
	rare = Color3.fromRGB(60, 140, 230),
	epic = Color3.fromRGB(170, 90, 230),
}

-- 九宮格切片(以 128px 素材為準,四周約 40px 是圓角+陰影)
local SLICE: { [string]: Rect } = {
	default = Rect.new(48, 48, 80, 80),
	ribbon = Rect.new(40, 20, 88, 44),
	title_banner = Rect.new(64, 20, 192, 44),
}

-- 取得圖片網址;沒上傳回 nil
function Skin.image(key: string): string?
	local e = UiAssets[key]
	if not e then
		return nil
	end
	if e.kind == "image" then
		return "rbxassetid://" .. e.id
	end
	-- 只有 Decal ID:用縮圖服務顯示(不能九宮格,只適合圖示)
	return "rbxthumb://type=Asset&id=" .. e.id .. "&w=150&h=150"
end

-- 能不能九宮格縮放(要真正的 Image ID)
function Skin.sliceable(key: string): boolean
	local e = UiAssets[key]
	return e ~= nil and e.kind == "image"
end

-- ── 圖片載入確認:同一張圖只檢查一次,成功後通知所有等待的元件 ──
local loadState: { [string]: string } = {} -- url → "loading" | "ok" | "wait"(失敗、等下次重試)
local waiters: { [string]: { () -> () } } = {}

local function fetch(url: string): boolean
	local ok = false
	pcall(function()
		ContentProvider:PreloadAsync({ url }, function(_, status)
			ok = status == Enum.AssetFetchStatus.Success
		end)
	end)
	return ok
end

-- url 確認載入成功後呼叫 fn(已成功過就立刻呼叫;永遠失敗就永遠不呼叫)
function Skin.whenLoaded(url: string, fn: () -> ())
	if loadState[url] == "ok" then
		fn()
		return
	end
	local list = waiters[url]
	if not list then
		list = {}
		waiters[url] = list
	end
	table.insert(list, fn)
	if loadState[url] ~= nil then
		return -- 已經在檢查/重試中
	end
	loadState[url] = "loading"
	task.spawn(function()
		for attempt = 1, Skin.MAX_RETRY do
			if fetch(url) then
				loadState[url] = "ok"
				local fns = waiters[url] or {}
				waiters[url] = nil
				if attempt > 1 then
					log("圖片載入成功(第", attempt, "次):", url)
				end
				for _, f in fns do
					task.spawn(f)
				end
				return
			end
			loadState[url] = "wait"
			if attempt == 1 then
				log("圖片還不能用(可能在審核中),先用備用樣式,", Skin.RETRY_SEC, "秒後再試:", url)
			end
			task.wait(Skin.RETRY_SEC)
		end
		log("圖片放棄載入,維持備用樣式:", url)
	end)
end

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thick: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thick
	s.Transparency = transparency or 0
	s.Parent = parent
end

-- 上亮下暗的光澤漸層(配合 BackgroundColor3 使用)
local function gloss(parent: Instance, strength: number?)
	local g = Instance.new("UIGradient")
	local k = strength or 0.25
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1 - k, 1 - k, 1 - k))
	g.Rotation = 90
	g.Parent = parent
end

local function darker(c: Color3, f: number): Color3
	return Color3.new(c.R * f, c.G * f, c.B * f)
end
Skin.darker = darker

-- 備用樣式:色塊 + 圓角 + 描邊 + 光澤(radius 999 = 膠囊形)
local function fallbackStyle(obj: GuiObject, color: Color3, radius: number, strokeDark: number, glossK: number)
	obj.BackgroundTransparency = 0
	obj.BackgroundColor3 = color
	corner(obj, radius)
	stroke(obj, darker(color, strokeDark), 2)
	gloss(obj, glossK)
end

-- 改備用樣式的顏色(底色 + 描邊)
local function fallbackColor(obj: GuiObject, color: Color3, strokeDark: number)
	obj.BackgroundColor3 = color
	local s = obj:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = darker(color, strokeDark)
	end
end

-- 圖片確認載入後:顯示圖片、收掉備用樣式
-- 注意:不能檢查 obj.Parent —— 圖片已載入過時會立刻呼叫,那時元件通常還沒放進畫面
local function reveal(obj: ImageLabel | ImageButton)
	obj.ImageTransparency = 0
	obj.BackgroundTransparency = 1
	for _, c in obj:GetChildren() do
		if c:IsA("UICorner") then
			c:Destroy() -- 圓角會把素材的邊角裁掉
		elseif c:IsA("UIStroke") or c:IsA("UIGradient") then
			c.Enabled = false
		elseif c.Name == "FallbackText" and c:IsA("GuiObject") then
			c.Visible = false
		end
	end
	obj:SetAttribute("SpriteShown", true)
end

-- 掛上素材(先隱形,載入成功才顯示);沒有可用素材回 false
local function spriteLater(obj: ImageLabel | ImageButton, key: string, slice: boolean, tint: Color3?): boolean
	if slice and not Skin.sliceable(key) then
		return false
	end
	local url = Skin.image(key)
	if not url then
		return false
	end
	obj.Image = url
	obj.ImageTransparency = 1
	obj.ImageColor3 = tint or Color3.new(1, 1, 1)
	if slice then
		obj.ScaleType = Enum.ScaleType.Slice
		obj.SliceCenter = SLICE[key] or SLICE.default
		obj.SliceScale = 0.4
	else
		obj.ScaleType = Enum.ScaleType.Fit
	end
	Skin.whenLoaded(url, function()
		reveal(obj)
	end)
	return true
end

-- 文字:白字 + 深色描邊,任何底色都看得清楚
function Skin.text(parent: Instance, text: string, size: UDim2, pos: UDim2?, maxSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos or UDim2.new()
	l.Font = Skin.FONT
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeColor3 = Skin.STROKE_COLOR
	l.TextStrokeTransparency = Skin.STROKE_TRANSPARENCY
	l.TextScaled = true
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = math.max(8, math.floor((maxSize or 26) * Skin.TEXT_SCALE + 0.5))
	c.Parent = l
	return l
end

-- 按下縮一下、滑過放大一點
local function pressFeedback(b: GuiButton)
	local s = Instance.new("UIScale")
	s.Parent = b
	b.MouseEnter:Connect(function()
		s.Scale = 1.04
	end)
	b.MouseLeave:Connect(function()
		s.Scale = 1
	end)
	b.MouseButton1Down:Connect(function()
		s.Scale = 0.94
	end)
	b.MouseButton1Up:Connect(function()
		s.Scale = 1.04
	end)
end

-- 按鈕素材:有這個顏色就用,沒有就灰色素材染色
local function buttonSprite(b: ImageButton, color: string)
	local base = BUTTON_COLOR[color] or BUTTON_COLOR.blue
	if not spriteLater(b, "btn_" .. color, true) then
		spriteLater(b, "btn_gray", true, base)
	end
end

-- 卡通按鈕;回傳 (按鈕, 文字)
function Skin.button(parent: Instance, text: string, color: string, size: UDim2, pos: UDim2?): (ImageButton, TextLabel)
	local b = Instance.new("ImageButton")
	b.AutoButtonColor = false
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BorderSizePixel = 0
	fallbackStyle(b, BUTTON_COLOR[color] or BUTTON_COLOR.blue, 12, 0.55, 0.25)
	buttonSprite(b, color)
	b.Parent = parent
	local label = Skin.text(b, text, UDim2.new(1, -14, 1, -8), UDim2.new(0, 7, 0, 3), 26)
	if color == "white" or color == "gold" then
		label.TextColor3 = Color3.fromRGB(70, 45, 20)
		label.TextStrokeTransparency = 1
	end
	pressFeedback(b)
	return b, label
end

-- 圓形圖示按鈕(省畫面空間):只顯示一個符號,滑過才在右邊浮出說明。回傳 (按鈕, 說明文字)
function Skin.iconButton(parent: Instance, glyph: string, tip: string, color: string, pos: UDim2): (ImageButton, TextLabel)
	local b, label = Skin.button(parent, glyph, color, UDim2.fromOffset(48, 48), pos)
	label.Size = UDim2.new(1, -8, 1, -8)
	label.Position = UDim2.fromOffset(4, 4)
	local c = label:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = 28
	end
	local tipBox = Instance.new("TextLabel")
	tipBox.Name = "Tip"
	tipBox.AutomaticSize = Enum.AutomaticSize.X
	tipBox.Size = UDim2.fromOffset(0, 30)
	tipBox.Position = UDim2.new(1, 8, 0.5, -15)
	tipBox.BackgroundColor3 = Color3.fromRGB(22, 26, 52)
	tipBox.BackgroundTransparency = 0.1
	tipBox.Font = Skin.FONT_BODY
	tipBox.TextSize = 16
	tipBox.TextColor3 = Color3.new(1, 1, 1)
	tipBox.Text = "  " .. tip .. "  "
	tipBox.Visible = false
	tipBox.ZIndex = 8
	corner(tipBox, 8)
	tipBox.Parent = b
	b.MouseEnter:Connect(function()
		tipBox.Visible = true
	end)
	b.MouseLeave:Connect(function()
		tipBox.Visible = false
	end)
	return b, tipBox
end

-- 改按鈕顏色(例:緊急時變紅);素材與備用樣式一起換,不管目前顯示哪個都對
function Skin.recolor(b: ImageButton, color: string)
	local base = BUTTON_COLOR[color] or BUTTON_COLOR.blue
	fallbackColor(b, base, 0.55)
	local key = if Skin.sliceable("btn_" .. color) then "btn_" .. color elseif Skin.sliceable("btn_gray") then "btn_gray" else nil
	if not key then
		return
	end
	local url = Skin.image(key) :: string
	b:SetAttribute("WantImage", url)
	-- 新素材確認載入後才換圖(避免換到還在審核的圖而變空白)
	Skin.whenLoaded(url, function()
		if b:GetAttribute("WantImage") == url then
			b.Image = url
			b.ImageColor3 = if key == "btn_gray" and color ~= "gray" then base else Color3.new(1, 1, 1)
		end
	end)
end

-- 深色半透明面板(HUD 用,不用素材)
function Skin.panel(parent: Instance, size: UDim2, pos: UDim2?, accent: Color3?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos or UDim2.new()
	f.BackgroundColor3 = Color3.fromRGB(22, 26, 52)
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	corner(f, 14)
	stroke(f, accent or Color3.fromRGB(255, 214, 120), 2, 0.25)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 195, 230))
	g.Rotation = 90
	g.Parent = f
	f.Parent = parent
	return f
end

-- 圖示:先畫彩色圓 + 一個字,素材載入成功才換成圖
function Skin.icon(parent: Instance, key: string, size: UDim2, pos: UDim2?, fallbackText: string?, fallbackColorValue: Color3?): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Size = size
	img.Position = pos or UDim2.new()
	img.BorderSizePixel = 0
	img.BackgroundTransparency = 0
	img.BackgroundColor3 = fallbackColorValue or Color3.fromRGB(120, 130, 160)
	corner(img, 999)
	stroke(img, Color3.new(1, 1, 1), 1.5, 0.3)
	gloss(img, 0.35)
	if fallbackText and fallbackText ~= "" then
		local t = Skin.text(img, fallbackText, UDim2.fromScale(1, 1), nil, 20)
		t.Name = "FallbackText"
	end
	spriteLater(img, key, false)
	img.Parent = parent
	return img
end

-- 建築卡片底(依 tier 1~5)
function Skin.card(parent: Instance, tier: number, size: UDim2): ImageButton
	local b = Instance.new("ImageButton")
	b.AutoButtonColor = false
	b.Size = size
	b.BorderSizePixel = 0
	local t = math.clamp(tier, 1, 5)
	fallbackStyle(b, Skin.TIER_COLOR[t], 12, 0.5, 0.35)
	spriteLater(b, "card_t" .. t, true)
	b.Parent = parent
	pressFeedback(b)
	return b
end

-- 依視窗大小等比縮放整個介面:介面以 1280×720 設計,視窗小就整體縮小(比例不變、不會互相重疊或超出)。
-- 做法:ScreenGui 底下建一個置中的 Root(大小 = 1/s 倍畫面)+ UIScale s → 縮放後剛好填滿畫面;
-- 呼叫前已建好的元件搬進 Root,之後直接加到 ScreenGui 的也會自動搬進去。回傳 Root。
Skin.DESIGN_W, Skin.DESIGN_H = 1280, 720
Skin.MIN_SCALE = 0.5
function Skin.autoScale(gui: ScreenGui): Frame
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	local sc = Instance.new("UIScale")
	sc.Parent = root
	local function update()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(Skin.DESIGN_W, Skin.DESIGN_H)
		local s = math.clamp(math.min(vp.X / Skin.DESIGN_W, vp.Y / Skin.DESIGN_H), Skin.MIN_SCALE, 1)
		sc.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	update()
	for _, c in gui:GetChildren() do
		if c:IsA("GuiObject") then
			c.Parent = root
		end
	end
	root.Parent = gui
	gui.ChildAdded:Connect(function(c)
		if c ~= root and c:IsA("GuiObject") then
			task.defer(function()
				c.Parent = root
			end)
		end
	end)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return root
end

-- 右上角紅點(提示「可以做了」);預設隱藏,呼叫端控制 Visible
function Skin.badge(parent: Instance): Frame
	local d = Instance.new("Frame")
	d.Name = "Badge"
	d.Size = UDim2.fromOffset(14, 14)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.new(1, -5, 0, 5)
	d.BackgroundColor3 = Color3.fromRGB(240, 50, 50)
	d.BorderSizePixel = 0
	d.ZIndex = 6
	d.Visible = false
	corner(d, 999)
	stroke(d, Color3.new(1, 1, 1), 2)
	d.Parent = parent
	return d
end

-- 選中外框:金色粗描邊(素材 img_select 是實心方塊,蓋上去會把卡片洗掉,所以不用素材)
function Skin.selectGlow(parent: Instance): GuiObject
	local f = Instance.new("Frame")
	f.Name = "SelectGlow"
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 6, 1, 6)
	f.Position = UDim2.new(0, -3, 0, -3)
	f.ZIndex = 3
	corner(f, 14)
	stroke(f, Color3.fromRGB(255, 226, 90), 4)
	f.Parent = parent
	return f
end

-- 彩帶底(任務目標)/ 標題橫幅(戰鬥結果)
function Skin.banner(parent: Instance, key: string, size: UDim2, pos: UDim2?, color: Color3): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Size = size
	img.Position = pos or UDim2.new()
	img.BorderSizePixel = 0
	fallbackStyle(img, color, 999, 0.5, 0.3)
	if spriteLater(img, key, true) then
		img.SliceScale = 0.6
	end
	img.Parent = parent
	return img
end

-- 分頁按鈕外觀切換:選中 = 金色,其他 = 暗藍灰(素材與備用樣式一起換)
local TAB_OFF = Color3.fromRGB(70, 82, 120)
function Skin.tab(b: ImageButton, on: boolean)
	local c = if on then BUTTON_COLOR.gold else TAB_OFF
	local hasSprites = Skin.sliceable("btn_gold") and Skin.sliceable("btn_gray")
	if not b:GetAttribute("TabStyled") then
		b:SetAttribute("TabStyled", true)
		fallbackStyle(b, c, 12, 0.5, 0.3)
		if hasSprites then
			b.ImageTransparency = 1
			b.ScaleType = Enum.ScaleType.Slice
			b.SliceCenter = SLICE.default
			b.SliceScale = 0.4
			-- 分頁會在金/灰兩張素材間切換:兩張都載入成功才顯示素材
			Skin.whenLoaded(Skin.image("btn_gray") :: string, function()
				Skin.whenLoaded(Skin.image("btn_gold") :: string, function()
					reveal(b)
				end)
			end)
		end
	end
	fallbackColor(b, c, 0.5)
	if hasSprites then
		b.Image = Skin.image(if on then "btn_gold" else "btn_gray") :: string
		b.ImageColor3 = if on then Color3.new(1, 1, 1) else TAB_OFF
	end
end

return Skin
