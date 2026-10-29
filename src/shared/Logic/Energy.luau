--!strict
-- 能源平衡:發電 < 耗電 時,所有耗電建築按比例降速(工程師模式的核心)。
-- buildings = { {id=..., lv=...}, ... };defs = Data.Buildings

local Energy = {}

export type Balance = { generation: number, demand: number, satisfaction: number }

function Energy.balance(placed: { { id: string } }, defs: any): Balance
	local byId = {}
	for _, d in defs.Types do
		byId[d.id] = d
	end
	local gen, demand = 0, 0
	for _, b in placed do
		local d = byId[b.id]
		if d then
			if d.power > 0 then
				gen += d.power
			else
				demand += -d.power
			end
		end
	end
	local sat = 1
	if demand > 0 then
		sat = math.min(1, gen / demand)
	end
	return { generation = gen, demand = demand, satisfaction = sat }
end

return Energy
