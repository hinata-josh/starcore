--!strict
-- M3+ 介面:裂縫倒數與怪獸預覽、戰鬥結果橫幅、任務目標、時空門升級、Shift+左鍵升級建築。
-- 外觀統一走 Shared/UI/Skin(有上傳 N1 素材就用素材,沒有用備用樣式)。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Items = require(Shared.Data.Items)
local Skin = require(Shared.UI.Skin)

local player = Players.LocalPlayer
local infoEv = Remotes.get("WaveInfo")
local resultEv = Remotes.get("WaveResult")
local questEv = Remotes.get("QuestChanged")
local upgradeEv = Remotes.get("UpgradeBuilding")
local upgradeWarpEv = Remotes.get("UpgradeWarp")

local itemName: { [string]: string } = {}
for _, it in Items.Types do
	itemName[it.id] = it.name
end

local gui = Instance.new("ScreenGui")
gui.Name = "HudExtras"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- ── 任務目標(左側,聊天視窗下方):橘色彩帶 + 圖示 ──
local quest = Skin.banner(gui, "ribbon", UDim2.fromOffset(340, 38), UDim2.new(0, 10, 0, 230), Skin.BUTTON_COLOR.orange)
quest.Visible = false
Skin.icon(quest, "icon_quest", UDim2.fromOffset(30, 30), UDim2.fromOffset(8, 4), "★", Skin.BUTTON_COLOR.gold)
local questText = Skin.text(quest, "", UDim2.new(1, -54, 1, -8), UDim2.fromOffset(44, 4), 22)
questText.TextXAlignment = Enum.TextXAlignment.Left
local questScale = Instance.new("UIScale")
questScale.Parent = quest
-- 選做任務(例:到好友星球採集):主線下面一條小彩帶
local side = Skin.banner(gui, "ribbon", UDim2.fromOffset(310, 30), UDim2.new(0, 10, 0, 272), Color3.fromRGB(70, 150, 230))
side.Visible = false
local sideText = Skin.text(side, "", UDim2.new(1, -24, 1, -8), UDim2.fromOffset(14, 4), 18)
sideText.TextXAlignment = Enum.TextXAlignment.Left
questEv.OnClientEvent:Connect(function(_, sq)
	side.Visible = sq ~= nil
	if sq then
		local prog = if sq.target > 1 then (" (%d/%d)"):format(sq.progress, sq.target) else ""
		sideText.Text = "👥 選做:" .. sq.text .. prog
	end
end)
questEv.OnClientEvent:Connect(function(cur)
	quest.Visible = true
	if cur then
		local prog = if cur.target > 1 then (" (%d/%d)"):format(cur.progress, cur.target) else ""
		questText.Text = "目標:" .. cur.text .. prog
	else
		questText.Text = "🏆 全部任務完成!"
	end
	-- 任務更新時彈一下,吸引注意
	questScale.Scale = 1.12
	TweenService:Create(questScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end)

-- ── 裂縫倒數 + 下一波預覽(右側)──
local wavePanel = Skin.panel(gui, UDim2.fromOffset(210, 70), UDim2.new(1, -220, 0, 112), Color3.fromRGB(200, 120, 255))
wavePanel.Visible = false
local waveText = Skin.text(wavePanel, "", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 4), 28)
local previewText = Skin.text(wavePanel, "", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 33), 20)
previewText.Font = Skin.FONT_BODY
previewText.TextWrapped = true
previewText.TextColor3 = Color3.fromRGB(230, 210, 255)
local waveStroke = wavePanel:FindFirstChildOfClass("UIStroke") :: UIStroke
local nextAt: number? = nil
local warnSec = 30
local boss = false

infoEv.OnClientEvent:Connect(function(info)
	nextAt = info.nextAt
	warnSec = info.warnSec
	boss = info.boss
	local parts = {}
	for _, m in info.preview do
		table.insert(parts, m.name .. "×" .. m.count)
	end
	previewText.Text = "下一波:" .. table.concat(parts, "、") .. (if info.scale > 1 then (" (巨大化×%d)"):format(info.scale) else "")
	wavePanel.Visible = true
end)

