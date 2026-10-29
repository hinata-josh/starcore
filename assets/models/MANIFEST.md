# 建築模型(SolidCraft MCP 建模 → OBJ)

| 檔案 | 對應建築 Id | 面數 | 說明 |
|---|---|---|---|
| `MinerRig.obj` | `Miner` | 60 | 底座 + 方塊機身 + 錐形鑽塔 + 頂蓋 |
| `SolarPanel.obj` | `SolarPanel` | 60 | 底座 + 支柱 + 兩層面板 |
| `PulseTurret.obj` | `PulseTurret` | 76 | 底座 + 錐形砲座 + 砲管 + 砲口 |
| `WarpGate.obj` | `WarpGate` | 88 | 底座 + 兩根門柱 + 橫樑 + 中央水晶台 |

其餘 46 種建築沒有匯入模型時,由 `src/server/BuildingModel.luau` 依「類別 + tier + 等級」用基本零件即時組出造型(越強越高大、Lv2 加角柱、Lv3 加信標)。
之後要替換任何建築,只要把匯入後的 Model 放進 `ReplicatedStorage.Assets.Buildings.<建築Id>`,程式會自動優先使用,不必改程式。

## 匯入 Roblox Studio 的步驟(要在有 Studio 的機器做)
1. Studio → Asset Manager → Bulk Import → 選 `assets/models/*.obj`(Mesh 匯入)。
2. 匯入後每個模型:**繞 X 軸旋轉 -90°**(SolidCraft 是 Z 軸向上,Roblox 是 Y 軸向上);縮放維持 1 mm = 1 stud(格位 12×12)。
3. 把 Pivot 設在「底座底面的正中心」(程式用這個點對準地表格位中心)。
4. 材質/顏色在 Studio 重上(OBJ 沒有顏色):建議用 Metal/Concrete + 類別色(能源綠、採集黃、攻擊紅、防禦藍、輔助紫、科技白)。
5. 放進 `ReplicatedStorage/Assets/Buildings/` 並以建築 Id 命名(例如 `Miner`、`SolarPanel`)。
6. 驗證:面數是否被 Studio 拒絕(這四個都很小);4 個建築蓋出來高度不超過約 15 studs。

## 用 SolidCraft MCP 再做新模型的心得
- `batch` 的參數叫 `commands`,每個指令寫成 `{"command": ..., "params": {...}}`(不是 `args`)。
- 往上疊高度:`sketch.create {plane:"XY", offset: <z>}` 再 `solid.extrude {operation:"join"}`;`taper` 負值 = 往上收窄(做錐形砲座/鑽塔)。
- **多用方塊與錐度,少用圓柱/圓孔**:圓形會被切成上千個面(一個簡單圓柱砲台 1560 面 / 125 KB),方塊模型只有 60~90 面。
- 同一張草圖畫兩個矩形可一次擠出兩根柱子(WarpGate 的門柱)。
- `export` 只能寫進 `...\Temp\solidcraft-mcp-<pid>-*` 資料夾,寫完再複製到本資料夾;格式只有 stl/obj/step/3mf/urdf。
- 建完一個模型記得 `new_design` 再做下一個,否則會疊在同一個設計裡。
