--!strict
-- 「每位玩家一台專屬私人伺服器 = 他的星球」:
--   * 每人一個保留伺服器代碼(TeleportService:ReserveServer),存在 DataStore,永久固定。
--   * 回家 / 拜訪好友 = TeleportToPrivateServer 到「那個人的代碼」,TeleportData 帶 homeOwner = 那個人的 UserId。
--   * 私人伺服器的主人 = homeOwner(不是先進來的人);訪客先到也不會變主人。
--   * 正式環境的公開伺服器當「大廳」:玩家進來就送回自己的星球。Studio 不傳送(維持原本第一位進來的人當主人)。

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local SHOW_LOG = true
local function log(...)
	if SHOW_LOG then
		print("[HomeOwner]", ...)
	end
end

local HomeOwner = {}

local store: DataStore? = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("HomeServers_v1")
	end)
	if ok then
		store = s
	end
end

function HomeOwner.isStudio(): boolean
	return RunService:IsStudio()
end

-- 正式環境的公開伺服器 = 大廳(玩家會被送回自己的星球)
function HomeOwner.isLobby(): boolean
	return not RunService:IsStudio() and game.PrivateServerId == ""
end

-- 這台私人伺服器屬於誰:第一位帶 TeleportData.homeOwner 進來的人決定,記在 workspace 屬性 HomeOwnerId
function HomeOwner.resolve(player: Player): number?
	local cur = workspace:GetAttribute("HomeOwnerId") :: number?
	if cur then
		return cur
	end
	if game.PrivateServerId == "" then
		return nil
	end
	local ok, jd = pcall(function()
		return player:GetJoinData()
	end)
	local td = if ok and jd then (jd :: any).TeleportData else nil
	if type(td) == "table" and type(td.homeOwner) == "number" then
		workspace:SetAttribute("HomeOwnerId", td.homeOwner)
		log("這台私人伺服器是", td.homeOwner, "的星球")
		return td.homeOwner
	end
	return nil
end

-- 某位玩家的保留伺服器代碼(沒有就建一個並存起來)
local cache: { [number]: string } = {}
function HomeOwner.codeFor(userId: number): string?
	if cache[userId] then
		return cache[userId]
	end
	if not store then
		return nil
	end
	local key = "Home_" .. userId
	local okGet, existing = pcall(function()
		return (store :: DataStore):GetAsync(key)
	end)
	if okGet and type(existing) == "string" then
		cache[userId] = existing
		return existing
	end
	local okRes, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not okRes or type(code) ~= "string" then
		log("建立保留伺服器失敗:", code)
		return nil
	end
	-- 兩台伺服器同時替同一人建代碼:以先寫入的為準
	local final = code
	pcall(function()
		(store :: DataStore):UpdateAsync(key, function(old)
			if type(old) == "string" then
				final = old
				return nil
			end
			return code
		end)
	end)
	cache[userId] = final
	return final
end

-- 把 player 傳送到 ownerId 的星球;回傳 (成功?, 失敗原因)
function HomeOwner.teleportTo(player: Player, ownerId: number): (boolean, string?)
	if RunService:IsStudio() then
		return false, "Studio 不能傳送,要在正式伺服器測"
	end
	local code = HomeOwner.codeFor(ownerId)
	if not code then
		return false, "找不到星球伺服器,稍後再試"
	end
	local ok, err = pcall(function()
		TeleportService:TeleportToPrivateServer(game.PlaceId, code :: string, { player }, nil, { homeOwner = ownerId })
	end)
	log("傳送", player.Name, "→", ownerId, "的星球", if ok then "OK" else tostring(err))
	return ok, if ok then nil else "傳送失敗:" .. tostring(err)
end

return HomeOwner
