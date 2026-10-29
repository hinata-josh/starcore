<!-- updated: 2026-10-29 -->
# L0 總覽(《星核守護者》)

計畫書:`../Roblox開發計畫書.md`。本檔是程式碼的導覽入口,新增 Service/建築時同步更新。

## 目錄
| 路徑 | 內容 | 可離線測試 |
|---|---|---|
| `src/shared/Logic/` | 純邏輯:CubeSphere(球面格位)、Rng、PlanetGen、WaveLogic、Energy、Migrate、Inventory(背包)、Build(建造/拆除/產出規則)、**Trip(穿梭:資源點/採集/載重結算)**、Gather(採集間隔/20 次冷卻)、HomePlanet(母星 5 種資源)、HomeNode(母星資源點)、MapView(中央螢幕 2D 地圖)、Combat/WaveLogic/Quest/Daily | ✅ `node test/run.js` |
| `src/shared/Data/` | 資料表:Planets / Monsters / Buildings / Items / **Warp**(各有 DataVersion) | ✅ 一致性測試 |
| `src/shared/Net/Remotes.luau` | 所有 RemoteEvent 名稱的單一註冊表 | ❌ 需 Studio |
| `src/server/` | PlanetDemo(M0 球體+格位標記)、**DataService(DataStore+session lock+自動存檔)**、PlanetService(星球主人/建造 remote/每秒產出)、WarpService(穿梭)、**WaveService(裂縫戰鬥)、HomeNodes(母星採集點,好友可採)、ScreenFeed(中央螢幕訊息)、QuestService** | ❌ |
| `src/client/` | SphereGravity(M0)、BuildUI(建造選單/資源列/點擊蓋拆)、TripUI(時空門/倒數/載重/採集冷卻)、HudExtras(裂縫倒數/任務/升級)、**CentralScreen(中央螢幕:2D 地圖 + 入侵/好友訊息)** | ❌ |

## 規則
1. **邏輯與 Roblox API 分離**:Logic/ 不得出現 `game`、`workspace`、`Vector3`(用 `{x,y,z}` 純表)。
2. 資料模組不得互相 require;需要資料的 Logic 函式用**參數傳入**(見 `PlanetGen.generate(seed, warp, planets)`)。
3. Logic 之間只用 `require(script.Parent.X)` 這一種寫法(測試腳本才能轉換)。
4. 改存檔欄位 → `Migrate.CURRENT + 1` + 新增遷移步驟 + 補測試。
5. 改資料表數值 → 該表 `DataVersion + 1`。
6. client 只送「意圖」,server 驗證後才改狀態。

## 驗證指令
```
node test/syntax.js   # 所有 .luau 能解析(含 Roblox 端)
node test/run.js      # 純邏輯測試(自寫 Luau 直譯器,K:\Html5\roblox-studio\luau.js)
```
直譯器是自寫的:型別標註會被略過、不做型別檢查;正式靜態檢查仍需 selene / luau-analyze。
