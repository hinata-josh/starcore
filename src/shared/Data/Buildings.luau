--!strict
-- 建築資料表(50 種)。power > 0 發電、< 0 耗電。cost 的 key 必須是 Items 內的資源 id。
-- 實作中的數值欄位:dps(攻擊)/ shield(護盾)/ wallHp(牆)/ slow(減傷,上限 40%)/ coreHp(星核加成)/
--                  yield(採集倍率,基準 1)/ storage(每種資源存量上限加成)/ warningBonus(預警秒數加成)。
-- 建築等級 tier(T1–T5):越強的建築需要的「資源種類」越多(MinTypesByTier;資料測試強制檢查)。
-- 新手四件(採集機/太陽能板/時空門/脈衝砲台)只用 礦石+金屬(開局物資剛好夠),進階建築才吃其他資源 → 逼玩家去別的星球採。
-- 升級:Lv→Lv+1 = 原價×1.5×目前等級 + UpgradeLadder[類別][目標等級] 的額外材料(越高級越需要稀有資源)。
-- 採集建築有母星資料(Planet.Home)時產母星自己的 5 種資源 × yield;沒有時用 produces 當後備。

local function B(id: string, name: string, category: string, cost: { [string]: number }, power: number, stats: any?): any
	local t: any = { id = id, name = name, category = category, cost = cost, power = power }
	if stats then
		for k, v in stats do
			t[k] = v
		end
	end
	return t
end

