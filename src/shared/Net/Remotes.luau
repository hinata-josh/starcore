--!strict
-- 單一 Remote 註冊表:client / server 都只從這裡取名稱,避免兩端字串不一致
-- (對應 N1-Pro 的「PackCmd 名稱必須與 Server 一致」)。
-- 新增 Remote:在 NAMES 加一行 + 在 docs/systems/net.md 記錄 payload。

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = {
	-- client → server(只送「意圖」,server 驗證後才改狀態)
	"PlaceBuilding", -- (slotKey: string, buildingId: string)
	"RemoveBuilding", -- (slotKey: string)
	"RequestWarp", -- ()
	"RequestReturn", -- ()
	"UpgradeBuilding", -- (slotKey: string)
	"UpgradeWarp", -- ()
	"RequestWatch", -- () 傳送到裂縫降落區旁觀戰(預警~戰鬥中才可用)
	"RebuildPlanet", -- () 重建星球:拆掉指揮中心以外全部建築、資源全數退還(只有主人、不在穿梭/來襲中)
	"RequestFriends", -- () 要「正在玩這個遊戲的線上好友」清單 → 伺服器回 FriendList
	"VisitFriend", -- (userId: number) 傳送到好友的星球
	"GoHome", -- () 傳送回自己的星球
	"FriendList", -- server → client (list: { {userId, name} })
	-- server → client
	"StateChanged", -- (patch: table)
	"TripChanged", -- (info: table?) 穿梭狀態;nil = 回到母星
	"CargoChanged", -- (loot: table, weight: number, capacity: number)
	"GatherState", -- (st: {readyAt(伺服器時間), interval, cooling={[id]=剩餘秒}})
	"WaveInfo", -- (info: {index, nextAt(伺服器時間), boss, preview={ {id,name,count} }, scale})
	"WaveResult", -- (res: {won, coreLeft, coreMax, reward, index})
	"QuestChanged", -- (cur: {id,text,progress,target}?)
	"ScreenFeed", -- (entry: {kind,text,data,t}) 中央螢幕訊息;kind=history 時 entry.list 是歷史
	"Notice", -- (text: string)
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.get(name: string): RemoteEvent
	local ev = folder:WaitForChild(name, 10)
	assert(ev, "Remote 未註冊:" .. name)
	return ev :: RemoteEvent
end

return Remotes
