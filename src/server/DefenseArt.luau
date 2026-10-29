--!strict
-- 防禦建築造型(攻擊 + 防禦類),風格參考 StarCraft:
--   飛彈砲塔(人類 Missile Turret)、攻城砲(Siege Tank)、光子砲(神族 Photon Cannon)、
--   有機刺塔(蟲族 Spine/Spore Crawler)、護盾電池(Shield Battery)、碉堡(Bunker)、要塞(Planetary Fortress)、堵口牆。
-- 每棟建築 = 一種「原型」+ 自己的配色/材質(STYLE 表),同原型也看得出差別。
-- 座標:base 的 Y 軸朝外(球面法線)、原點在地表;BuildingModel 已經放了 10×1×10 的底座(頂面 y = 1)。
-- 所有零件 Anchored、不可碰撞(與 BuildingModel 一致)。

local DefenseArt = {}

local STEEL = Color3.fromRGB(150, 158, 175)
local DARK = Color3.fromRGB(52, 57, 70)
local GOLD = Color3.fromRGB(225, 180, 80)
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- 圓柱(軸是 X)轉成直立

type Style = { kind: string, main: Color3, accent: Color3, mat: Enum.Material?, extra: string? }

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- 建築 id → 原型與配色
local STYLE: { [string]: Style } = {
	-- 攻擊
	CryoTurret = { kind = "cryo", main = C(70, 110, 160), accent = C(170, 240, 255) },
	PulseTurret = { kind = "missile", main = C(205, 210, 220), accent = C(255, 90, 70) },
	AcidSprayer = { kind = "organic", main = C(120, 150, 60), accent = C(190, 255, 80) },
	SparkCoil = { kind = "coil", main = C(200, 120, 60), accent = C(150, 200, 255) },
	FlakCannon = { kind = "missile", main = C(120, 130, 90), accent = C(255, 200, 60), extra = "flak" },
	FrostBeam = { kind = "dish", main = C(150, 200, 235), accent = C(170, 240, 255) },
	LaserTower = { kind = "pylon", main = C(200, 60, 70), accent = C(255, 80, 90) },
	SonicEmitter = { kind = "dish", main = C(120, 90, 170), accent = C(230, 160, 255), extra = "triple" },
	MagmaCannon = { kind = "artillery", main = C(120, 60, 45), accent = C(255, 130, 40) },
	GravityWell = { kind = "gravity", main = C(70, 70, 110), accent = C(150, 90, 255) },
	Railgun = { kind = "artillery", main = C(170, 180, 195), accent = C(90, 200, 255), extra = "rail" },
	SolarLance = { kind = "photon", main = GOLD, accent = C(255, 230, 120) },
	PlasmaCannon = { kind = "photon", main = C(210, 200, 170), accent = C(110, 230, 255) },
	VoidCannon = { kind = "photon", main = C(60, 45, 80), accent = C(180, 80, 255), extra = "void" },
	-- 護盾
	IceBarrier = { kind = "shield", main = C(150, 190, 220), accent = C(160, 230, 255) },
	AmberShield = { kind = "shield", main = C(170, 120, 60), accent = C(255, 170, 60) },
	EnergyShield = { kind = "shield", main = C(170, 180, 200), accent = C(80, 220, 255) },
	PrismShield = { kind = "shield", main = C(230, 230, 240), accent = C(255, 130, 240), extra = "prism" },
	VoidShield = { kind = "shield", main = C(55, 40, 75), accent = C(150, 70, 255) },
	-- 牆
	ScrapWall = { kind = "wall", main = C(140, 95, 70), accent = C(180, 160, 120), mat = Enum.Material.CorrodedMetal, extra = "scrap" },
	StoneWall = { kind = "wall", main = C(140, 140, 135), accent = C(105, 105, 100), mat = Enum.Material.Slate },
	SandBarrier = { kind = "wall", main = C(200, 175, 120), accent = C(150, 125, 80), mat = Enum.Material.Fabric, extra = "sandbag" },
	CoalBrickWall = { kind = "wall", main = C(60, 58, 60), accent = C(150, 140, 130), mat = Enum.Material.Brick, extra = "brick" },
	AlloyWall = { kind = "wall", main = C(150, 160, 175), accent = C(250, 200, 40), mat = Enum.Material.DiamondPlate, extra = "hazard" },
	AmberWall = { kind = "wall", main = C(240, 150, 40), accent = C(255, 200, 100), mat = Enum.Material.Glass, extra = "crystal" },
	CrystalWall = { kind = "wall", main = C(110, 210, 240), accent = C(180, 250, 255), mat = Enum.Material.Glass, extra = "crystal" },
	ObsidianWall = { kind = "wall", main = C(30, 25, 40), accent = C(255, 110, 40), mat = Enum.Material.Basalt, extra = "lava" },
	TitaniumWall = { kind = "wall", main = C(195, 200, 210), accent = C(60, 140, 255), mat = METAL, extra = "rivets" },
	StarArmor = { kind = "wall", main = C(240, 240, 250), accent = C(255, 210, 90), mat = Enum.Material.SmoothPlastic, extra = "star" },
	-- 基地
	CommandCenter = { kind = "command", main = C(175, 180, 195), accent = C(255, 190, 60) },
	-- 星核
	CoreReinforcer = { kind = "bunker", main = C(110, 120, 100), accent = C(255, 200, 80) },
	CoreBulwark = { kind = "fortress", main = C(120, 125, 140), accent = C(120, 220, 255) },
}

