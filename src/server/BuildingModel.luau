--!strict
-- 建築外觀產生器:
--   1. 優先用 ReplicatedStorage.Assets.Buildings.<建築Id>(由 SolidCraft 建模 → OBJ → Studio 匯入的模型,見 assets/models/MANIFEST.md)
--   2. 沒有匯入模型時,依「類別 + tier(T1~T5)+ 建築等級(Lv1~3)」用基本零件組出造型:
--      越強(tier 越高)越高大、零件越多;Lv2 加四角柱、Lv3 再加頂端信標。
-- 所有零件 Anchored、不可碰撞;Model 上記錄 SlotKey / BuildingId / Lv,供點擊拆除與升級辨識。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DefenseArt = require(script.Parent.DefenseArt) -- 攻擊/防禦類的 StarCraft 風造型

local BuildingModel = {}

local CATEGORY_COLOR: { [string]: Color3 } = {
	Energy = Color3.fromRGB(80, 220, 120),
	Collect = Color3.fromRGB(240, 190, 60),
	Storage = Color3.fromRGB(200, 160, 110),
	Attack = Color3.fromRGB(230, 80, 80),
	Defense = Color3.fromRGB(80, 160, 240),
	Support = Color3.fromRGB(190, 130, 240),
	Tech = Color3.fromRGB(240, 240, 240),
}
local TIER_ACCENT: { Color3 } = {
	Color3.fromRGB(190, 190, 200),
	Color3.fromRGB(120, 220, 160),
	Color3.fromRGB(110, 180, 255),
	Color3.fromRGB(200, 130, 255),
	Color3.fromRGB(255, 190, 70),
}
local METAL = Color3.fromRGB(60, 66, 80)

