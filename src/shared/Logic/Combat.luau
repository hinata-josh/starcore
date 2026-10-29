--!strict
-- 一波戰鬥的確定性模擬(純邏輯)。伺服器用它算結果,再把事件「回放」成畫面;平衡模擬器也用它。
-- 抽象化:怪獸從裂縫降落 → 走 travel 秒抵達 → 開始攻擊星球(護盾→牆→星核)。
-- 砲台只對「已進入射程(抵達前 RANGE_LEAD 秒起)」的怪獸輸出,集火最早的那隻,溢出傷害不浪費。

local Energy = require(script.Parent.Energy)

local Combat = {}

Combat.STEP = 0.5
Combat.MAX_TIME = 300
Combat.RANGE_LEAD = 4 -- 怪獸抵達前幾秒就能被砲台打到
Combat.BASE_CORE_HP = 300
Combat.CORE_HP_PER_LEVEL = 100
Combat.LEVEL_BONUS = 0.5 -- 建築每升一級 +50% 數值
Combat.MAX_SLOW = 0.4
Combat.SAMPLE_EVERY = 2 -- 秒

export type Defense = { dps: number, shield: number, wallHp: number, coreHp: number, power: number, dmgMult: number }

function Combat.coreHp(level: number): number
	return Combat.BASE_CORE_HP + Combat.CORE_HP_PER_LEVEL * (level - 1)
end

-- 由已蓋建築算出防禦總覽。電力不足時,砲台與護盾按滿足率縮水;牆不吃電。
function Combat.defenseOf(placed: { { id: string, lv: number? } }, defs: any, level: number): Defense
	local byId = {}
	for _, d in defs.Types do
		byId[d.id] = d
	end
	local sat = Energy.balance(placed, defs).satisfaction
	local dps, shield, wall, slow, coreBonus = 0, 0, 0, 0, 0
	for _, b in placed do
		local d = byId[b.id]
		if d then
			local mult = 1 + Combat.LEVEL_BONUS * ((b.lv or 1) - 1)
			dps += (d.dps or 0) * mult
			shield += (d.shield or 0) * mult
			wall += (d.wallHp or 0) * mult
			coreBonus += (d.coreHp or 0) * mult
			slow += (d.slow or 0) * sat -- 沒電時冰凍效果也縮水
		end
	end
	return { dps = dps * sat, shield = shield * sat, wallHp = wall, coreHp = Combat.coreHp(level) + coreBonus, power = sat,
		dmgMult = 1 - math.min(Combat.MAX_SLOW, slow) }
end

export type Event = { t: number, kind: string, index: number? }
export type Sample = { t: number, core: number, shield: number, wall: number, alive: number }
export type Result = {
	won: boolean,
	coreHpLeft: number,
	duration: number,
	killed: number,
	total: number,
	events: { Event },
	samples: { Sample }, -- 每 SAMPLE_EVERY 秒一筆戰況(中央螢幕播放用)
}

-- comp = WaveLogic.compose 的結果;threat = 本波強度(首領血量/傷害依它縮放)
function Combat.simulate(defense: Defense, comp: any, monsters: any, threat: number): Result
	local mons = {}
	local byId = {}
	for _, m in monsters.Types do
		byId[m.id] = m
	end
	local order = {}
	for id in comp.counts do
		table.insert(order, id)
	end
	table.sort(order) -- 確定性排序
	local k = 0
	for _, id in order do
		for _ = 1, comp.counts[id] do
			local m = byId[id]
			local sc = comp.scale or 1
			table.insert(mons, { hp = m.hp * sc, dmg = m.dmg * sc, arrive = k * monsters.spawnGap + m.travel, id = id })
			k += 1
		end
	end
	if comp.bossId then
		local b = monsters.Boss
		table.insert(mons, {
			hp = threat * b.hpPerBudget, dmg = threat * b.dmgPerBudget,
			arrive = k * monsters.spawnGap + b.travel, id = b.id,
		})
	end

	local events: { Event } = {}
	local shield, wall, core = defense.shield, defense.wallHp, defense.coreHp
	local alive = #mons
	local t = 0
	local samples: { Sample } = { { t = 0, core = core, shield = shield, wall = wall, alive = alive } }
	local nextSample = Combat.SAMPLE_EVERY
	for i, m in mons do
		table.insert(events, { t = 0, kind = "spawn", index = i })
	end
	while alive > 0 and core > 0 and t < Combat.MAX_TIME do
		t += Combat.STEP
		-- 砲台:集火最早進入射程的怪
		local budget = defense.dps * Combat.STEP
		for i, m in mons do
			if budget <= 0 then
				break
			end
			if m.hp > 0 and t >= m.arrive - Combat.RANGE_LEAD then
				local hit = math.min(m.hp, budget)
				m.hp -= hit
				budget -= hit
				if m.hp <= 0 then
					alive -= 1
					table.insert(events, { t = t, kind = "kill", index = i })
				end
			end
		end
		-- 怪獸攻擊:護盾 → 牆 → 星核
		local dmg = 0
		for _, m in mons do
			if m.hp > 0 and t >= m.arrive then
				dmg += m.dmg * Combat.STEP * defense.dmgMult
			end
		end
		if dmg > 0 then
			local a = math.min(shield, dmg)
			shield -= a
			dmg -= a
			a = math.min(wall, dmg)
			wall -= a
			dmg -= a
			core -= dmg
		end
		if t >= nextSample then
			table.insert(samples, { t = t, core = math.max(0, core), shield = shield, wall = wall, alive = alive })
			nextSample += Combat.SAMPLE_EVERY
		end
	end
	table.insert(samples, { t = t, core = math.max(0, core), shield = shield, wall = wall, alive = alive })
	local won = core > 0 and alive == 0
	table.insert(events, { t = t, kind = if won then "win" else "lose" })
	return { won = won, coreHpLeft = math.max(0, core), duration = t, killed = #mons - alive, total = #mons, events = events, samples = samples }
end

return Combat