local Buildings = {
	DataVersion = 3,
	MaxLevel = 3,
	MinTypesByTier = { 1, 2, 3, 4, 5 }, -- T1 至少 1 種資源、T2 至少 2 種 … T5 至少 5 種
	-- 升到「目標等級」時,額外需要的材料(依類別)
	UpgradeLadder = {
		Energy = { [2] = { Copper = 6 }, [3] = { Silicon = 8, Titanium = 4 } },
		Collect = { [2] = { Metal = 10 }, [3] = { Copper = 12, Titanium = 4 } },
		Attack = { [2] = { Copper = 8 }, [3] = { Titanium = 6, Crystal = 3 } },
		Defense = { [2] = { Metal = 8 }, [3] = { Titanium = 6, Amber = 4 } },
		Storage = { [2] = { Metal = 10 }, [3] = { Titanium = 6 } },
		Support = { [2] = { Silicon = 6 }, [3] = { Glowstone = 3 } },
		Tech = { [2] = { Crystal = 5 }, [3] = { Stardust = 2 } },
	},
	Types = {
		-- ── 能源(9)──
		B("SolarPanel", "太陽能板", "Energy", { Ore = 15, Metal = 5 }, 4, { tier = 1 }),
		B("WindTurbine", "風力發電機", "Energy", { Metal = 15, Copper = 8 }, 6, { tier = 2 }),
		B("BioReactor", "生質反應爐", "Energy", { Biomass = 15, Coal = 10 }, 8, { tier = 2 }),
		B("HydroGen", "水力發電機", "Energy", { Water = 20, Copper = 10 }, 9, { tier = 2 }),
		B("CoalPlant", "燃煤發電廠", "Energy", { Coal = 20, Metal = 10 }, 10, { tier = 2 }),
		B("CrystalReactor", "晶體反應爐", "Energy", { Metal = 20, Crystal = 10, Copper = 10 }, 16, { tier = 3 }),
		B("GeothermalPlant", "地熱發電廠", "Energy", { LavaCore = 6, Metal = 20, Sulfur = 6 }, 20, { tier = 3 }),
		B("StarReactor", "星塵反應爐", "Energy", { Stardust = 6, Plasma = 4, Titanium = 10, Silicon = 8 }, 45, { tier = 4 }),
		B("FusionCore", "核融合爐", "Energy", { Plasma = 8, Stardust = 4, Titanium = 15, Silicon = 10, Crystal = 8 }, 80, { tier = 5 }),
		-- ── 採集(6)──
		B("Miner", "採集機", "Collect", { Ore = 20 }, -2, { yield = 1, tier = 1, produces = { Ore = 1 } }),
		B("AutoHarvester", "自動採集臂", "Collect", { Scrap = 20, Copper = 5 }, -2, { yield = 1.3, tier = 2, produces = { Ore = 1 } }),
		B("HeavyDrill", "重型鑽機", "Collect", { Metal = 25, Copper = 10, Scrap = 10 }, -4, { yield = 1.8, tier = 3, produces = { Ore = 1 } }),
		B("DeepDrill", "深層鑽探機", "Collect", { Titanium = 10, Metal = 20, Silicon = 10, Copper = 10 }, -7, { yield = 3, tier = 4, produces = { Ore = 1 } }),
		B("PlasmaExtractor", "電漿萃取器", "Collect", { Plasma = 5, Titanium = 10, Silicon = 10, Copper = 8 }, -9, { yield = 4, tier = 4, produces = { Ore = 1 } }),
		B("QuantumHarvester", "量子採集器", "Collect", { Stardust = 4, Silicon = 15, Titanium = 10, Plasma = 3, Crystal = 6 }, -10, { yield = 5, tier = 5, produces = { Ore = 1 } }),
		-- ── 倉儲(2)──
		B("Warehouse", "倉庫", "Storage", { Metal = 15, Sand = 15 }, 0, { storage = 400, tier = 1 }),
		B("CargoSilo", "貨運筒倉", "Storage", { Titanium = 8, Scrap = 20 }, 0, { storage = 900, tier = 2 }),
		-- ── 攻擊(14)──
		B("CryoTurret", "冰凍砲台", "Attack", { Ice = 15, Water = 10 }, -3, { dps = 9, range = 50, slow = 0.06, tier = 1 }),
		B("PulseTurret", "脈衝砲台", "Attack", { Ore = 30, Metal = 10 }, -3, { dps = 12, range = 60, tier = 2 }),
		B("AcidSprayer", "酸液噴射器", "Attack", { Sulfur = 10, Water = 10 }, -3, { dps = 14, tier = 2 }),
		B("SparkCoil", "電弧線圈", "Attack", { Copper = 15, Coal = 5 }, -3, { dps = 15, tier = 2 }),
		B("FlakCannon", "防空砲", "Attack", { Metal = 20, Scrap = 15 }, -3, { dps = 16, tier = 2 }),
		B("FrostBeam", "冰霜光束", "Attack", { Ice = 25, Silicon = 10, Crystal = 4 }, -5, { dps = 20, slow = 0.05, tier = 3 }),
		B("LaserTower", "雷射塔", "Attack", { Silicon = 8, Copper = 8, Metal = 10 }, -4, { dps = 22, tier = 3 }),
		B("SonicEmitter", "音波砲", "Attack", { Silicon = 10, Glowstone = 3, Copper = 6 }, -5, { dps = 28, tier = 3 }),
		B("MagmaCannon", "熔岩砲", "Attack", { LavaCore = 10, Sulfur = 8, Metal = 10 }, -5, { dps = 30, range = 70, tier = 3 }),
		B("GravityWell", "重力陷阱", "Attack", { Glowstone = 6, Titanium = 6, Crystal = 4, Silicon = 6 }, -6, { dps = 6, slow = 0.12, control = true, tier = 4 }),
		B("Railgun", "磁軌砲", "Attack", { Titanium = 12, Copper = 15, Metal = 15, Silicon = 8 }, -7, { dps = 50, tier = 4 }),
		B("SolarLance", "太陽長矛", "Attack", { Crystal = 10, Amber = 10, Titanium = 8, Copper = 8 }, -8, { dps = 60, tier = 4 }),
		B("PlasmaCannon", "電漿砲", "Attack", { Plasma = 6, Titanium = 10, Copper = 10, Silicon = 8, Sulfur = 6 }, -9, { dps = 80, range = 90, tier = 5 }),
		B("VoidCannon", "虛空砲", "Attack", { DarkMatter = 4, Plasma = 4, Titanium = 15, Stardust = 4, Silicon = 10 }, -12, { dps = 140, tier = 5 }),
		-- ── 防禦:護盾(5)──
		B("IceBarrier", "冰壁護盾", "Defense", { Ice = 25, Water = 15 }, -3, { shield = 120, tier = 1 }),
		B("AmberShield", "琥珀護盾", "Defense", { Amber = 10, Silicon = 5 }, -4, { shield = 160, tier = 2 }),
		B("EnergyShield", "能量護盾", "Defense", { Silicon = 10, Crystal = 6, Metal = 10 }, -6, { shield = 200, tier = 3 }),
		B("PrismShield", "稜鏡護盾", "Defense", { Crystal = 8, Silicon = 8, Glowstone = 2, Copper = 6 }, -6, { shield = 320, tier = 4 }),
		B("VoidShield", "虛空護盾", "Defense", { DarkMatter = 3, Stardust = 5, Titanium = 8, Crystal = 6, Glowstone = 4 }, -10, { shield = 1200, tier = 5 }),
		-- ── 防禦:牆(10)──
		B("ScrapWall", "廢料牆", "Defense", { Scrap = 15 }, 0, { wallHp = 100, tier = 1 }),
		B("StoneWall", "岩石牆", "Defense", { Ore = 40 }, 0, { wallHp = 110, tier = 1 }),
		B("SandBarrier", "沙袋堡壘", "Defense", { Sand = 20, Water = 5 }, 0, { wallHp = 120, tier = 1 }),
		B("CoalBrickWall", "煤磚牆", "Defense", { Coal = 20, Sand = 20 }, 0, { wallHp = 130, tier = 2 }),
		B("AlloyWall", "合金牆", "Defense", { Ore = 25, Metal = 5 }, 0, { wallHp = 150, tier = 2 }),
		B("AmberWall", "琥珀牆", "Defense", { Amber = 10, Sand = 10, Scrap = 10 }, 0, { wallHp = 220, tier = 3 }),
		B("CrystalWall", "晶牆", "Defense", { Crystal = 8, Silicon = 6, Metal = 10 }, 0, { wallHp = 300, tier = 3 }),
		B("ObsidianWall", "黑曜石牆", "Defense", { LavaCore = 5, Sand = 20, Sulfur = 6 }, 0, { wallHp = 350, tier = 3 }),
		B("TitaniumWall", "鈦合金牆", "Defense", { Titanium = 10, Scrap = 10, Metal = 10, Copper = 6 }, 0, { wallHp = 400, tier = 4 }),
		B("StarArmor", "星塵裝甲", "Defense", { Stardust = 3, Titanium = 10, Silicon = 8, Crystal = 6, Amber = 6 }, 0, { wallHp = 900, tier = 5 }),
		-- ── 防禦:星核(2)──
		B("CoreReinforcer", "星核強化裝置", "Defense", { Metal = 25, Titanium = 8, Copper = 8 }, -2, { coreHp = 150, tier = 3 }),
		-- 指揮中心(基地):開局送一座(Logic/Starter),不能自己蓋(hidden)、不能拆(permanent)、不佔建造格數。
		-- 自帶電力 +6,讓開局送的砲台不用先蓋太陽能板就能運作;算防禦類 → 裂縫會往基地這群降落。
		B("CommandCenter", "指揮中心", "Defense", { Ore = 500, Metal = 100 }, 6, { coreHp = 100, tier = 1, hidden = true, permanent = true }),
		B("CoreBulwark", "星核堡壘", "Defense", { Titanium = 20, Amber = 10, Crystal = 6, Silicon = 8 }, -4, { coreHp = 400, tier = 4 }),
		-- ── 輔助 / 科技(2)──
		B("Radar", "雷達", "Support", { Copper = 10, Glowstone = 4, Silicon = 6 }, -2, { warningBonus = 30, tier = 3 }),
		B("WarpGate", "時空門", "Tech", { Ore = 40, Metal = 10 }, -2, { tier = 2 }),
	},
}

return Buildings
