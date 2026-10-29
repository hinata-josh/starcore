--!strict
-- 母星資源點:母星上依「母星自己的 5 種資源」擺放可手動採集的點,主人與好友都能採。
-- 採到的東西進採集者「自己」的背包,並受採集者自己的間隔/20 次冷卻限制(Logic/Gather);
-- 資源點被採光後過一段時間重生。時間 now 由呼叫端傳入,可離線測試。

local Rng = require(script.Parent.Rng)

local HomeNode = {}

HomeNode.PER_RESOURCE = 2 -- 每種母星資源擺幾個點
HomeNode.AMOUNT = 40 -- 每個點的資源量
HomeNode.RESPAWN = 90 -- 被採光後幾秒重生

export type Node = { id: string, dir: { x: number, y: number, z: number }, amount: number, respawnAt: number }

-- 依主人的母星資源與 seed 擺點(同 seed 位置固定);避開北極(出生點,y > 0.9)
function HomeNode.layout(home: any, seed: number): { Node }
	local rng = Rng.new(seed * 13 + 5)
	local nodes: { Node } = {}
	for _, id in home.Resources do
		for _ = 1, HomeNode.PER_RESOURCE do
			local dir
			for _ = 1, 20 do
				local y = Rng.next(rng) * 2 - 1
				local a = Rng.next(rng) * 2 * math.pi
				local s = math.sqrt(1 - y * y)
				dir = { x = s * math.cos(a), y = y, z = s * math.sin(a) }
				if y <= 0.9 then
					break
				end
			end
			table.insert(nodes, { id = id, dir = dir, amount = HomeNode.AMOUNT, respawnAt = 0 })
		end
	end
	return nodes
end

-- 時間到了就重生(回傳這個點現在可採的量)
function HomeNode.refresh(node: Node, now: number): number
	if node.amount <= 0 and node.respawnAt > 0 and now >= node.respawnAt then
		node.amount = HomeNode.AMOUNT
		node.respawnAt = 0
	end
	return node.amount
end

-- 採集:最多拿 want 個;回傳實際拿到的量(0 = 這個點空了)
function HomeNode.harvest(node: Node, want: number, now: number): number
	local avail = HomeNode.refresh(node, now)
	if avail <= 0 then
		return 0
	end
	local take = math.min(avail, want)
	node.amount -= take
	if node.amount <= 0 then
		node.respawnAt = now + HomeNode.RESPAWN
	end
	return take
end

return HomeNode
