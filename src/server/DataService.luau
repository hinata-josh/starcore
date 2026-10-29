--!strict
-- 玩家存檔:DataStore + session lock(防兩個伺服器同時改同一份檔)+ 版本遷移 + 自動存檔。
-- 在 Studio 未開啟 API 存取時退回記憶體模式(不持久化),並印出警告。

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Migrate = require(ReplicatedStorage.Shared.Logic.Migrate)
local Starter = require(ReplicatedStorage.Shared.Logic.Starter)

local STORE_NAME = "PlayerData_v1"
local LOCK_TIMEOUT = 90 -- 秒:鎖超過這麼久沒刷新視為伺服器已死
local AUTOSAVE_INTERVAL = 60
local LOAD_RETRIES = 6

local DataService = {}

local store: DataStore? = nil
local memoryMode = false
local cache: { [Player]: any } = {}
local loading: { [Player]: boolean } = {}

local function keyOf(player: Player): string
	return "Player_" .. player.UserId
end

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		memoryMode = true
	end
end

local function myJobId(): string
	return if RunService:IsStudio() then "studio" else game.JobId
end

local function lockFor(): any
	return { jobId = myJobId(), t = os.time() }
end

local function lockedByOther(lock: any): boolean
	return lock ~= nil and lock.jobId ~= myJobId() and os.time() - lock.t < LOCK_TIMEOUT
end

-- 新玩家存檔:空白範本 + 開局贈送(指揮中心 + 脈衝砲台,見 Logic/Starter)
local function newData(): any
	local data = Migrate.newPlayerData()
	Starter.grant(data)
	return data
end

-- 嘗試取得資料並上鎖;回傳 data 或 nil
local function acquire(player: Player): any?
	if memoryMode or not store then
		return newData()
	end
	for attempt = 1, LOAD_RETRIES do
		local result: any = nil
		local blocked = false
		local ok, err = pcall(function()
			store:UpdateAsync(keyOf(player), function(old)
				old = old or { data = nil, lock = nil }
				if lockedByOther(old.lock) then
					blocked = true
					return nil -- 不改動
				end
				old.lock = lockFor()
				result = old.data
				return old
			end)
		end)
		if ok and not blocked then
			local data = result or newData()
			Migrate.run(data) -- 存檔比程式新時會 error → 由外層 pcall 接住,不覆寫
			return data
		end
		if not ok then
			warn(("[DataService] 讀取失敗(第 %d 次):%s"):format(attempt, tostring(err)))
			-- Studio 沒開「Enable Studio Access to API Services」時每次都會失敗,
			-- 重試 6 次要卡一分多鐘(期間玩家不是主人、什麼都不能蓋),直接退回記憶體模式
			if RunService:IsStudio() then
				memoryMode = true
				warn("[DataService] Studio 無法存取 DataStore → 改用記憶體模式(不會保存)。要測存檔請到 Game Settings → Security 開啟 Enable Studio Access to API Services")
				return newData()
			end
		end
		task.wait(2 ^ math.min(attempt, 4))
	end
	return nil
end

function DataService.load(player: Player): any?
	if cache[player] then
		return cache[player]
	end
	if loading[player] then
		while loading[player] do
			task.wait(0.1)
		end
		return cache[player]
	end
	loading[player] = true
	local okLoad, data = pcall(acquire, player)
	loading[player] = nil
	if not okLoad or not data then
		warn("[DataService] 無法載入 " .. player.Name .. ":" .. tostring(data))
		return nil
	end
	cache[player] = data
	return data
end

function DataService.get(player: Player): any?
	return cache[player]
end

local function save(player: Player, release: boolean)
	local data = cache[player]
	if not data or memoryMode or not store then
		return
	end
	data.LastSeen = os.time() -- 離線收益用
	local ok, err = pcall(function()
		store:UpdateAsync(keyOf(player), function(old)
			if old and lockedByOther(old.lock) then
				return nil -- 鎖被別的伺服器拿走,不覆寫
			end
			return { data = data, lock = if release then nil else lockFor() }
		end)
	end)
	if not ok then
		warn("[DataService] 存檔失敗:" .. tostring(err))
	end
end

function DataService.save(player: Player)
	save(player, false)
end

Players.PlayerRemoving:Connect(function(player)
	save(player, true)
	cache[player] = nil
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		save(player, true)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player in cache do
			task.spawn(save, player, false)
		end
	end
end)

if memoryMode then
	warn("[DataService] DataStore 不可用,使用記憶體模式(不會保存)")
end

return DataService
