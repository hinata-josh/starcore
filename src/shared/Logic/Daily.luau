--!strict
-- 每日登入獎勵:連續登入第 1~7 天遞增,第 7 天大獎;斷一天從第 1 天重算(但只重算連續,不扣任何東西)。
-- day = os.time() // 86400(UTC 日序號);由呼叫端傳入,方便測試。

local Daily = {}

Daily.REWARDS = {
	{ Ore = 40 },
	{ Ore = 60, Metal = 5 },
	{ Ore = 80, Metal = 10 },
	{ Ore = 100, Metal = 15 },
	{ Ore = 120, Metal = 20, Crystal = 5 },
	{ Ore = 150, Metal = 30, Crystal = 10 },
	{ Ore = 200, Metal = 50, Crystal = 25 }, -- 第 7 天大獎
}

function Daily.dayOf(now: number): number
	return now // 86400
end

-- 今天可領的獎勵(不修改資料);已領過回 nil
function Daily.available(data: any, day: number): (number?, { [string]: number }?)
	local d = data.Daily
	if d.LastDay == day then
		return nil, nil
	end
	local streak = if d.LastDay == day - 1 then d.Streak + 1 else 1
	local idx = (streak - 1) % #Daily.REWARDS + 1
	return streak, Daily.REWARDS[idx]
end

-- 領取:發放並記錄;回傳 streak, reward(今天已領過回 nil)
function Daily.claim(data: any, day: number): (number?, { [string]: number }?)
	local streak, reward = Daily.available(data, day)
	if not streak or not reward then
		return nil, nil
	end
	for id, n in reward do
		data.Inventory[id] = (data.Inventory[id] or 0) + n
	end
	data.Daily.Streak = streak
	data.Daily.LastDay = day
	return streak, reward
end

return Daily
