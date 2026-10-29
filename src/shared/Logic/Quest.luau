--!strict
-- 任務進度(純邏輯)。notify 在遊戲事件發生時呼叫;完成的任務立刻發獎勵,回傳剛完成的清單供提示。
-- data.Quests = { Done = {[id]=true}, Progress = {[id]=n} }

local Inventory = require(script.Parent.Inventory)

local Quest = {}

export type Done = { id: string, text: string, reward: { [string]: number } }

function Quest.notify(data: any, event: string, arg: any, quests: any): { Done }
	local q = data.Quests
	q.Progress = q.Progress or {}
	local finished: { Done } = {}
	for _, def in quests.Chain do
		if not q.Done[def.id] and def.event == event then
			local hit = false
			if def.atLeast then
				-- 「打到第 N 波 / 升到 Lv N」:arg 是目前達到的數值
				hit = type(arg) == "number" and arg >= def.target
				if hit then
					q.Progress[def.id] = def.target
				end
			elseif def.match == nil or def.match == arg then
				q.Progress[def.id] = (q.Progress[def.id] or 0) + 1
				hit = q.Progress[def.id] >= def.target
			end
			if hit then
				q.Done[def.id] = true
				for id, n in def.reward do
					Inventory.add(data.Inventory, id, n)
				end
				table.insert(finished, { id = def.id, text = def.text, reward = def.reward })
			end
		end
	end
	return finished
end

-- 目前該顯示的主線任務(鏈上第一個未完成、非選做的),附進度
function Quest.current(data: any, quests: any): { id: string, text: string, progress: number, target: number }?
	for _, def in quests.Chain do
		if not def.optional and not data.Quests.Done[def.id] then
			local prog = (data.Quests.Progress or {})[def.id] or 0
			return { id = def.id, text = def.text, progress = prog, target = def.target }
		end
	end
	return nil
end

-- 目前的選做任務(第一個未完成的 optional),沒有回 nil
function Quest.side(data: any, quests: any): { id: string, text: string, progress: number, target: number }?
	for _, def in quests.Chain do
		if def.optional and not data.Quests.Done[def.id] then
			local prog = (data.Quests.Progress or {})[def.id] or 0
			return { id = def.id, text = def.text, progress = prog, target = def.target }
		end
	end
	return nil
end

function Quest.doneCount(data: any): number
	local c = 0
	for _ in data.Quests.Done do
		c += 1
	end
	return c
end

return Quest
