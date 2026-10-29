--!strict
-- 一趟時空穿梭:資源點生成、採集、載重結算。純邏輯、時間用參數傳入(now),可離線測試。
-- 規則(計畫書 §3.2):
--   • 撿取時最多到「載重 × overloadFactor」(貪心空間)
--   • 自己按返航 → 全部帶回
--   • 倒數到被強制拉回 → 超出載重的部分只保留 overflowKeep(預設 50%)

local Rng = require(script.Parent.Rng)

local Trip = {}

export type Node = { id: string, amount: number, dir: { x: number, y: number, z: number } }
export type TripState = {
	seed: number,
	planet: any,
	startedAt: number,
	expiresAt: number,
	nodes: { Node },
	loot: { [string]: number },
	capacity: number,
}

function Trip.capacity(warpLv: number, cfg: any): number
	return cfg.capacityByLevel[math.min(math.max(warpLv, 1), #cfg.capacityByLevel)]
end

local function weightTable(items: any): { [string]: number }
	local w = {}
	for _, it in items.Types do
		w[it.id] = it.weight
	end
	return w
end

local function lootWeight(loot: { [string]: number }, w: { [string]: number }): number
	local total = 0
	for id, n in loot do
		total += n * (w[id] or 1)
	end
	return total
end

-- 在球面上隨機撒資源點;避開北極(出生/返航點,y > 0.92)。每種資源的總量 = planet.resources[i].amount
function Trip.spawnNodes(planet: any, seed: number, cfg: any): { Node }
	local rng = Rng.new(seed * 31 + 17)
	local nodes: { Node } = {}
	for _, r in planet.resources do
		local count = math.max(1, math.ceil(r.amount / cfg.nodeSize))
		local base = r.amount // count
		local extra = r.amount - base * count
		for i = 1, count do
			local dir
			for _ = 1, 20 do
				local y = Rng.next(rng) * 2 - 1
				local a = Rng.next(rng) * 2 * math.pi
				local s = math.sqrt(1 - y * y)
				dir = { x = s * math.cos(a), y = y, z = s * math.sin(a) }
				if y <= 0.92 then
					break
				end
			end
			table.insert(nodes, { id = r.id, amount = base + (if i <= extra then 1 else 0), dir = dir })
		end
	end
	return nodes
end

function Trip.start(seed: number, planet: any, now: number, warpLv: number, cfg: any): TripState
	return {
		seed = seed,
		planet = planet,
		startedAt = now,
		expiresAt = now + cfg.durationSec,
		nodes = Trip.spawnNodes(planet, seed, cfg),
		loot = {},
		capacity = Trip.capacity(warpLv, cfg),
	}
end

function Trip.timeLeft(trip: TripState, now: number): number
	return math.max(0, trip.expiresAt - now)
end

function Trip.expired(trip: TripState, now: number): boolean
	return now >= trip.expiresAt
end

function Trip.weight(trip: TripState, items: any): number
	return lootWeight(trip.loot, weightTable(items))
end

-- 採集第 index 個資源點。回傳 ok, 取得數量或錯誤碼(BadNode / Empty / Full)
function Trip.gather(trip: TripState, index: number, items: any, cfg: any): (boolean, any)
	local node = trip.nodes[index]
	if not node then
		return false, "BadNode"
	end
	if node.amount <= 0 then
		return false, "Empty"
	end
	local w = weightTable(items)
	local unit = w[node.id] or 1
	local room = trip.capacity * cfg.overloadFactor - lootWeight(trip.loot, w)
	local allowed = math.floor(room / unit)
	if allowed <= 0 then
		return false, "Full"
	end
	local take = math.min(node.amount, cfg.gatherPerAction, allowed)
	node.amount -= take
	trip.loot[node.id] = (trip.loot[node.id] or 0) + take
	return true, take
end

-- 結算:回傳實際帶回的 { [itemId] = 數量 }
function Trip.settle(trip: TripState, items: any, cfg: any, timedOut: boolean): { [string]: number }
	local w = weightTable(items)
	local total = lootWeight(trip.loot, w)
	local ratio = 1
	if timedOut and total > trip.capacity then
		local keptWeight = trip.capacity + (total - trip.capacity) * cfg.overflowKeep
		ratio = keptWeight / total
	end
	local kept = {}
	for id, n in trip.loot do
		local k = math.floor(n * ratio)
		if k > 0 then
			kept[id] = k
		end
	end
	return kept
end

return Trip
