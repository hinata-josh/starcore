--!strict
-- 玩家角色不和場景碰撞:球面上的位置/高度完全由 client 的 SphereGravity 計算,
-- 若還跟星球球體、出生台、格位方塊碰撞,物理會一直把角色推出去 → 卡住不能走、身體亂飄。

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[Walkers]", ...)
	end
end

local GROUP = "Walkers"
PhysicsService:RegisterCollisionGroup(GROUP)
PhysicsService:CollisionGroupSetCollidable(GROUP, "Default", false)
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

local function tag(inst: Instance)
	if inst:IsA("BasePart") then
		inst.CollisionGroup = GROUP
	end
end

local function onCharacter(character: Model)
	for _, d in character:GetDescendants() do
		tag(d)
	end
	character.DescendantAdded:Connect(tag) -- 飾品、工具晚一點才掛上來
	log("角色改為不碰撞場景:", character.Name)
end

local function onPlayer(player: Player)
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