local function part(model: Model, size: Vector3, base: CFrame, offset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	-- offset 的 Y 是「離地高度(零件中心)」
	p.CFrame = base * CFrame.new(offset)
	p.Parent = model
	return p
end

local function glow(model: Model, size: Vector3, base: CFrame, offset: Vector3, color: Color3, shape: Enum.PartType?)
	return part(model, size, base, offset, color, Enum.Material.Neon, shape)
end

local function buildProcedural(model: Model, def: any, lv: number, base: CFrame)
	local tier = math.clamp(def.tier or 1, 1, 5)
	local cat = def.category
	local color = CATEGORY_COLOR[cat] or Color3.fromRGB(200, 200, 200)
	local accent = TIER_ACCENT[tier]

	part(model, Vector3.new(10, 1, 10), base, Vector3.new(0, 0.5, 0), METAL, Enum.Material.Metal) -- 底座

	if DefenseArt.build(model, def, base) then
		-- 已由 DefenseArt 建好(攻擊/防禦類)
	elseif cat == "Energy" then
		local h = 2 + tier
		part(model, Vector3.new(2, h, 2), base, Vector3.new(0, 1 + h / 2, 0), METAL, Enum.Material.Metal)
		local panels = math.min(tier, 3)
		for i = 1, panels do
			local y = 1 + h + (i - 1) * 0.9
			part(model, Vector3.new(9 - (i - 1) * 2, 0.5, 6), base, Vector3.new(0, y, 0), color, Enum.Material.Glass)
		end
		glow(model, Vector3.new(1.2, 1.2, 1.2), base, Vector3.new(0, 1 + h + panels * 0.9 + 0.8, 0), accent, Enum.PartType.Ball)
	elseif cat == "Collect" then
		part(model, Vector3.new(7, 2 + tier * 0.6, 7), base, Vector3.new(0, 1 + (2 + tier * 0.6) / 2, 0), color, Enum.Material.Metal)
		local mast = 3 + tier * 1.6
		part(model, Vector3.new(2.4, mast, 2.4), base, Vector3.new(0, 1 + 2 + tier * 0.6 + mast / 2, 0), METAL, Enum.Material.Metal)
		glow(model, Vector3.new(3.4, 0.8, 3.4), base, Vector3.new(0, 1 + 2 + tier * 0.6 + mast + 0.4, 0), accent)
	elseif cat == "Storage" then
		local h = 3 + tier
		part(model, Vector3.new(8.5, h, 8.5), base, Vector3.new(0, 1 + h / 2, 0), color, Enum.Material.Concrete)
		part(model, Vector3.new(9.5, 1, 9.5), base, Vector3.new(0, 1 + h + 0.5, 0), METAL, Enum.Material.Metal)
		glow(model, Vector3.new(3, 0.4, 0.4), base, Vector3.new(0, 1 + h / 2, 4.4), accent)
	elseif cat == "Attack" then
		part(model, Vector3.new(6, 2, 6), base, Vector3.new(0, 2, 0), METAL, Enum.Material.Metal)
		part(model, Vector3.new(4.4, 2 + tier * 0.4, 4.4), base, Vector3.new(0, 3 + (2 + tier * 0.4) / 2, 0), color, Enum.Material.Metal)
		local barrels = math.min(1 + (tier - 1) // 2, 3)
		local len = 4 + tier
		local y = 3 + (2 + tier * 0.4) / 2
		for i = 1, barrels do
			local x = (i - (barrels + 1) / 2) * 1.3
			part(model, Vector3.new(0.9, 0.9, len), base, Vector3.new(x, y, -len / 2 - 1), METAL, Enum.Material.Metal)
			glow(model, Vector3.new(1.1, 1.1, 0.6), base, Vector3.new(x, y, -len - 1), accent)
		end
	elseif cat == "Defense" then
		if def.shield then
			part(model, Vector3.new(3.4, 3, 3.4), base, Vector3.new(0, 2.5, 0), color, Enum.Material.Metal)
			local d = 7 + tier * 1.2
			local dome = glow(model, Vector3.new(d, d, d), base, Vector3.new(0, 3 + d / 4, 0), color, Enum.PartType.Ball)
			dome.Transparency = 0.65
			dome.Material = Enum.Material.ForceField
		elseif def.wallHp then
			local h = 3 + tier * 1.3
			part(model, Vector3.new(10, h, 2.6), base, Vector3.new(0, 1 + h / 2, 0), color, Enum.Material.Concrete)
			for i = -1, 1 do
				part(model, Vector3.new(2.4, 1.4, 3), base, Vector3.new(i * 3.6, 1 + h + 0.7, 0), METAL, Enum.Material.Metal)
			end
			glow(model, Vector3.new(6, 0.35, 0.35), base, Vector3.new(0, 1 + h * 0.55, 1.4), accent)
		else -- 星核強化:階梯塔
			local levels = 3 + (if tier >= 4 then 1 else 0)
			for i = 1, levels do
				local s = 8 - (i - 1) * 1.8
				part(model, Vector3.new(s, 1.6, s), base, Vector3.new(0, 1 + (i - 1) * 1.6 + 0.8, 0), color, Enum.Material.Metal)
			end
			glow(model, Vector3.new(1.6, 1.6, 1.6), base, Vector3.new(0, 1 + levels * 1.6 + 1, 0), accent, Enum.PartType.Ball)
		end
	elseif cat == "Support" then
		part(model, Vector3.new(1.2, 6, 1.2), base, Vector3.new(0, 4, 0), METAL, Enum.Material.Metal)
		local dish = part(model, Vector3.new(0.6, 6, 6), base * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0, 0, 0), color, Enum.Material.Metal, Enum.PartType.Cylinder)
		dish.CFrame = base * CFrame.new(0, 7.5, 0) * CFrame.Angles(math.rad(20), 0, math.rad(90))
		glow(model, Vector3.new(0.8, 0.8, 0.8), base, Vector3.new(0, 8.4, -1), accent, Enum.PartType.Ball)
	else -- Tech:時空門
		part(model, Vector3.new(2, 9, 3), base, Vector3.new(-4.2, 5.5, 0), METAL, Enum.Material.Metal)
		part(model, Vector3.new(2, 9, 3), base, Vector3.new(4.2, 5.5, 0), METAL, Enum.Material.Metal)
		part(model, Vector3.new(11, 2, 3.4), base, Vector3.new(0, 10.5, 0), color, Enum.Material.Metal)
		local portal = glow(model, Vector3.new(6.4, 8, 0.6), base, Vector3.new(0, 5.5, 0), accent)
		portal.Transparency = 0.4
	end

	-- 建築等級外觀:Lv2 四角發光柱、Lv3 再加頂端信標
	if lv >= 2 then
		for _, sx in { -4.4, 4.4 } do
			for _, sz in { -4.4, 4.4 } do
				glow(model, Vector3.new(0.6, 1.8, 0.6), base, Vector3.new(sx, 1.9, sz), Color3.fromRGB(255, 220, 90))
			end
		end
	end
	if lv >= 3 then
		local beacon = glow(model, Vector3.new(1.4, 1.4, 1.4), base, Vector3.new(0, 15, 0), Color3.fromRGB(255, 240, 150), Enum.PartType.Ball)
		beacon.Transparency = 0.15
	end
end

-- 建立建築 Model;base 的 Y 軸 = 球面法線(朝外),原點在格位中心的地表
function BuildingModel.create(def: any, lv: number, base: CFrame, slotKey: string): Model
	local model: Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Buildings")
	local template = folder and folder:FindFirstChild(def.id)
	if template then
		local clone = template:Clone()
		if clone:IsA("Model") then
			model = clone
		else
			model = Instance.new("Model")
			clone.Parent = model
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		model:PivotTo(base)
	else
		model = Instance.new("Model")
		buildProcedural(model, def, lv, base)
	end
	-- 頭頂名牌:看得出蓋的是什麼。只在走近時顯示、不壓在介面最上層(免得整個畫面滿是字)
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = base * CFrame.new(0, 14 + (def.tier or 1), 0)
	anchor.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 22)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 45
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.5
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
	label.TextColor3 = CATEGORY_COLOR[def.category] or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = (def.name or def.id) .. " Lv" .. lv
	label.Parent = gui

	model.Name = def.id
	model:SetAttribute("SlotKey", slotKey)
	model:SetAttribute("BuildingId", def.id)
	model:SetAttribute("Lv", lv)
	return model
end

return BuildingModel
