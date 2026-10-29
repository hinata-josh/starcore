--!strict
-- 怪獸外觀產生器:用基本零件組出 5 種怪(酸液蟲/巨甲獸/飛行刃蛾/電漿幼龍/裂縫巨獸)。
-- 結構:Root(錨定、隱形,原點在腳底,-Z 是臉朝的方向)+ 其他零件用 Weld 掛在 Root 上。
-- 移動只要改 Root.CFrame,整隻跟著走;翅膀拍動改 Weld.C0(MonsterModel.animate 每幀呼叫)。
-- 零件全部不碰撞、不可射線點選(不會擋到建造點擊)。

local MonsterModel = {}

export type Monster = {
	model: Model,
	root: BasePart,
	size: number,
	flyHeight: number, -- 飛行怪離地高度(studs)
	wings: { { weld: Weld, base: CFrame, side: number, half: number } },
	glow: { BasePart },
}

local NEON = Enum.Material.Neon

local function newPart(shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- 在 root 上加一個零件;cf 是相對 root 的位置/朝向
local function add(m: Monster, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, transparency: number?): (Part, Weld)
	local p = newPart(shape)
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.CFrame = m.root.CFrame * cf
	local w = Instance.new("Weld")
	w.Part0 = m.root
	w.Part1 = p
	w.C0 = cf
	w.Parent = p
	p.Parent = m.model
	if p.Material == NEON then
		table.insert(m.glow, p)
	end
	return p, w
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 2
	l.Parent = parent
end

local function eyes(m: Monster, y: number, z: number, gap: number, r: number, color: Color3)
	for _, sx in { -1, 1 } do
		add(m, Vector3.one * r, CFrame.new(sx * gap, y, z), color, NEON, Enum.PartType.Ball)
	end
end

local function wing(m: Monster, size: Vector3, attach: CFrame, side: number, color: Color3, edge: Color3, spot: Color3?)
	-- 翅膀零件的中心往外偏半個翼展,轉軸就在翅根
	local cf = attach * CFrame.new(side * size.X / 2, 0, 0)
	local p, w = add(m, size, cf, color, Enum.Material.Glass, nil, 0.25)
	p.Name = "Wing"
	-- 前緣發光刀刃
	local blade = newPart()
	blade.Size = Vector3.new(size.X, size.Y * 1.5, math.max(0.15, size.Z * 0.12))
	blade.Color = edge
	blade.Material = NEON
	blade.CFrame = p.CFrame * CFrame.new(0, 0, -size.Z / 2)
	local bw = Instance.new("Weld")
	bw.Part0 = p
	bw.Part1 = blade
	bw.C0 = CFrame.new(0, 0, -size.Z / 2)
	bw.Parent = blade
	blade.Parent = m.model
	table.insert(m.glow, blade)
	-- 翅膀上的發光眼紋(圓盤平貼翅面)
	if spot then
		local d = math.min(size.X, size.Z) * 0.55
		local disk = newPart(Enum.PartType.Cylinder)
		disk.Size = Vector3.new(size.Y * 1.6, d, d)
		disk.Color = spot
		disk.Material = NEON
		local off = CFrame.new(side * size.X * 0.12, 0, size.Z * 0.05) * CFrame.Angles(0, 0, math.rad(90))
		disk.CFrame = p.CFrame * off
		local sw = Instance.new("Weld")
		sw.Part0 = p
		sw.Part1 = disk
		sw.C0 = off
		sw.Parent = disk
		disk.Parent = m.model
		table.insert(m.glow, disk)
	end
	table.insert(m.wings, { weld = w, base = attach, side = side, half = size.X / 2 })
end

-- ── 各怪獸造型(u = 整體尺寸,約等於身高)──
local BUILD: { [string]: (m: Monster, u: number) -> () } = {}

BUILD.AcidWorm = function(m, u)
	local body = Color3.fromRGB(110, 205, 70)
	local dark = Color3.fromRGB(55, 120, 40)
	local spot = Color3.fromRGB(190, 255, 90)
	-- 由頭到尾 6 節,越後面越小、上下起伏
	local radii = { 0.62, 0.56, 0.5, 0.44, 0.36, 0.28 }
	local z = 0
	for i, r in radii do
		local y = r * u * 0.5 + (if i % 2 == 0 then 0.06 else 0) * u
		add(m, Vector3.one * r * u, CFrame.new(0, y, z), if i == 1 then dark else body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		if i > 1 then
			add(m, Vector3.one * r * u * 0.35, CFrame.new(0, y + r * u * 0.42, z), spot, NEON, Enum.PartType.Ball)
		end
		z += r * u * 0.62
	end
	-- 頭:發光眼睛 + 兩根顎
	local hy = radii[1] * u * 0.5
	eyes(m, hy + 0.12 * u, -0.26 * u, 0.15 * u, 0.13 * u, Color3.fromRGB(255, 240, 80))
	for _, sx in { -1, 1 } do
		add(m, Vector3.new(0.07, 0.07, 0.3) * u, CFrame.new(sx * 0.13 * u, hy - 0.12 * u, -0.38 * u) * CFrame.Angles(0, sx * math.rad(-25), 0), Color3.fromRGB(240, 235, 200))
	end
	-- 酸液滴
	add(m, Vector3.one * 0.1 * u, CFrame.new(0, hy - 0.26 * u, -0.34 * u), spot, NEON, Enum.PartType.Ball)
	light(m.glow[1], spot, u * 2.5, 1.5)
end

BUILD.Behemoth = function(m, u)
	local skin = Color3.fromRGB(150, 105, 80)
	local shell = Color3.fromRGB(70, 58, 62)
	local horn = Color3.fromRGB(245, 230, 195)
	local lava = Color3.fromRGB(255, 140, 40)
	local leg = 0.24 * u
	-- 四條短粗腿 + 腳爪
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			add(m, Vector3.new(0.26, leg, 0.26) * Vector3.new(u, 1, u), CFrame.new(sx * 0.32 * u, leg / 2, sz * 0.34 * u), shell)
			add(m, Vector3.new(0.3, 0.06, 0.34) * u, CFrame.new(sx * 0.32 * u, 0.03 * u, sz * 0.34 * u - 0.04 * u), horn)
		end
	end
	-- 身體 + 犰狳式圓弧甲帶(圓柱橫放),每條甲帶頂端有熔岩刺
	local by = leg + 0.22 * u
	add(m, Vector3.new(0.86, 0.46, 1.1) * u, CFrame.new(0, by, 0), skin)
	-- 中間的甲帶大、兩端小 → 整片殼是圓拱形(不是一疊一樣大的輪子);甲帶交錯深淺色
	local BAND = { 0.6, 0.78, 0.84, 0.72, 0.56 }
	for i, d in BAND do
		local z = (-0.44 + (i - 1) * 0.22) * u
		local cy = by + (0.08 + (d - 0.84) * 0.3) * u
		add(m, Vector3.new(0.92 + d * 0.08, d, d) * u, CFrame.new(0, cy, z), if i % 2 == 0 then shell else Color3.fromRGB(95, 78, 80), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		add(m, Vector3.new(0.1, 0.16, 0.1) * u, CFrame.new(0, cy + d * 0.5 * u + 0.05 * u, z), lava, NEON)
	end
	-- 頭(低垂、往前伸)+ 下巴 + 向前上方的大角 + 紅眼
	local hz, hy = -0.68 * u, by - 0.02 * u
	add(m, Vector3.new(0.56, 0.44, 0.42) * u, CFrame.new(0, hy, hz), skin)
	add(m, Vector3.new(0.5, 0.14, 0.36) * u, CFrame.new(0, hy - 0.25 * u, hz - 0.04 * u), horn)
	add(m, Vector3.new(0.6, 0.12, 0.3) * u, CFrame.new(0, hy + 0.24 * u, hz + 0.04 * u), shell) -- 額甲
	for _, sx in { -1, 1 } do
		-- 角根朝外、角尖朝前上
		add(m, Vector3.new(0.12, 0.3, 0.12) * u, CFrame.new(sx * 0.28 * u, hy + 0.3 * u, hz) * CFrame.Angles(math.rad(-20), 0, -sx * math.rad(40)), horn)
		add(m, Vector3.new(0.08, 0.26, 0.08) * u, CFrame.new(sx * 0.38 * u, hy + 0.5 * u, hz - 0.1 * u) * CFrame.Angles(math.rad(-45), 0, -sx * math.rad(10)), horn)
	end
	eyes(m, hy + 0.08 * u, hz - 0.22 * u, 0.15 * u, 0.11 * u, Color3.fromRGB(255, 70, 50))
	-- 胸口熔岩裂紋
	local crack = add(m, Vector3.new(0.5, 0.06, 0.06) * u, CFrame.new(0, by - 0.05 * u, -0.56 * u), lava, NEON)
	light(crack, Color3.fromRGB(255, 120, 40), u * 1.5, 1.5)
end

BUILD.BladeMoth = function(m, u)
	m.flyHeight = u * 0.9
	local body = Color3.fromRGB(60, 50, 45)
	local fur = Color3.fromRGB(240, 205, 70)
	-- 毛茸茸的胸 + 條紋腹 + 頭(比例加大,遠看才認得出是蛾)
	add(m, Vector3.one * 0.36 * u, CFrame.new(0, 0.5 * u, -0.04 * u), fur, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for i = 1, 3 do
		local r = 0.33 - i * 0.05
		add(m, Vector3.one * r * u, CFrame.new(0, (0.5 - i * 0.02) * u, (0.12 + i * 0.17) * u), if i % 2 == 1 then body else fur, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	add(m, Vector3.one * 0.26 * u, CFrame.new(0, 0.55 * u, -0.3 * u), body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	eyes(m, 0.58 * u, -0.4 * u, 0.08 * u, 0.13 * u, Color3.fromRGB(80, 255, 255))
	-- 羽狀觸角
	for _, sx in { -1, 1 } do
		add(m, Vector3.new(0.04, 0.04, 0.34) * u, CFrame.new(sx * 0.08 * u, 0.72 * u, -0.42 * u) * CFrame.Angles(math.rad(45), sx * math.rad(25), 0), fur)
	end
	-- 兩對翅膀(上大下小),前緣是發光刀刃,上翅有眼紋
	local wingColor = Color3.fromRGB(245, 170, 60)
	local edge = Color3.fromRGB(255, 255, 210)
	local spot = Color3.fromRGB(120, 255, 255)
	for _, side in { -1, 1 } do
		wing(m, Vector3.new(0.85, 0.03, 0.55) * u, CFrame.new(side * 0.14 * u, 0.56 * u, -0.06 * u), side, wingColor, edge, spot)
		wing(m, Vector3.new(0.55, 0.03, 0.38) * u, CFrame.new(side * 0.14 * u, 0.5 * u, 0.2 * u), side, Color3.fromRGB(220, 120, 50), edge)
	end
	light(m.glow[1], Color3.fromRGB(120, 255, 255), u * 2, 1)
end

BUILD.PlasmaDrake = function(m, u)
	m.flyHeight = u * 0.5
	local scale = Color3.fromRGB(70, 120, 230)
	local belly = Color3.fromRGB(170, 210, 255)
	local horn = Color3.fromRGB(230, 235, 255)
	local plasma = Color3.fromRGB(110, 240, 255)
	-- 身體 + 肚子
	add(m, Vector3.new(0.5, 0.42, 0.75) * u, CFrame.new(0, 0.45 * u, 0), scale)
	add(m, Vector3.new(0.4, 0.1, 0.6) * u, CFrame.new(0, 0.26 * u, -0.02 * u), belly)
	-- 胸口電漿核心
	local core = add(m, Vector3.one * 0.2 * u, CFrame.new(0, 0.45 * u, -0.38 * u), plasma, NEON, Enum.PartType.Ball)
	light(core, plasma, u * 2.5, 3)
	-- 脖子 + 頭 + 吻部 + 角 + 眼
	add(m, Vector3.new(0.22, 0.22, 0.32) * u, CFrame.new(0, 0.62 * u, -0.45 * u) * CFrame.Angles(math.rad(30), 0, 0), scale)
	add(m, Vector3.new(0.32, 0.26, 0.36) * u, CFrame.new(0, 0.78 * u, -0.66 * u), scale)
	add(m, Vector3.new(0.22, 0.14, 0.22) * u, CFrame.new(0, 0.72 * u, -0.88 * u), belly)
	for _, sx in { -1, 1 } do
		add(m, Vector3.new(0.05, 0.05, 0.3) * u, CFrame.new(sx * 0.1 * u, 0.94 * u, -0.56 * u) * CFrame.Angles(math.rad(-35), 0, 0), horn)
	end
	eyes(m, 0.84 * u, -0.83 * u, 0.1 * u, 0.07 * u, Color3.fromRGB(255, 240, 80))
	-- 背鰭(發光)
	for i = 0, 2 do
		add(m, Vector3.new(0.04, 0.14, 0.14) * u, CFrame.new(0, 0.7 * u, (-0.2 + i * 0.22) * u) * CFrame.Angles(math.rad(45), 0, 0), plasma, NEON)
	end
	-- 尾巴三節
	for i = 1, 3 do
		local s = 0.22 - i * 0.05
		add(m, Vector3.new(s, s, 0.3) * u, CFrame.new(0, (0.45 - i * 0.05) * u, (0.38 + i * 0.26) * u), scale)
	end
	add(m, Vector3.new(0.18, 0.04, 0.16) * u, CFrame.new(0, 0.3 * u, 1.25 * u), plasma, NEON)
	-- 四隻短腿(收在身下,飛行姿勢)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			add(m, Vector3.new(0.12, 0.22, 0.14) * u, CFrame.new(sx * 0.2 * u, 0.2 * u, sz * 0.24 * u) * CFrame.Angles(math.rad(25), 0, 0), scale)
			add(m, Vector3.new(0.13, 0.05, 0.16) * u, CFrame.new(sx * 0.2 * u, 0.1 * u, sz * 0.24 * u - 0.06 * u), horn)
		end
	end
	-- 大蝙蝠翼
	for _, side in { -1, 1 } do
		wing(m, Vector3.new(1.15, 0.04, 0.7) * u, CFrame.new(side * 0.22 * u, 0.62 * u, -0.05 * u), side, Color3.fromRGB(110, 80, 220), plasma)
	end
end

BUILD.RiftTitan = function(m, u)
	local hide = Color3.fromRGB(70, 20, 95)
	local plate = Color3.fromRGB(40, 15, 55)
	local rift = Color3.fromRGB(230, 90, 255)
	-- 腿
	for _, sx in { -1, 1 } do
		add(m, Vector3.new(0.18, 0.32, 0.2) * u, CFrame.new(sx * 0.16 * u, 0.16 * u, 0), plate)
	end
	-- 軀幹 + 胸甲 + 發光裂痕
	add(m, Vector3.new(0.6, 0.42, 0.36) * u, CFrame.new(0, 0.53 * u, 0), hide)
	add(m, Vector3.new(0.66, 0.16, 0.4) * u, CFrame.new(0, 0.7 * u, 0), plate)
	local heart = add(m, Vector3.one * 0.12 * u, CFrame.new(0, 0.55 * u, -0.17 * u), rift, NEON, Enum.PartType.Ball)
	light(heart, rift, u * 2, 4)
	for _, a in { -30, 25 } do
		add(m, Vector3.new(0.03, 0.3, 0.02) * u, CFrame.new(a / 300 * u, 0.5 * u, -0.185 * u) * CFrame.Angles(0, 0, math.rad(a)), rift, NEON)
	end
	-- 肩刺
	for _, sx in { -1, 1 } do
		add(m, Vector3.new(0.12, 0.2, 0.12) * u, CFrame.new(sx * 0.33 * u, 0.85 * u, 0) * CFrame.Angles(0, 0, sx * math.rad(-30)), rift, NEON)
	end
	-- 長手臂 + 爪
	for _, sx in { -1, 1 } do
		add(m, Vector3.new(0.14, 0.48, 0.14) * u, CFrame.new(sx * 0.4 * u, 0.48 * u, -0.06 * u) * CFrame.Angles(math.rad(15), 0, sx * math.rad(8)), hide)
		for i = -1, 1 do
			add(m, Vector3.new(0.03, 0.12, 0.03) * u, CFrame.new(sx * 0.42 * u + i * 0.04 * u, 0.2 * u, -0.16 * u) * CFrame.Angles(math.rad(-30), 0, 0), Color3.fromRGB(240, 220, 255))
		end
	end
	-- 頭 + 角冠 + 三隻眼
	add(m, Vector3.new(0.3, 0.24, 0.26) * u, CFrame.new(0, 0.9 * u, -0.06 * u), plate)
	for i, a in { -50, -20, 20, 50 } do
		local x = a / 300 * u
		add(m, Vector3.new(0.05, 0.22 - math.abs(a) / 1000, 0.05) * u, CFrame.new(x, 1.08 * u, -0.04 * u) * CFrame.Angles(0, 0, math.rad(-a * 0.6)), if i % 2 == 0 then rift else Color3.fromRGB(240, 220, 255), if i % 2 == 0 then NEON else nil)
	end
	eyes(m, 0.92 * u, -0.2 * u, 0.08 * u, 0.06 * u, Color3.fromRGB(255, 80, 230))
	add(m, Vector3.one * 0.07 * u, CFrame.new(0, 0.99 * u, -0.19 * u), Color3.fromRGB(255, 255, 255), NEON, Enum.PartType.Ball)
	-- 裂縫光環
	local aura = add(m, Vector3.one * 1.12 * u, CFrame.new(0, 0.55 * u, 0), rift, Enum.Material.ForceField, Enum.PartType.Ball, 0.5)
	aura.Name = "Aura"
end

-- 名牌(首領與巨大化的怪才顯示)
local function nameplate(m: Monster, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, m.size * 1.25, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	gui.Adornee = m.root
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.Text = text
	l.Parent = gui
	gui.Parent = m.root
end

-- 建立怪獸(放在原點、尚未設定位置)。label 非 nil 時顯示名牌
function MonsterModel.create(id: string, size: number, label: string?): Monster
	local model = Instance.new("Model")
	model.Name = id
	local root = newPart()
	root.Name = "Root"
	root.Anchored = true
	root.Transparency = 1
	root.Size = Vector3.one * 0.5
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	local m: Monster = { model = model, root = root, size = size, flyHeight = 0, wings = {}, glow = {} }
	local build = BUILD[id] or BUILD.AcidWorm
	build(m, size)
	if label then
		nameplate(m, label, if id == "RiftTitan" then Color3.fromRGB(255, 120, 240) else Color3.fromRGB(255, 230, 120))
	end
	return m
end

-- 每幀動畫:翅膀拍動(t = 秒數,phase 讓每隻不同步)
function MonsterModel.animate(m: Monster, t: number, phase: number)
	if #m.wings == 0 then
		return
	end
	local flap = math.sin(t * 14 + phase) * math.rad(35)
	for _, w in m.wings do
		-- 以翅根為軸轉動,再往外推半個翼展到翅膀中心
		w.weld.C0 = w.base * CFrame.Angles(0, 0, w.side * flap) * CFrame.new(w.half * w.side, 0, 0)
	end
end

-- 擊倒:全身閃白 → 爆開淡出(回傳後 0.6 秒自行銷毀)
function MonsterModel.kill(m: Monster)
	local pos = m.root.Position + m.root.CFrame.UpVector * (m.size * 0.5 + m.flyHeight)
	local boom = Instance.new("Explosion")
	boom.Position = pos
	boom.BlastRadius = 0 -- 純特效,不傷人不炸零件
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.Parent = workspace
	for _, d in m.model:GetDescendants() do
		if d:IsA("BasePart") and d ~= m.root then
			d.Color = Color3.new(1, 1, 1)
			d.Material = NEON
		end
	end
	task.delay(0.12, function()
		for _, d in m.model:GetDescendants() do
			if d:IsA("BasePart") and d ~= m.root then
				d.Transparency = math.max(d.Transparency, 0.6)
			end
		end
	end)
	task.delay(0.6, function()
		m.model:Destroy()
	end)
end

return MonsterModel
