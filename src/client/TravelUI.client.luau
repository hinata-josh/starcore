--!strict
-- 星球旅行介面:「👥 拜訪好友」(列出正在玩的線上好友 → 傳送到他的星球)、「🏠 回到我的星球」(人在別人星球時才顯示)。
-- 實際傳送由伺服器 TravelService 執行(Studio 不能傳送,會提示)。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Skin = require(Shared.UI.Skin)

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[TravelUI]", ...)
	end
end

local player = Players.LocalPlayer
local friendsEv = Remotes.get("RequestFriends")
local listEv = Remotes.get("FriendList")
local visitEv = Remotes.get("VisitFriend")
local homeEv = Remotes.get("GoHome")
local tripEv = Remotes.get("TripChanged")

local gui = Instance.new("ScreenGui")
gui.Name = "TravelUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- 左下圖示按鈕(由下往上:中央螢幕 → 重建星球 → 拜訪好友 → 回到我的星球;滑過才顯示說明)
local friendsBtn = Skin.iconButton(gui, "👥", "拜訪好友", "blue", UDim2.new(0, 10, 1, -168))
friendsBtn.Name = "FriendsButton"
local homeBtn = Skin.iconButton(gui, "🏠", "回到我的星球", "green", UDim2.new(0, 10, 1, -222))
homeBtn.Name = "HomeButton"
homeBtn.Visible = false

-- 好友清單面板
local panel = Skin.panel(gui, UDim2.fromOffset(380, 330), UDim2.new(0.5, 0, 0.45, 0), Color3.fromRGB(110, 190, 255))
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Visible = false
Skin.text(panel, "👥 拜訪好友的星球", UDim2.new(1, -60, 0, 34), UDim2.fromOffset(14, 10), 26).TextXAlignment = Enum.TextXAlignment.Left
local closeBtn = Skin.button(panel, "✕", "gray", UDim2.fromOffset(38, 34), UDim2.new(1, -48, 0, 10))
local hint = Skin.text(panel, "", UDim2.new(1, -28, 0, 40), UDim2.fromOffset(14, 50), 18)
hint.Font = Skin.FONT_BODY
local list = Instance.new("ScrollingFrame")
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Size = UDim2.new(1, -24, 1, -100)
list.Position = UDim2.fromOffset(12, 92)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 6
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

-- 人在別人的星球(私人伺服器的主人不是我,或這台的主人不是我)才顯示「回到我的星球」
local function refreshHome()
	local home = workspace:GetAttribute("HomeOwnerId")
	local owner = workspace:GetAttribute("OwnerUserId")
	local away = (home ~= nil and home ~= player.UserId) or (home == nil and owner ~= nil and owner ~= player.UserId)
	homeBtn.Visible = away and not player:GetAttribute("InTrip")
end
workspace:GetAttributeChangedSignal("HomeOwnerId"):Connect(refreshHome)
workspace:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshHome)
player:GetAttributeChangedSignal("InTrip"):Connect(refreshHome)
refreshHome()

tripEv.OnClientEvent:Connect(function(info)
	friendsBtn.Visible = info == nil
	if info then
		panel.Visible = false
	end
	refreshHome()
end)

friendsBtn.Activated:Connect(function()
	panel.Visible = true
	hint.Text = "查詢中…"
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	friendsEv:FireServer()
end)
closeBtn.Activated:Connect(function()
	panel.Visible = false
end)
homeBtn.Activated:Connect(function()
	log("請求回家")
	homeEv:FireServer()
end)

listEv.OnClientEvent:Connect(function(friends)
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if #friends == 0 then
		hint.Text = "目前沒有好友在玩這個遊戲\n邀請好友一起來吧!"
		return
	end
	hint.Text = ("有 %d 位好友在線上,點名字就能過去採集"):format(#friends)
	for _, f in friends do
		local b = Skin.button(list, "🚀 前往 " .. f.name .. " 的星球", "orange", UDim2.new(1, -10, 0, 40))
		b.Activated:Connect(function()
			log("請求拜訪", f.userId)
			panel.Visible = false
			visitEv:FireServer(f.userId)
		end)
	end
end)

-- 依視窗大小等比縮放整個介面(小視窗不擠、不超出)
Skin.autoScale(gui)
