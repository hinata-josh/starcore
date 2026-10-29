--!strict
-- 玩家手動採集的節奏限制(純邏輯,時間 now 由呼叫端傳入):
--   • 兩次採集之間要隔一段時間,間隔取決於母星開發程度(星球等級):Lv1 = 120 秒 → 滿級 = 20 秒(線性)
--   • 同一種資源累計採集 LIMIT(20)次後,進入 COOLDOWN(12 小時)冷卻,期間不能再採這種資源
-- 存檔欄位 data.Gather = { LastAt = 上次採集時間, Counts = {[id]=次數}, CooldownUntil = {[id]=解除時間} }

local Gather = {}

Gather.MIN_INTERVAL = 20 -- 秒(星球滿級)
Gather.MAX_INTERVAL = 120 -- 秒(星球 Lv1;先限制在 2 分鐘)
Gather.LIMIT = 20 -- 同一資源採幾次後冷卻
Gather.COOLDOWN = 12 * 3600 -- 冷卻時間(半天)

-- 星球等級 → 採集間隔(秒)
function Gather.interval(level: number, maxLevel: number): number
	local t = math.clamp((level - 1) / math.max(1, maxLevel - 1), 0, 1)
	return math.floor(Gather.MAX_INTERVAL - (Gather.MAX_INTERVAL - Gather.MIN_INTERVAL) * t + 0.5)
end

-- 能不能採這種資源;回傳 ok, 原因("Cooldown" 該資源冷卻中 / "TooSoon" 間隔未到), 還要等幾秒
function Gather.check(data: any, itemId: string, now: number, level: number, maxLevel: number): (boolean, string?, number?)
	local g = data.Gather
	local cd = g.CooldownUntil[itemId]
	if cd then
		if now < cd then
			return false, "Cooldown", cd - now
		end
		g.CooldownUntil[itemId] = nil -- 冷卻結束,重新計次
	end
	local wait = g.LastAt + Gather.interval(level, maxLevel) - now
	if wait > 0 then
		return false, "TooSoon", wait
	end
	return true, nil, 0
end

-- 成功採集一次後記錄;回傳這種資源是否因此進入冷卻
function Gather.record(data: any, itemId: string, now: number): boolean
	local g = data.Gather
	g.LastAt = now
	g.Counts[itemId] = (g.Counts[itemId] or 0) + 1
	if g.Counts[itemId] >= Gather.LIMIT then
		g.Counts[itemId] = 0
		g.CooldownUntil[itemId] = now + Gather.COOLDOWN
		return true
	end
	return false
end

-- 給 UI:下次可採集的剩餘秒數、各資源冷卻剩餘秒數
function Gather.status(data: any, now: number, level: number, maxLevel: number): { readyIn: number, interval: number, cooling: { [string]: number } }
	local g = data.Gather
	local cooling: { [string]: number } = {}
	for id, t in g.CooldownUntil do
		if t > now then
			cooling[id] = t - now
		end
	end
	local interval = Gather.interval(level, maxLevel)
	return { readyIn = math.max(0, g.LastAt + interval - now), interval = interval, cooling = cooling }
end

return Gather
