--!strict
-- 星門裂縫波次:強度公式 + 組波。數值為初版,待模擬器校準(見計畫書附錄 A)。

local Rng = require(script.Parent.Rng)

local WaveLogic = {}

WaveLogic.BASE_THREAT = 60 -- 第 1 波只有 3 隻酸液蟲:新手開局資源就能守住(試玩發現 100 時只蓋 1 砲台必輸)
WaveLogic.GROWTH = 1.27
WaveLogic.MAX_VISIBLE = 14 -- 同一波最多幾隻怪(畫面/效能上限);超過就合併成「巨大化」怪獸
WaveLogic.FIRST_WAVE_DELAY = 300 -- 開局第一波 5 分鐘後(新手教學期),之後依 countdownSeconds
WaveLogic.TARGET_DEFENSE_RATIO = 1.3 -- 防禦力評分 ≈ 1.3 × 強度 時新手勝率約 85%

function WaveLogic.threat(n: number): number
	return WaveLogic.BASE_THREAT * WaveLogic.GROWTH ^ (n - 1)
end

-- 連敗減壓:連續失守同一波時,下一次怪獸強度打折(每敗一次 -15%,最多 -45%),贏了就恢復。
-- 目的:對國小生友善,避免卡在首領波反覆受挫;但不會讓人躺著贏(仍需補強防禦)。
function WaveLogic.mercy(losses: number): number
	return 1 - 0.15 * math.min(math.max(losses, 0), 3)
end

function WaveLogic.isBoss(n: number, monsters: any): boolean
	return n % monsters.Boss.bossEvery == 0
end

-- 倒數秒數:10 分鐘起跳,隨波數慢慢拉長到 12 分鐘上限
function WaveLogic.countdownSeconds(n: number): number
	return 600 + math.min(n, 20) * 6
end

export type Composition = { counts: { [string]: number }, bossId: string?, spent: number, budget: number, scale: number }

-- 在強度預算內,從已解鎖的怪獸挑組合;預算花不完時,剩餘不足一隻最便宜怪的部分才會剩下
function WaveLogic.compose(n: number, seed: number, monsters: any, mult: number?): Composition
	local budget = WaveLogic.threat(n) * (mult or 1)
	local rng = Rng.new(seed + n * 7919)
	local spent = 0
	local bossId: string? = nil
	if WaveLogic.isBoss(n, monsters) then
		bossId = monsters.Boss.id
		spent = budget * monsters.Boss.budgetShare
	end
	local pool = {}
	for _, m in monsters.Types do
		if m.unlockWave <= n then
			table.insert(pool, m)
		end
	end
	local counts: { [string]: number } = {}
	while true do
		local affordable = {}
		for _, m in pool do
			if spent + m.cost <= budget then
				table.insert(affordable, m)
			end
		end
		if #affordable == 0 then
			break
		end
		-- 貴的怪被抽中的機率更高(cost²),後期出現的是大隻怪而不是一大群小蟲
		local pick = Rng.weighted(rng, affordable, function(m)
			return m.cost * m.cost
		end)
		counts[pick.id] = (counts[pick.id] or 0) + 1
		spent += pick.cost
	end
	-- 怪太多:合併成較少隻,每隻血量/傷害乘 scale,總強度不變
	local total = 0
	for _, c in counts do
		total += c
	end
	local scale = 1
	if total > WaveLogic.MAX_VISIBLE then
		scale = math.ceil(total / WaveLogic.MAX_VISIBLE)
		for id, c in counts do
			counts[id] = math.max(1, math.floor(c / scale + 0.5))
		end
	end
	return { counts = counts, bossId = bossId, spent = spent, budget = budget, scale = scale }
end

-- 防禦力評分:Σ(砲台DPS × 電力滿足率) + 護盾×0.5 + 牆體HP×0.2
function WaveLogic.defenseScore(turretDps: number, powerSatisfaction: number, shield: number, wallHp: number): number
	return turretDps * powerSatisfaction + shield * 0.5 + wallHp * 0.2
end

-- 守住一波的獎勵(首領波額外給晶體)
function WaveLogic.reward(n: number, monsters: any): { [string]: number }
	local r: { [string]: number } = { Ore = 15 + 3 * n, Metal = 3 + n }
	if WaveLogic.isBoss(n, monsters) then
		r.Crystal = 5 + n
	end
	return r
end

function WaveLogic.defenseTarget(n: number): number
	return WaveLogic.TARGET_DEFENSE_RATIO * WaveLogic.threat(n)
end

return WaveLogic
