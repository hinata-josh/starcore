--!strict
-- M0 技術驗證用:生成一顆球形母星 + 把每個格位用小方塊標出來,
-- 用來肉眼確認格位大小一致、跨面無縫(Studio Play 測試)。
-- 正式的 PlanetService 之後取代本檔。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CubeSphere = require(Shared.Logic.CubeSphere)

local N = 12
local CELL = 12
local RADIUS = CubeSphere.radiusFor(N, CELL)
local CENTER = Vector3.new(0, 300, 0)

workspace:SetAttribute("PlanetCenter", CENTER)
workspace:SetAttribute("PlanetRadius", RADIUS)

local planet = Instance.new("Part")
planet.Name = "HomePlanet"
planet.Shape = Enum.PartType.Ball
planet.Size = Vector3.one * RADIUS * 2
planet.Position = CENTER
planet.Anchored = true
planet.Material = Enum.Material.Slate
planet.Color = Color3.fromRGB(110, 130, 150)
planet.Parent = workspace

local markers = Instance.new("Folder")
markers.Name = "SlotMarkers"
markers.Parent = workspace

for face = 1, 6 do
	for u = 0, N - 1 do
		for v = 0, N - 1 do
			local p = CubeSphere.position(face, u, v, N, RADIUS)
			local pos = CENTER + Vector3.new(p.x, p.y, p.z)
			local up = (pos - CENTER).Unit
			local m = Instance.new("Part")
			m.Anchored = true
			m.CanCollide = false
			m.Size = Vector3.new(CELL - 2, 0.4, CELL - 2)
			-- 讓方塊「朝外」:Y 軸對齊球面法線
			local ref = if math.abs(up.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
			local tangent = up:Cross(ref).Unit
			m.CFrame = CFrame.lookAt(pos, pos + tangent, up)
			m.Color = Color3.fromHSV((face - 1) / 6, 0.6, 0.9)
			m.Name = CubeSphere.key(face, u, v)
			m.Parent = markers
		end
	end
end

-- 出生點放在北極上方
local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(8, 1, 8)
spawn.Position = CENTER + Vector3.new(0, RADIUS + 1, 0)
spawn.Parent = workspace