function DefenseArt.has(id: string): boolean
	return STYLE[id] ~= nil
end

-- 零件:cf 是相對 base 的完整 CFrame(位置 + 旋轉)
local function P(model: Model, size: Vector3, base: CFrame, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?, transparency: number?): BasePart
	local p = Instance.new("Part")
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = base * cf
	p.Parent = model
	return p
end

-- 楔形(斜面朝 -Z,高的那邊在 +Z)
local function W(model: Model, size: Vector3, base: CFrame, cf: CFrame, color: Color3, mat: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.CFrame = base * cf
	p.Parent = model
	return p
end

local function glow(model: Model, size: Vector3, base: CFrame, cf: CFrame, color: Color3, shape: Enum.PartType?, transparency: number?): BasePart
	return P(model, size, base, cf, color, NEON, shape, transparency)
end

local function light(part: BasePart, color: Color3, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = 1.5
	l.Parent = part
end

local function V(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- 八角形底盤(兩塊方塊錯開 45°)
local function octBase(m: Model, b: CFrame, w: number, h: number, y: number, color: Color3)
	P(m, Vector3.new(w, h, w), b, V(0, y, 0), color, METAL)
	P(m, Vector3.new(w, h, w), b, V(0, y, 0) * CFrame.Angles(0, math.rad(45), 0), color, METAL)
end

local BUILD: { [string]: (m: Model, b: CFrame, s: Style, t: number) -> () } = {}

-- 飛彈砲塔:八角底 + 轉軸 + 砲頭 + 兩側飛彈莢艙(防空砲:三排)
BUILD.missile = function(m, b, s, t)
	octBase(m, b, 8, 1.2, 1.6, DARK)
	P(m, Vector3.new(3.2, 2.6, 2.6), b, V(0, 3.4, 0) * UPRIGHT, STEEL, METAL, Enum.PartType.Cylinder)
	P(m, Vector3.new(4.6, 2.6, 4), b, V(0, 6, 0), s.main, METAL)
	W(m, Vector3.new(4.6, 1.2, 1.4), b, V(0, 7.9, -1.3), s.main, METAL)
	glow(m, Vector3.new(2.2, 0.5, 0.2), b, V(0, 6.4, -2.05), s.accent)
	local rows = if s.extra == "flak" then 3 else 2
	for _, sx in { -1, 1 } do
		P(m, Vector3.new(2, 1.1 * rows + 0.6, 3.6), b, V(sx * 3.4, 6.2, 0), DARK, METAL)
		for r = 1, rows do
			for c = -1, 1, 2 do
				glow(m, Vector3.one * 0.7, b, V(sx * 3.4 + c * 0.45, 6.2 + (r - (rows + 1) / 2) * 1.1, -1.85), s.accent, Enum.PartType.Ball)
			end
		end
	end
	P(m, Vector3.new(0.2, 3, 0.2), b, V(1.6, 8.6, 1.2), STEEL)
	glow(m, Vector3.one * 0.5, b, V(1.6, 10.1, 1.2), s.accent, Enum.PartType.Ball)
end

-- 攻城砲:履帶底盤 + 車身 + 砲塔 + 長砲管(磁軌砲:雙軌 + 中間電光)
BUILD.artillery = function(m, b, s, t)
	for _, sx in { -1, 1 } do
		P(m, Vector3.new(2.2, 2, 8.6), b, V(sx * 3.4, 2, 0), DARK, METAL)
		for z = -3, 3, 3 do
			P(m, Vector3.new(2.4, 1.5, 1.5), b, V(sx * 3.4, 2, z), STEEL, METAL, Enum.PartType.Cylinder)
		end
	end
	P(m, Vector3.new(4.8, 1.8, 7), b, V(0, 3.2, 0), s.main, METAL)
	W(m, Vector3.new(4.8, 1.2, 1.6), b, V(0, 3.7, -4.3), s.main, METAL)
	P(m, Vector3.new(4.2, 2, 4.4), b, V(0, 5.1, 0.8), s.main, METAL)
	P(m, Vector3.new(4.4, 0.5, 4.6), b, V(0, 6.3, 0.8), DARK, METAL)
	local len = 8 + t
	local aim = V(0, 5.4, -1) * CFrame.Angles(math.rad(18), 0, 0)
	if s.extra == "rail" then
		for _, x in { -0.75, 0.75 } do
			P(m, Vector3.new(0.45, 0.8, len), b, aim * V(x, 0, -len / 2), STEEL, METAL)
		end
		local arc = glow(m, Vector3.new(0.35, 0.25, len * 0.92), b, aim * V(0, 0, -len / 2), s.accent)
		light(arc, s.accent, 12)
	else
		P(m, Vector3.new(1.1, 1.1, len), b, aim * V(0, 0, -len / 2), STEEL, METAL)
		P(m, Vector3.new(1.6, 1.6, 1.4), b, aim * V(0, 0, -1.2), DARK, METAL) -- 砲盾
		local muzzle = glow(m, Vector3.new(1.3, 1.3, 0.5), b, aim * V(0, 0, -len), s.accent)
		light(muzzle, s.accent, 10)
	end
	glow(m, Vector3.new(1.4, 0.3, 0.2), b, V(0, 5.4, -1.42), s.accent)
end

-- 光子砲:金色台座 + 四片向內傾的鰭 + 懸浮能量球 + 光環(虛空砲:暗色 + 雙環)
BUILD.photon = function(m, b, s, t)
	P(m, Vector3.new(7, 1.4, 7), b, V(0, 1.7, 0), s.main, METAL)
	P(m, Vector3.new(5, 1, 5), b, V(0, 2.9, 0) * CFrame.Angles(0, math.rad(45), 0), s.main, METAL)
	for k = 0, 3 do
		local a = math.rad(k * 90 + 45)
		local cf = V(math.cos(a) * 3.1, 5.6, math.sin(a) * 3.1) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(16))
		P(m, Vector3.new(0.8, 5.6, 2), b, cf, s.main, METAL)
		glow(m, Vector3.new(0.3, 3.6, 0.6), b, cf * V(-0.45, 0.4, 0), s.accent)
	end
	local d = 3.2 + t * 0.25
	local orb = glow(m, Vector3.one * d, b, V(0, 9.4, 0), if s.extra == "void" then C(70, 20, 120) else s.accent, Enum.PartType.Ball)
	light(orb, s.accent, 16)
	glow(m, Vector3.new(0.25, d + 2.6, d + 2.6), b, V(0, 9.4, 0) * UPRIGHT, s.accent, Enum.PartType.Cylinder, 0.55)
	if s.extra == "void" then
		glow(m, Vector3.new(0.25, d + 3.6, d + 3.6), b, V(0, 9.4, 0) * CFrame.Angles(math.rad(70), 0, 0) * UPRIGHT, s.accent, Enum.PartType.Cylinder, 0.45)
	end
end

-- 有機刺塔(蟲族風):菌毯 + 肉質球體 + 骨刺 + 發光膿包 + 噴口
BUILD.organic = function(m, b, s, t)
	local creep = C(95, 45, 95)
	local bone = C(235, 220, 190)
	P(m, Vector3.new(0.8, 10.5, 10.5), b, V(0, 1.1, 0) * UPRIGHT, creep, Enum.Material.Slate, Enum.PartType.Cylinder)
	P(m, Vector3.one * 5.4, b, V(0, 3.6, 0.4), s.main, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	P(m, Vector3.one * 3.6, b, V(0, 6.4, -0.4), s.main, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for k = 0, 5 do
		local a = math.rad(k * 60)
		P(m, Vector3.new(0.6, 2.8, 0.6), b, V(math.cos(a) * 2.6, 5, math.sin(a) * 2.6 + 0.4) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-35)), bone)
	end
	for _, pt in { { 1.6, 3.2, -2 }, { -1.9, 4.2, -1.2 }, { 0.9, 7.4, 0.8 }, { -1.2, 2.6, 2.3 } } do
		glow(m, Vector3.one * 0.9, b, V(pt[1], pt[2], pt[3]), s.accent, Enum.PartType.Ball)
	end
	local nozzle = V(0, 7.6, -1.6) * CFrame.Angles(math.rad(35), 0, 0)
	P(m, Vector3.new(1.4, 1.4, 2.6), b, nozzle, s.main)
	local tip = glow(m, Vector3.new(1, 1, 0.4), b, nozzle * V(0, 0, -1.4), s.accent)
	light(tip, s.accent, 10)
end

-- 電弧線圈:疊層銅環 + 中柱 + 頂端電球 + 放電光環
BUILD.coil = function(m, b, s, t)
	octBase(m, b, 6.5, 1.2, 1.6, DARK)
	P(m, Vector3.new(8, 0.7, 0.7), b, V(0, 6, 0) * UPRIGHT, STEEL, METAL, Enum.PartType.Cylinder)
	for i = 0, 4 do
		local d = 4.6 - i * 0.6
		P(m, Vector3.new(0.9, d, d), b, V(0, 3 + i * 1.5, 0) * UPRIGHT, if i % 2 == 0 then s.main else DARK, METAL, Enum.PartType.Cylinder)
	end
	local ball = glow(m, Vector3.one * 2.6, b, V(0, 10.8, 0), s.accent, Enum.PartType.Ball)
	light(ball, s.accent, 14)
	glow(m, Vector3.new(0.2, 4.6, 4.6), b, V(0, 10.8, 0) * CFrame.Angles(math.rad(60), 0, 0) * UPRIGHT, s.accent, Enum.PartType.Cylinder, 0.5)
	glow(m, Vector3.new(0.2, 4.2, 4.2), b, V(0, 10.8, 0) * CFrame.Angles(math.rad(-50), math.rad(60), 0) * UPRIGHT, s.accent, Enum.PartType.Cylinder, 0.5)
end

-- 雷射塔:漸細的塔身 + 正面光條 + 頂端菱形透鏡
BUILD.pylon = function(m, b, s, t)
	octBase(m, b, 6.5, 1.2, 1.6, DARK)
	local y = 2.2
	for i, sz in { 3.8, 3, 2.2 } do
		local h = 4.2 - i * 0.5
		P(m, Vector3.new(sz, h, sz), b, V(0, y + h / 2, 0), if i % 2 == 1 then s.main else DARK, METAL)
		y += h
	end
	glow(m, Vector3.new(0.35, y - 2.4, 0.2), b, V(0, (y + 2.2) / 2, -1.95), s.accent)
	local lens = glow(m, Vector3.one * 2, b, V(0, y + 1.5, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), s.accent)
	light(lens, s.accent, 14)
	glow(m, Vector3.new(0.2, 3.6, 3.6), b, V(0, y + 1.5, 0) * UPRIGHT, s.accent, Enum.PartType.Cylinder, 0.6)
end

-- 碟形發射器:立柱 + 朝前上方的碟子 + 發射桿(音波砲:三片小碟)
BUILD.dish = function(m, b, s, t)
	octBase(m, b, 6.5, 1.2, 1.6, DARK)
	P(m, Vector3.new(4, 1.6, 1.6), b, V(0, 4, 0) * UPRIGHT, STEEL, METAL, Enum.PartType.Cylinder)
	local function dish(cf: CFrame, d: number)
		local face = cf * CFrame.Angles(math.rad(25), 0, 0)
		P(m, Vector3.new(0.5, d, d), b, face * CFrame.Angles(0, math.rad(90), 0), s.main, METAL, Enum.PartType.Cylinder)
		glow(m, Vector3.new(0.3, d * 0.55, d * 0.55), b, face * V(0, 0, -0.3) * CFrame.Angles(0, math.rad(90), 0), s.accent, Enum.PartType.Cylinder, 0.2)
		P(m, Vector3.new(0.4, 0.4, d * 0.45), b, face * V(0, 0, -d * 0.22), STEEL)
		glow(m, Vector3.one * 0.8, b, face * V(0, 0, -d * 0.45), s.accent, Enum.PartType.Ball)
	end
	if s.extra == "triple" then
		dish(V(0, 7.6, 0), 4)
		dish(V(-2.6, 5.6, 0.4), 2.6)
		dish(V(2.6, 5.6, 0.4), 2.6)
	else
		dish(V(0, 7.2, 0), 6)
	end
end

-- 重力陷阱:兩道交叉圓環 + 中央暗物質球
BUILD.gravity = function(m, b, s, t)
	octBase(m, b, 7.5, 1.2, 1.6, DARK)
	local cy = 6.8
	for k = 0, 11 do
		local a = math.rad(k * 30)
		P(m, Vector3.new(1, 1.9, 1.1), b, V(math.cos(a) * 4, cy + math.sin(a) * 4, 0) * CFrame.Angles(0, 0, a), s.main, METAL)
	end
	glow(m, Vector3.new(0.3, 7, 7), b, V(0, cy, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, 0), s.accent, Enum.PartType.Cylinder, 0.6)
	local orb = glow(m, Vector3.one * 2.8, b, V(0, cy, 0), C(60, 20, 110), Enum.PartType.Ball)
	glow(m, Vector3.one * 3.6, b, V(0, cy, 0), s.accent, Enum.PartType.Ball, 0.7)
	light(orb, s.accent, 14)
end

-- 冰凍砲台:低台座 + 冰晶簇 + 短砲管
BUILD.cryo = function(m, b, s, t)
	octBase(m, b, 7, 1.4, 1.7, s.main)
	local ice = s.accent
	for _, c in { { 0, 5.4, 0, 1.6, 6, 8 }, { 1.6, 4, 0.8, 1.1, 4, -20 }, { -1.5, 3.8, 0.6, 1, 3.6, 22 }, { 0.4, 3.4, 1.8, 0.9, 3, -10 } } do
		P(m, Vector3.new(c[4], c[5], c[4]), b, V(c[1], c[2], c[3]) * CFrame.Angles(0, math.rad(45), math.rad(c[6])), ice, Enum.Material.Glass, nil, 0.15)
	end
	local core = glow(m, Vector3.new(0.7, 4, 0.7), b, V(0, 5.4, 0) * CFrame.Angles(0, math.rad(45), math.rad(8)), Color3.new(1, 1, 1))
	light(core, ice, 12)
	P(m, Vector3.new(0.9, 0.9, 3.6), b, V(0, 3.2, -2.6), STEEL, METAL)
	glow(m, Vector3.new(1.1, 1.1, 0.4), b, V(0, 3.2, -4.4), ice)
end

-- 護盾電池:八角底 + 三根導能柱 + 中央核心 + 半透明護盾罩(稜鏡:三柱三色)
BUILD.shield = function(m, b, s, t)
	octBase(m, b, 8, 1.2, 1.6, s.main)
	local prism = { C(255, 110, 110), C(110, 255, 160), C(120, 160, 255) }
	for k = 0, 2 do
		local a = math.rad(k * 120 + 90)
		local x, z = math.cos(a) * 3, math.sin(a) * 3
		P(m, Vector3.new(0.9, 5, 0.9), b, V(x, 4.7, z), s.main, METAL)
		glow(m, Vector3.one * 1, b, V(x, 7.5, z), if s.extra == "prism" then prism[k + 1] else s.accent, Enum.PartType.Ball)
	end
	local core = glow(m, Vector3.new(1.6, 3, 1.6), b, V(0, 3.8, 0) * CFrame.Angles(0, math.rad(45), 0), s.accent)
	light(core, s.accent, 16)
	local d = 11 + t * 1.2
	P(m, Vector3.one * d, b, V(0, 2, 0), s.accent, Enum.Material.ForceField, Enum.PartType.Ball, 0.55)
end

-- 堵口牆:牆身 + 扶壁 + 頂蓋 + 垛口,加上各自的材質細節
BUILD.wall = function(m, b, s, t)
	local h = 4 + t * 1.2
	local top = 1 + h
	local mat = s.mat or Enum.Material.Concrete
	local trans = if s.extra == "crystal" then 0.25 else 0
	if s.extra == "sandbag" then
		-- 沙袋:圓柱橫放疊三層,上下錯開
		for row = 0, 2 do
			local off = if row % 2 == 0 then 0 else 1.25
			for i = 0, 3 do
				local x = -3.75 + i * 2.5 + off
				if x <= 4.5 then
					-- 圓柱的軸是 X = 沿著牆的方向橫躺
					P(m, Vector3.new(2.4, 1.6, 1.6), b, V(x, 1.8 + row * 1.35, 0), if (row + i) % 2 == 0 then s.main else s.accent, mat, Enum.PartType.Cylinder)
				end
			end
		end
		P(m, Vector3.new(0.2, 3, 0.2), b, V(3.8, 6.5, 0), DARK)
		P(m, Vector3.new(1.6, 1, 0.1), b, V(4.6, 7.4, 0), C(220, 60, 60)) -- 小旗
		return
	end
	P(m, Vector3.new(10, h, 2.8), b, V(0, 1 + h / 2, 0), s.main, mat, nil, trans)
	for _, sx in { -1, 1 } do
		W(m, Vector3.new(1.6, h * 0.75, 2), b, V(sx * 4.2, 1 + h * 0.375, 2.4) * CFrame.Angles(0, math.rad(180), 0), s.accent, mat)
	end
	P(m, Vector3.new(10.6, 0.7, 3.4), b, V(0, top + 0.35, 0), s.accent, mat)
	for _, x in { -3.6, 0, 3.6 } do
		P(m, Vector3.new(2, 1.2, 3.2), b, V(x, top + 1.3, 0), s.accent, mat)
	end
	local face = -1.45 -- 牆正面(-Z)
	if s.extra == "hazard" then
		-- 黃黑警示條紋
		P(m, Vector3.new(10.05, 1.1, 0.1), b, V(0, 1 + h * 0.3, face), s.accent)
		for i = -4, 4, 2 do
			W(m, Vector3.new(0.12, 1.1, 1.1), b, V(i, 1 + h * 0.3, face - 0.06) * CFrame.Angles(0, math.rad(90), 0), DARK)
		end
	elseif s.extra == "rivets" then
		for x = -4, 4, 2 do
			for _, y in { 0.25, 0.75 } do
				P(m, Vector3.one * 0.45, b, V(x, 1 + h * y, face), DARK, METAL, Enum.PartType.Ball)
			end
		end
		glow(m, Vector3.new(9.6, 0.25, 0.1), b, V(0, 1 + h * 0.5, face), s.accent)
	elseif s.extra == "lava" then
		for _, c in { { -2.6, 0.4, 30 }, { 0.8, 0.55, -25 }, { 3, 0.35, 40 } } do
			glow(m, Vector3.new(0.25, h * 0.6, 0.1), b, V(c[1], 1 + h * c[2], face) * CFrame.Angles(0, 0, math.rad(c[3])), s.accent)
		end
	elseif s.extra == "crystal" then
		for _, x in { -5, 5 } do
			glow(m, Vector3.new(0.3, h, 0.3), b, V(x, 1 + h / 2, face), s.accent)
		end
		glow(m, Vector3.new(10, 0.25, 0.25), b, V(0, top, face), s.accent)
	elseif s.extra == "brick" then
		for i = 1, 3 do
			P(m, Vector3.new(10.02, 0.15, 2.85), b, V(0, 1 + h * i / 4, 0), s.accent)
		end
	elseif s.extra == "scrap" then
		for _, c in { { -2.5, 0.35, 8, C(90, 110, 120) }, { 1.6, 0.6, -6, C(170, 120, 60) }, { 3.4, 0.25, 12, C(110, 80, 70) } } do
			P(m, Vector3.new(2.6, 2, 0.2), b, V(c[1], 1 + h * c[2], face) * CFrame.Angles(0, 0, math.rad(c[3])), c[4], Enum.Material.CorrodedMetal)
		end
	elseif s.extra == "star" then
		glow(m, Vector3.new(9.8, 0.25, 0.1), b, V(0, 1 + h * 0.2, face), s.accent)
		glow(m, Vector3.new(9.8, 0.25, 0.1), b, V(0, 1 + h * 0.85, face), s.accent)
		local star = glow(m, Vector3.new(1.6, 1.6, 0.2), b, V(0, 1 + h * 0.52, face) * CFrame.Angles(0, 0, math.rad(45)), s.accent)
		light(star, s.accent, 10)
	end
end

-- 碉堡:低矮裝甲箱 + 斜前裝甲 + 射擊孔 + 頂艙 + 天線
BUILD.bunker = function(m, b, s, t)
	P(m, Vector3.new(9, 3.4, 7.4), b, V(0, 2.7, 0.6), s.main, METAL)
	W(m, Vector3.new(9, 2.4, 2.2), b, V(0, 2.2, -4.2), s.main, METAL)
	P(m, Vector3.new(9.4, 0.6, 7.8), b, V(0, 4.7, 0.6), DARK, METAL)
	local slit = glow(m, Vector3.new(6, 0.45, 0.2), b, V(0, 3.9, -3.12), s.accent)
	light(slit, s.accent, 10)
	P(m, Vector3.new(0.8, 3.4, 3.4), b, V(0, 5.3, 1.2) * UPRIGHT, STEEL, METAL, Enum.PartType.Cylinder)
	P(m, Vector3.new(0.2, 4, 0.2), b, V(3.4, 7, 2.6), STEEL)
	glow(m, Vector3.one * 0.5, b, V(3.4, 9, 2.6), s.accent, Enum.PartType.Ball)
	for _, sx in { -1, 1 } do
		P(m, Vector3.new(1, 0.6, 7.4), b, V(sx * 4.6, 2, 0.6), C(240, 200, 60)) -- 側邊警示條
	end
end

-- 要塞:厚底座 + 四角塔 + 中央砲塔 + 星核能量球
BUILD.fortress = function(m, b, s, t)
	octBase(m, b, 9.4, 2.2, 2.1, s.main)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(m, Vector3.new(2.2, 4.8, 2.2), b, V(sx * 3.6, 4.6, sz * 3.6), DARK, METAL)
			glow(m, Vector3.new(2.3, 0.3, 2.3), b, V(sx * 3.6, 6.4, sz * 3.6), s.accent)
		end
	end
	P(m, Vector3.new(5.6, 2.6, 5.6), b, V(0, 4.5, 0), s.main, METAL)
	P(m, Vector3.new(1, 1, 4.4), b, V(-0.9, 6.3, -2.4), STEEL, METAL)
	P(m, Vector3.new(1, 1, 4.4), b, V(0.9, 6.3, -2.4), STEEL, METAL)
	local core = glow(m, Vector3.one * 2.6, b, V(0, 7.2, 0.6), s.accent, Enum.PartType.Ball)
	light(core, s.accent, 18)
	glow(m, Vector3.new(0.25, 4.6, 4.6), b, V(0, 7.2, 0.6) * UPRIGHT, s.accent, Enum.PartType.Cylinder, 0.5)
end

-- 指揮中心(人類 Command Center 風):四支降落腳架 + 八角主體 + 上層甲板 + 控制塔 + 雷達碟 + 觀測圓頂 + 旗子
BUILD.command = function(m, b, s, t)
	local glass = C(110, 200, 255)
	-- 降落腳架(斜撐 + 腳墊)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(m, Vector3.new(0.9, 4.2, 0.9), b, V(sx * 4.3, 2.6, sz * 4.3) * CFrame.Angles(sz * math.rad(-14), 0, sx * math.rad(14)), DARK, METAL)
			P(m, Vector3.new(2, 0.5, 2), b, V(sx * 4.8, 1.25, sz * 4.8), DARK, METAL)
		end
	end
	-- 主體(八角)+ 一圈黃色警示帶 + 正面發光窗
	octBase(m, b, 9.6, 3.2, 4.6, s.main)
	octBase(m, b, 9.8, 0.4, 3.2, s.accent)
	glow(m, Vector3.new(5, 0.5, 0.2), b, V(0, 5.2, -4.82), glass)
	local emblem = glow(m, Vector3.new(1.4, 1.4, 0.2), b, V(0, 4.2, -4.85) * CFrame.Angles(0, 0, math.rad(45)), s.accent)
	light(emblem, s.accent, 12)
	-- 上層甲板
	octBase(m, b, 6.6, 1.6, 7, DARK)
	-- 控制塔 + 藍色窗帶
	P(m, Vector3.new(2.6, 3.8, 2.6), b, V(-1.6, 9.7, 1.3), s.main, METAL)
	glow(m, Vector3.new(2.7, 0.6, 2.7), b, V(-1.6, 10.6, 1.3), glass)
	P(m, Vector3.new(3, 0.5, 3), b, V(-1.6, 11.85, 1.3), DARK, METAL)
	-- 雷達碟(朝前上方)
	local face = V(-1.6, 13, 1.3) * CFrame.Angles(math.rad(35), 0, 0)
	P(m, Vector3.new(0.3, 3.2, 3.2), b, face * CFrame.Angles(0, math.rad(90), 0), STEEL, METAL, Enum.PartType.Cylinder)
	glow(m, Vector3.one * 0.5, b, face * V(0, 0, -0.9), s.accent, Enum.PartType.Ball)
	-- 觀測圓頂
	P(m, Vector3.one * 2.8, b, V(1.7, 8.1, -0.8), glass, Enum.Material.Glass, Enum.PartType.Ball, 0.25)
	-- 天線 + 紅色信號燈
	P(m, Vector3.new(0.2, 3.4, 0.2), b, V(2.6, 9.4, 2.4), STEEL)
	glow(m, Vector3.one * 0.6, b, V(2.6, 11.2, 2.4), C(255, 70, 70), Enum.PartType.Ball)
	-- 旗子
	P(m, Vector3.new(0.18, 3.2, 0.18), b, V(-3.6, 9.4, -2.6), STEEL)
	P(m, Vector3.new(0.1, 1.2, 1.9), b, V(-3.6, 10.4, -1.6), C(60, 140, 255))
end

-- 依建築 id 建造型;回傳是否有處理(沒有 STYLE 的建築交回 BuildingModel 的通用造型)
function DefenseArt.build(model: Model, def: any, base: CFrame): boolean
	local s = STYLE[def.id]
	if not s then
		return false
	end
	local fn = BUILD[s.kind]
	if not fn then
		return false
	end
	fn(model, base, s, math.clamp(def.tier or 1, 1, 5))
	return true
end

return DefenseArt