RunService.RenderStepped:Connect(function()
	if nextAt then
		local left = math.floor(math.max(0, nextAt - workspace:GetServerTimeNow())) -- %d 只吃整數
		local urgent = left <= warnSec
		waveText.Text = ("%s裂縫 %d:%02d"):format(if boss then "👹首領 " else "", left // 60, left % 60)
		-- 快開戰:面板變紅、外框閃爍
		wavePanel.BackgroundColor3 = if urgent then Color3.fromRGB(120, 24, 40) else Color3.fromRGB(22, 26, 52)
		waveStroke.Color = if urgent then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(200, 120, 255)
		waveStroke.Transparency = if urgent then 0.5 + 0.5 * math.sin(os.clock() * 8) else 0.25
	end
end)

-- ── 前往防守現場(預警開始到戰鬥結束才出現;穿梭中不顯示)──
local watchEv = Remotes.get("RequestWatch")
local watchBtn = Skin.button(gui, "⚔ 前往防守現場", "red", UDim2.fromOffset(210, 42), UDim2.new(1, -220, 0, 190))
watchBtn.Visible = false
local watchScale = watchBtn:FindFirstChildOfClass("UIScale") :: UIScale
local function refreshWatch()
	local show = workspace:GetAttribute("RiftActive") == true and not player:GetAttribute("InTrip")
	if show and not watchBtn.Visible then
		watchScale.Scale = 0.5
		TweenService:Create(watchScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	watchBtn.Visible = show
end
workspace:GetAttributeChangedSignal("RiftActive"):Connect(refreshWatch)
player:GetAttributeChangedSignal("InTrip"):Connect(refreshWatch)
refreshWatch()
watchBtn.Activated:Connect(function()
	watchEv:FireServer()
end)

-- ── 開戰前 3 秒:倒數自動傳送到防守現場(可取消)──
local autoPanel = Skin.panel(gui, UDim2.fromOffset(360, 118), UDim2.new(0.5, 0, 0.34, 0), Color3.fromRGB(255, 90, 90))
autoPanel.AnchorPoint = Vector2.new(0.5, 0.5)
autoPanel.Visible = false
local autoText = Skin.text(autoPanel, "", UDim2.new(1, -20, 0, 58), UDim2.fromOffset(10, 6), 26)
local cancelBtn = Skin.button(autoPanel, "取消傳送", "gray", UDim2.fromOffset(150, 40), UDim2.new(0.5, -75, 1, -48))
local autoAt: number? = nil

local function nearZone(): boolean
	local dir = workspace:GetAttribute("RiftDir") :: Vector3?
	local center = workspace:GetAttribute("PlanetCenter") :: Vector3?
	local radius = workspace:GetAttribute("PlanetRadius") :: number?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (dir and center and radius and root) then
		return false
	end
	return (root.Position - (center + dir * radius)).Magnitude < 70
end

workspace:GetAttributeChangedSignal("RiftAutoWatchAt"):Connect(function()
	local at = workspace:GetAttribute("RiftAutoWatchAt") :: number?
	-- 穿梭中、或人已經在降落區附近:不用傳送
	if not at or player:GetAttribute("InTrip") or nearZone() then
		return
	end
	autoAt = at
	autoPanel.Visible = true
end)
cancelBtn.Activated:Connect(function()
	autoAt = nil
	autoPanel.Visible = false
end)
RunService.RenderStepped:Connect(function()
	if not autoAt then
		return
	end
	local left = (autoAt :: number) - workspace:GetServerTimeNow()
	if left <= 0 then
		autoAt = nil
		autoPanel.Visible = false
		watchEv:FireServer()
		return
	end
	autoText.Text = ("⚔ 怪獸即將降落!\n%d 秒後傳送到防守現場"):format(math.ceil(left))
end)

-- ── 戰鬥結果橫幅(畫面中上)──
local banner = Skin.banner(gui, "title_banner", UDim2.fromOffset(520, 110), UDim2.new(0.5, 0, 0.26, 0), Skin.BUTTON_COLOR.gold)
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Visible = false
local bannerText = Skin.text(banner, "", UDim2.new(1, -60, 1, -20), UDim2.fromOffset(30, 10), 34)
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner
resultEv.OnClientEvent:Connect(function(res)
	local text
	if res.won then
		local parts = {}
		for id, n in res.reward or {} do
			table.insert(parts, (itemName[id] or id) .. "+" .. n)
		end
		text = ("守住第 %d 波!星核 %d/%d\n獎勵:%s"):format(res.index, res.coreLeft, res.coreMax, table.concat(parts, " "))
		banner.ImageColor3 = Color3.new(1, 1, 1)
		banner.BackgroundColor3 = Skin.BUTTON_COLOR.gold
	else
		text = ("第 %d 波失守(擊殺 %d/%d)\n補強防禦再來一次!"):format(res.index, res.killed, res.total)
		banner.ImageColor3 = Color3.fromRGB(255, 130, 130)
		banner.BackgroundColor3 = Skin.BUTTON_COLOR.red
	end
	bannerText.Text = text
	banner.Visible = true
	bannerScale.Scale = 0.3
	TweenService:Create(bannerScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(6, function()
		banner.Visible = false
	end)
end)

-- ── 時空門升級(右上,時空穿梭按鈕下方):平常收起來,材料夠才出現 + 紅點 ──
-- 時空門等級決定穿梭能去多遠、載重多大;也可以對時空門按 Shift+左鍵升級
local Warp = require(Shared.Data.Warp)
local upBtn, upText = Skin.button(gui, "⬆ 升級時空門", "purple", UDim2.fromOffset(190, 44), UDim2.new(1, -200, 0, 62))
upBtn.Visible = false
Skin.badge(upBtn).Visible = true -- 這顆出現就代表「可以升了」
local warpLv = 1
local inventory: { [string]: number } = {}
local tripping = false
local function refreshUpgrade()
	local cost = Warp.upgradeCost[warpLv + 1]
	local ok = cost ~= nil and not tripping and workspace:GetAttribute("OwnerUserId") == player.UserId
	if ok then
		for id, n in cost :: { [string]: number } do
			if (inventory[id] or 0) < n then
				ok = false
				break
			end
		end
	end
	upText.Text = ("⬆ 時空門 Lv%d"):format(warpLv + 1)
	upBtn.Visible = ok
end
Remotes.get("StateChanged").OnClientEvent:Connect(function(s)
	if s.Inventory then
		inventory = s.Inventory
	end
	if s.WarpLv then
		warpLv = s.WarpLv
	end
	refreshUpgrade()
end)
Remotes.get("TripChanged").OnClientEvent:Connect(function(info)
	tripping = info ~= nil
	refreshUpgrade()
end)
workspace:GetAttributeChangedSignal("OwnerUserId"):Connect(refreshUpgrade)
upBtn.Activated:Connect(function()
	upgradeWarpEv:FireServer()
end)

-- Shift+左鍵點建築 = 升級
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		return
	end
	local cam = workspace.CurrentCamera
	local pos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local built = workspace:FindFirstChild("Buildings")
	local markers = workspace:FindFirstChild("SlotMarkers")
	if not built or not markers then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { built }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not hit then
		return
	end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("BuildingId") == "WarpGate" then
		upgradeWarpEv:FireServer() -- 時空門升的是「時空門等級」(穿梭距離/載重),不是建築等級
		return
	end
	if model and model:GetAttribute("SlotKey") then
		upgradeEv:FireServer(model:GetAttribute("SlotKey"))
		return
	end
	local best, bestD = nil, math.huge
	for _, m in markers:GetChildren() do
		local d = ((m :: BasePart).Position - hit.Instance.Position).Magnitude
		if d < bestD then
			best, bestD = m.Name, d
		end
	end
	if best then
		upgradeEv:FireServer(best)
	end
end)

-- 依視窗大小等比縮放整個介面(小視窗不擠、不超出)
Skin.autoScale(gui)
