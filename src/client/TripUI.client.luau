--!strict
-- M2 穿梭介面:母星上顯示「開啟時空門」按鈕;穿梭中顯示倒數、載重、「返航」按鈕。
-- 外觀統一走 Shared/UI/Skin。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Data.Items)
local Remotes = require(Shared.Net.Remotes)
local Skin = require(Shared.UI.Skin)

local player = Players.LocalPlayer
local warpEv = Remotes.get("RequestWarp")
local returnEv = Remotes.get("RequestReturn")
local tripEv = Remotes.get("TripChanged")
local cargoEv = Remotes.get("CargoChanged")
local gatherEv = Remotes.get("GatherState")

local itemName: { [string]: string } = {}
for _, it in Items.Types do
	itemName[it.id] = it.name
end

local gui = Instance.new("ScreenGui")
gui.Name = "TripUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- 右上:開啟時空門 / 返航(同一位置,依狀態切換)
local warpBtn = Skin.button(gui, "🌀 時空穿梭", "blue", UDim2.fromOffset(190, 48), UDim2.new(1, -200, 0, 8))
local returnBtn = Skin.button(gui, "返航", "orange", UDim2.fromOffset(190, 48), UDim2.new(1, -200, 0, 8))
returnBtn.Visible = false

-- 左側:穿梭資訊面板(倒數 / 載重 / 採集冷卻)
local tripPanel = Skin.panel(gui, UDim2.fromOffset(330, 124), UDim2.new(0, 10, 0, 322), Color3.fromRGB(120, 200, 255))
tripPanel.Visible = false
local timerText = Skin.text(tripPanel, "", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 6), 28)
local cargoText = Skin.text(tripPanel, "", UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 42), 18)
cargoText.Font = Skin.FONT_BODY
cargoText.TextWrapped = true
cargoText.TextXAlignment = Enum.TextXAlignment.Left
Skin.icon(tripPanel, "icon_pickaxe", UDim2.fromOffset(28, 28), UDim2.fromOffset(8, 88), "⛏", Skin.BUTTON_COLOR.gray)
local gatherText = Skin.text(tripPanel, "", UDim2.new(1, -52, 0, 28), UDim2.fromOffset(42, 88), 18)
gatherText.TextXAlignment = Enum.TextXAlignment.Left

local expiresAt: number? = nil
local gatherReadyAt = 0
local gatherCooling: { [string]: number } = {}

warpBtn.Activated:Connect(function()
	warpEv:FireServer()
end)
returnBtn.Activated:Connect(function()
	returnEv:FireServer()
end)

tripEv.OnClientEvent:Connect(function(info)
	local on = info ~= nil
	warpBtn.Visible = not on
	returnBtn.Visible = on
	tripPanel.Visible = on
	expiresAt = if on then info.expiresAt else nil
end)

cargoEv.OnClientEvent:Connect(function(loot, weight, cap)
	local parts = {}
	for id, n in loot do
		table.insert(parts, (itemName[id] or id) .. " " .. n)
	end
	local over = weight > cap
	cargoText.Text = ("載重 %d/%d%s  %s"):format(weight, cap, if over then " ⚠超載" else "", table.concat(parts, " "))
	cargoText.TextColor3 = if over then Color3.fromRGB(255, 170, 80) else Color3.new(1, 1, 1)
end)

gatherEv.OnClientEvent:Connect(function(st)
	gatherReadyAt = st.readyAt
	gatherCooling = st.cooling
end)

RunService.RenderStepped:Connect(function()
	if not tripPanel.Visible then
		return
	end
	local wait = gatherReadyAt - workspace:GetServerTimeNow()
	local coolCount = 0
	for _ in gatherCooling do
		coolCount += 1
	end
	local resting = if coolCount > 0 then ("(%d 種資源休息中)"):format(coolCount) else ""
	if wait > 0 then
		gatherText.Text = ("採集冷卻 %d 秒"):format(math.ceil(wait)) .. resting
		gatherText.TextColor3 = Color3.fromRGB(255, 190, 90)
	else
		gatherText.Text = "可以採集!" .. resting
		gatherText.TextColor3 = Color3.fromRGB(140, 255, 160)
	end
	if expiresAt then
		local left = math.floor(math.max(0, expiresAt - workspace:GetServerTimeNow())) -- %d 只吃整數
		timerText.Text = ("空間崩塌倒數 %d:%02d"):format(left // 60, left % 60)
		timerText.TextColor3 = if left < 30 then Color3.fromRGB(255, 90, 90) else Color3.new(1, 1, 1)
	end
end)

-- 依視窗大小等比縮放整個介面(小視窗不擠、不超出)
Skin.autoScale(gui)
