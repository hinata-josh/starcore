--!strict
-- 母星資源:全遊戲 20 種資源,每位玩家的母星隨機擁有其中 5 種,再挑 2 種「高產」。
-- 其餘 15 種資源母星完全沒有,必須穿梭到別的星球採集(計畫書 §3.1/§3.2)。
-- 同一個玩家 seed 永遠得到同一組(存進存檔後就不再變)。

local Rng = require(script.Parent.Rng)

local HomePlanet = {}

HomePlanet.COUNT = 5 -- 母星資源種類
HomePlanet.BOOSTED = 2 -- 其中高產的種類
HomePlanet.NORMAL_RATE = 0.1 -- 每台採集機每秒(Lv1)的基礎產量
HomePlanet.BOOST_RATE = 0.35 -- 高產資源的基礎產量(3.5 倍)
HomePlanet.MAX_EPIC = 1 -- 母星最多 1 種傳說級資源(避免開局就富可敵國)

export type Home = { Resources: { string }, Boosted: { string }, Rates: { [string]: number } }

function HomePlanet.generate(seed: number, items: any): Home
	local rng = Rng.new(seed)
	local ids, epic = {}, {}
	for _, it in items.Types do
		table.insert(ids, it.id)
		epic[it.id] = it.rarity == "epic"
	end
	local picked: { string } = {}
	for _ = 1, 30 do -- 有限次重抽,滿足「傳說級最多 1 種」
		local pool = table.clone(ids)
		for i = #pool, 2, -1 do -- Fisher–Yates 洗牌
			local j = Rng.int(rng, 1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		picked = {}
		local epics = 0
		for i = 1, HomePlanet.COUNT do
			table.insert(picked, pool[i])
			if epic[pool[i]] then
				epics += 1
			end
		end
		if epics <= HomePlanet.MAX_EPIC then
			break
		end
	end
	local rateOf = {}
	for _, it in items.Types do
		rateOf[it.id] = it.rate
	end
	local boosted: { string } = {}
	local rates: { [string]: number } = {}
	for i, id in picked do
		local isBoost = i <= HomePlanet.BOOSTED
		if isBoost then
			table.insert(boosted, id)
		end
		rates[id] = (if isBoost then HomePlanet.BOOST_RATE else HomePlanet.NORMAL_RATE) * (rateOf[id] or 1)
	end
	return { Resources = picked, Boosted = boosted, Rates = rates }
end

-- 存檔還沒有母星資料時指派一份(伺服器載入存檔後呼叫);已有就保持不變
function HomePlanet.ensure(data: any, seed: number, items: any): Home
	if not data.Planet.Home then
		data.Planet.Home = HomePlanet.generate(seed, items)
	end
	return data.Planet.Home
end

return HomePlanet
