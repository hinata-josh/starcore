--!strict
-- 開局贈送(純邏輯):每位玩家一座「指揮中心」(基地)+ 一座「脈衝砲台」(基本防守)+ 一座「時空門」。
-- 時空門直接送 → 主人一上線、好友就能用主人的門去穿梭採集,不用先蓋。
-- 新存檔(DataService 建檔時)和舊存檔(Migrate v4→v5 送基地+砲台、v5→v6 補時空門)都呼叫 grant;
-- 每樣各自檢查:已經有基地就不再送基地/砲台,已經有時空門就不再送門。
-- 位置:出生點(北極)旁邊的預設格位;被佔用就找離預設格最近的空格。

local CubeSphere = require(script.Parent.CubeSphere)

local Starter = {}

Starter.BASE = "CommandCenter"
Starter.DEFENSE = "PulseTurret"
Starter.BASE_KEY = "3_5_7" -- 出生點旁(北極附近,面 3 = +Y)
Starter.DEFENSE_KEY = "3_7_7" -- 基地右邊一格,砲口朝外
Starter.GATE = "WarpGate"
Starter.GATE_KEY = "3_3_7" -- 基地左邊一格

-- 離 preferred 最近的空格(preferred 本身空著就用它);整顆星球都滿了回 nil
local function nearestFree(slots: { [string]: any }, preferred: string, n: number, taken: { [string]: boolean }): string?
	if not slots[preferred] and not taken[preferred] then
		return preferred
	end
	local p = CubeSphere.parseKey(preferred, n)
	if not p then
		return nil
	end
	local d0 = CubeSphere.direction(p.face, p.u, p.v, n)
	local best, bestDot = nil, -2
	for face = 1, 6 do
		for u = 0, n - 1 do
			for v = 0, n - 1 do
				local key = CubeSphere.key(face, u, v)
				if not slots[key] and not taken[key] then
					local d = CubeSphere.direction(face, u, v, n)
					local dot = d.x * d0.x + d.y * d0.y + d.z * d0.z
					if dot > bestDot then
						best, bestDot = key, dot
					end
				end
			end
		end
	end
	return best
end

-- 送基地 + 砲台;回傳這次放下的 { key → 建築 id }(已經有基地就回空表、不動存檔)
function Starter.grant(data: any): { [string]: string }
	local placed: { [string]: string } = {}
	if not (data.Planet and data.Planet.Slots and data.Planet.N) then
		return placed -- 不完整的存檔(舊格式/測試資料)不動
	end
	local slots = data.Planet.Slots
	local n = data.Planet.N
	local hasBase, hasGate = false, false
	for _, s in slots do
		if s.Id == Starter.BASE then
			hasBase = true
		elseif s.Id == Starter.GATE then
			hasGate = true
		end
	end
	local taken: { [string]: boolean } = {}
	local function put(preferred: string, id: string)
		local key = nearestFree(slots, preferred, n, taken)
		if key then
			slots[key] = { Id = id, Lv = 1 }
			placed[key] = id
			taken[key] = true
		end
	end
	if not hasBase then
		put(Starter.BASE_KEY, Starter.BASE)
		put(Starter.DEFENSE_KEY, Starter.DEFENSE) -- 砲台只跟著第一次送基地時送(之後拆了不補)
	end
	if not hasGate then
		put(Starter.GATE_KEY, Starter.GATE)
	end
	return placed
end

return Starter
