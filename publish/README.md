# 一鍵發布到 Roblox

雙擊專案根目錄的 **`一鍵發布Roblox.bat`** 開啟圖形介面。流程:**自動測試 → Rojo 建置 .rbxl → Roblox Open Cloud 上傳發布**,全程不用開 Roblox Studio。

## 一、第一次要準備的事(外網機器上做一次)

| 要準備 | 怎麼做 |
|---|---|
| **Rojo** | 到 https://github.com/rojo-rbx/rojo/releases 下載 Windows 版 `rojo.exe`,放進專案的 `tools` 資料夾。(已安裝 Rokit 的話,工具會自動 `rokit install`) |
| **體驗 + Universe ID / Place ID** | https://create.roblox.com → 建立體驗。體驗網址 `.../experiences/{Universe ID}/...`;體驗 → 地點(Places)→ 起始地點 → 複製 **Place ID** |
| **API 金鑰** | Creator Hub → Open Cloud → API 金鑰 → 建立。權限選 **Place Publishing(universe-places)→ 寫入**,加入你的體驗。金鑰只顯示一次,等於密碼 |
| **Node.js**(選用) | 有裝就會在發布前自動跑 261 項測試,沒全過就不發布;沒裝會略過測試並提示 |

> 內網機打包搬到外網:介面上按 **「打包(搬到外網)」**,產生 `StarCoreGuardian-transfer-日期.zip`(已排除 build、.git、node_modules)。專案內附了測試用的 Luau 直譯器(`tools/luau.js`),搬過去不依賴任何內網路徑。

## 二、日常使用

1. 雙擊 `一鍵發布Roblox.bat`
2. 貼上 API 金鑰、Universe ID、Place ID(可勾「記住」,金鑰用 Windows 帳號加密存放,不會寫進專案)
3. 按 **① 檢查環境** → 都是 ✔ 後按 **③ 建置並發布 ★**
   - **Published**:正式發布,玩家馬上看到新版
   - **Saved**:只存檔不發布,可在 Studio 開啟檢查(第一次建議先用這個)
   - **② 只建置**:只產生 `build\StarCoreGuardian.rbxl`,可自己用 Studio 開啟

命令列版(排程/自動化):
```
powershell -File publish\publish.ps1 -UniverseId 123 -PlaceId 456 -ApiKey xxxx [-VersionType Saved] [-SkipTests] [-BuildOnly] [-CheckOnly]
```
金鑰也可放環境變數 `SCG_API_KEY`(避免出現在行程清單)。

## 二之一、介面圖片(N1 美術素材)

- 素材挑選與檔名對照在 `assets/ui/collect.js`(來源:`K:\N1Project\N1-Pro\Client\Assets\design\RawResources\sprite`);改了對照後跑 `node assets/ui/collect.js` 重新複製。
- 發布時填了 **創作者 User ID**(Roblox 個人頁網址 `/users/數字/profile` 的數字),且 API 金鑰有 **Assets → asset:read + asset:write** 權限,就會自動把 `assets/ui/*.png` 上傳,並產生 `src/shared/Data/UiAssets.luau`。只傳新的或改過的圖(紀錄在 `assets/ui/uploaded.json`)。
- 沒上傳、上傳失敗、或圖片還在 Roblox 審核中:介面自動用「備用樣式」(圓角色塊),不影響遊戲。
- 預覽上傳後的樣子(不用開 Roblox):`node test/ui-preview.js` → `build/ui-preview-*.png`。
- 上傳流程已用本機假伺服器測過(`publish\test-upload-assets.ps1`,31 項),**還沒對真的 Roblox 測過**。Decal 轉 Image ID 用的是 Asset Delivery API;轉不成功時會改用縮圖網址顯示圖示(按鈕/卡片會退回備用樣式)。

## 三、錯誤碼對照(介面會直接顯示中文提示)

| HTTP | 意思 |
|---|---|
| 401 | API 金鑰錯誤或過期 |
| 403 | 金鑰沒有這個體驗的 Place Publishing 寫入權限,或被 IP 限制擋住 |
| 404 | Universe ID / Place ID 填錯,或地點不屬於這個體驗 |
| 429 / 5xx | 伺服器忙碌,會自動重試 3 次 |

## 四、發布工具「做不到」的事(要在 Creator Hub 手動做)
- 體驗名稱、縮圖、描述、**年齡分級問卷**、付費項目、私人/公開、最大玩家數。**第一次發布後請先設為私人測試。**
- 把 `assets/models/*.obj` 匯入成 Roblox 模型(見 `assets/models/MANIFEST.md`):沒匯入時遊戲會用程式化造型,不影響運作。
- 球面重力、UI 手感等需要在 Studio 實測(見 `docs/studio-checklist.md`)。

## 五、驗證狀況(誠實說明)
- 發布流程已用**假 Rojo + 本機假 Roblox 伺服器**做自動測試(`publish\test-publish.ps1`,29 項):檢查上傳網址、標頭、檔案內容、成功/各種錯誤碼/重試、設定不完整時不上傳、金鑰不外洩。圖形介面也用自動化驗證過「按鈕 → 子行程 → 顯示結果」。
- **尚未對真正的 Roblox 伺服器測試**(這台是內網機,連不到)。上傳端點用的是 Open Cloud 的 Place Publishing API(`POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published|Saved`,標頭 `x-api-key`,內容為 .rbxl)。第一次請先用 **Saved** 試,若 Roblox 端點有變動,只需改 `publish\publish.ps1` 的 `$url` 那一行。
