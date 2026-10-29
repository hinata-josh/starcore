--!strict
-- 背包:資源增減、載重。inv = { [itemId] = 數量 };全部是純函式/就地修改。

local Inventory = {}

function Inventory.canAfford(inv: { [string]: number }, cost: { [string]: number }): boolean
	for id, n in cost do
		if (inv[id] or 0) < n then
			return false
		end
	end
	return true
end

function Inventory.spend(inv: { [string]: number }, cost: { [string]: number })
	for id, n in cost do
		inv[id] = (inv[id] or 0) - n
	end
end

function Inventory.add(inv: { [string]: number }, id: string, n: number)
	inv[id] = (inv[id] or 0) + n
end

-- 總載重:Σ 數量 × 該物品 weight(items = Data.Items)
function Inventory.totalWeight(inv: { [string]: number }, items: any): number
	local w = {}
	for _, it in items.Types do
		w[it.id] = it.weight
	end
	local total = 0
	for id, n in inv do
		total += n * (w[id] or 1)
	end
	return total
end

-- 退款:floor(cost × ratio)
function Inventory.refund(cost: { [string]: number }, ratio: number): { [string]: number }
	local r = {}
	for id, n in cost do
		r[id] = math.floor(n * ratio)
	end
	return r
end

return Inventory
