# 一鍵發布核心:自動測試 → Rojo 建置 .rbxl → Roblox Open Cloud 上傳發布
# 圖形介面(publish-gui.ps1)與命令列都用這支。API 金鑰優先從環境變數 SCG_API_KEY 讀(避免出現在行程清單)。
# 用法(命令列):
#   powershell -File publish.ps1 -UniverseId 123 -PlaceId 456 -ApiKey xxxx            # 建置並發布
#   powershell -File publish.ps1 -BuildOnly                                          # 只建置
#   powershell -File publish.ps1 -CheckOnly                                          # 只檢查環境
param(
	[string]$ProjectRoot = '',
	[string]$ApiKey = '',
	[string]$UniverseId = '',
	[string]$PlaceId = '',
	[string]$CreatorUserId = '',
	[switch]$SkipAssets,
	[ValidateSet('Published', 'Saved')][string]$VersionType = 'Published',
	[switch]$SkipTests,
	[switch]$BuildOnly,
	[switch]$CheckOnly,
	[string]$ApiBase = 'https://apis.roblox.com',
	[string]$RojoPath = '',
	[string]$LogFile = ''
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
	$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
if (-not $ApiKey) { $ApiKey = $env:SCG_API_KEY }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
# Node/Rojo 輸出的是 UTF-8;繁中 Windows 預設用 CP950 讀會變亂碼 → 一律切成 UTF-8(沒有主控台時忽略)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [Text.Encoding]::UTF8

function Log([string]$msg) {
	Write-Host $msg
	if ($LogFile) { [IO.File]::AppendAllText($LogFile, $msg + "`r`n", [Text.Encoding]::UTF8) }
}
function Finish([int]$code) {
	Log "##EXIT:$code"
	exit $code
}
function Fail([string]$msg) {
	Log ("✗ " + $msg)
	Finish 1
}

function Invoke-Native([scriptblock]$block) {
	$old = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	try { return (& $block 2>&1) } finally { $ErrorActionPreference = $old }
}

function Find-Exe([string[]]$names, [string[]]$extraDirs) {
	foreach ($d in $extraDirs) {
		foreach ($n in $names) {
			$p = Join-Path $d $n
			if (Test-Path $p) { return $p }
		}
	}
	foreach ($n in $names) {
		$c = Get-Command $n -ErrorAction SilentlyContinue
		if ($c) { return $c.Source }
	}
	return $null
}

try {
	Log "=== 星核守護者 一鍵發布 ==="
	# 設定檔 publish.config.json(專案根目錄):沒用命令列參數指定的項目,從這裡讀
	$cfgPath = Join-Path $ProjectRoot 'publish.config.json'
	if (Test-Path $cfgPath) {
		try {
			$pc = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
			if (-not $ApiKey -and $pc.ApiKey) { $ApiKey = [string]$pc.ApiKey }
			if (-not $UniverseId -and $pc.UniverseId) { $UniverseId = [string]$pc.UniverseId }
			if (-not $PlaceId -and $pc.PlaceId) { $PlaceId = [string]$pc.PlaceId }
			if (-not $CreatorUserId -and $pc.CreatorUserId) { $CreatorUserId = [string]$pc.CreatorUserId }
			if (-not $PSBoundParameters.ContainsKey('VersionType') -and $pc.VersionType -in @('Published', 'Saved')) { $VersionType = [string]$pc.VersionType }
			if (-not $PSBoundParameters.ContainsKey('SkipTests') -and $null -ne $pc.RunTests -and -not [bool]$pc.RunTests) { $SkipTests = [switch]$true }
			Log "已讀取設定檔:publish.config.json"
		} catch {
			Log ("! 設定檔 publish.config.json 讀取失敗(格式錯誤?):" + $_.Exception.Message)
		}
	}
	# 預設值 publish.defaults.json(不含金鑰、會打包):上面都沒給的欄位才用
	$defPath = Join-Path $ProjectRoot 'publish.defaults.json'
	if (Test-Path $defPath) {
		try {
			$dj = Get-Content $defPath -Raw -Encoding UTF8 | ConvertFrom-Json
			if (-not $UniverseId -and $dj.UniverseId) { $UniverseId = [string]$dj.UniverseId }
			if (-not $PlaceId -and $dj.PlaceId) { $PlaceId = [string]$dj.PlaceId }
			if (-not $CreatorUserId -and $dj.CreatorUserId) { $CreatorUserId = [string]$dj.CreatorUserId }
		} catch {
			Log ("! publish.defaults.json 讀取失敗:" + $_.Exception.Message)
		}
	}
	Log "專案資料夾:$ProjectRoot"
	if (-not (Test-Path (Join-Path $ProjectRoot 'default.project.json'))) {
		Fail "找不到 default.project.json,請確認專案資料夾"
	}

	# ── 1. 找 Rojo ──
	$userHome = [Environment]::GetFolderPath('UserProfile')
	$rojo = $null
	if ($RojoPath -and (Test-Path $RojoPath)) { $rojo = $RojoPath }
	if (-not $rojo) {
		$rojo = Find-Exe @('rojo.exe', 'rojo.cmd', 'rojo') @(
			(Join-Path $ProjectRoot 'tools'),
			(Join-Path $userHome '.rokit\bin'),
			(Join-Path $userHome '.aftman\bin'))
	}
	if (-not $rojo) {
		$rokit = Find-Exe @('rokit.exe') @((Join-Path $userHome '.rokit\bin'))
		if ($rokit) {
			Log "找不到 Rojo,嘗試用 Rokit 安裝(需要網路)…"
			Push-Location $ProjectRoot
			try { Invoke-Native { & $rokit install --no-trust-check } | ForEach-Object { Log ("  " + $_) } } catch { Log ("  Rokit 安裝失敗:" + $_.Exception.Message) }
			Pop-Location
			$rojo = Find-Exe @('rojo.exe') @((Join-Path $userHome '.rokit\bin'))
		}
	}
	if ($rojo) {
		Log "✔ Rojo:$rojo"
	} else {
		Fail "找不到 Rojo。請到 https://github.com/rojo-rbx/rojo/releases 下載 rojo.exe,放進專案的 tools 資料夾(或安裝 Rokit 後重試)"
	}

	# ── 2. 檢查發布設定 ──
	$needUpload = (-not $BuildOnly) -and (-not $CheckOnly)
	if (-not $BuildOnly) {
		$problems = @()
		if ($UniverseId -notmatch '^\d{3,}$') { $problems += "Universe ID 要是數字(Creator Hub 體驗的「Universe ID」)" }
		if ($PlaceId -notmatch '^\d{3,}$') { $problems += "Place ID 要是數字(起始地點的「Place ID」)" }
		if (-not $ApiKey -or $ApiKey.Length -lt 20) { $problems += "API 金鑰空白或太短(Creator Hub → Open Cloud → API 金鑰)" }
		if ($problems.Count -gt 0) {
			foreach ($p in $problems) { Log ("  ✗ " + $p) }
			if ($needUpload) { Fail "發布設定不完整" }
			Log "(只檢查環境:發布設定不完整,正式發布前請補齊)"
		} else {
			Log "✔ 發布設定格式正確(Universe $UniverseId / Place $PlaceId / $VersionType)"
		}
	}

	# ── 3. 自動測試 ──
	$node = Find-Exe @('node.exe', 'node') @()
	if ($SkipTests) {
		Log "略過自動測試(已勾選略過)"
	} elseif (-not $node) {
		Log "! 這台沒有 Node.js,略過自動測試(建議在有 Node.js 的機器先跑過 node test\run.js)"
	} else {
		Log "執行自動測試(快速版,約幾秒;完整平衡模擬請另外跑 node test
un.js)…"
		Push-Location $ProjectRoot
		$testOut = Invoke-Native { & $node 'test\syntax.js' }
		$code1 = $LASTEXITCODE
		$testOut | ForEach-Object { Log ("  " + $_) }
		$testOut = Invoke-Native { & $node 'test\run.js' '--fast' }
		$code2 = $LASTEXITCODE
		($testOut | Select-Object -Last 3) | ForEach-Object { Log ("  " + $_) }
		# 介面實跑(Roblox 模擬器執行 src/client,抓執行期錯誤)
		$testOut = Invoke-Native { & $node 'test\ui-check.js' }
		$code3 = $LASTEXITCODE
		($testOut | Where-Object { "$_" -match '✗' }) | ForEach-Object { Log ("  介面" + $_) }
		($testOut | Select-Object -Last 2) | ForEach-Object { Log ("  介面:" + $_) }
		# 怪獸來襲完整流程(全部伺服器腳本 + 模擬時鐘)
		$testOut = Invoke-Native { & $node 'test\wave-check.js' }
		$code4 = $LASTEXITCODE
		($testOut | Where-Object { "$_" -match '✗' }) | ForEach-Object { Log ("  來襲" + $_) }
		($testOut | Select-Object -Last 2) | ForEach-Object { Log ("  來襲:" + $_) }
		Pop-Location
		if ($code1 -ne 0 -or $code2 -ne 0 -or $code3 -ne 0 -or $code4 -ne 0) { Fail "自動測試沒有全過,已停止發布(修正後再試,或勾選略過測試)" }
		Log "✔ 自動測試全過"
	}
	if ($CheckOnly) {
		Log "✔ 環境檢查完成"
		Finish 0
	}

	# ── 3.5 介面圖片上傳(只傳新的/有變的;失敗不擋發布,介面會用備用樣式)──
	if ($needUpload -and -not $SkipAssets) {
		if ($CreatorUserId -match '^\d+$') {
			$assetPs1 = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'upload-assets.ps1'
			$env:SCG_API_KEY = $ApiKey
			$assetArgs = @{ ProjectRoot = $ProjectRoot; CreatorUserId = $CreatorUserId; ApiBase = $ApiBase; LogFile = $LogFile }
			& $assetPs1 @assetArgs | Out-Null
		} else {
			Log "! 略過介面圖片上傳:沒填 Creator User ID(介面先用備用樣式;填了之後下次發布會自動上傳)"
		}
	}

	# ── 4. 建置 .rbxl ──
	$outDir = Join-Path $ProjectRoot 'build'
	if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
	$outFile = Join-Path $outDir 'StarCoreGuardian.rbxl'
	if (Test-Path $outFile) { Remove-Item $outFile -Force }
	Log "Rojo 建置中…"
	Push-Location $ProjectRoot
	$buildOut = Invoke-Native { & $rojo build (Join-Path $ProjectRoot 'default.project.json') -o $outFile }
	$buildCode = $LASTEXITCODE
	Pop-Location
	$buildOut | ForEach-Object { Log ("  " + $_) }
	if ($buildCode -ne 0 -or -not (Test-Path $outFile) -or (Get-Item $outFile).Length -lt 1) {
		Fail "Rojo 建置失敗(看上面訊息;常見原因:Packages 資料夾不存在、專案檔路徑錯誤)"
	}
	$sizeKb = [math]::Round((Get-Item $outFile).Length / 1KB, 1)
	Log "✔ 已建置:$outFile($sizeKb KB)"
	if ($BuildOnly) { Finish 0 }

	# ── 5. 上傳發布(Open Cloud Place Publishing)──
	$url = "$ApiBase/universes/v1/$UniverseId/places/$PlaceId/versions?versionType=$VersionType"
	Log "上傳到 Roblox($VersionType)…"
	$attempt = 0
	$done = $false
	while (-not $done) {
		$attempt++
		try {
			$resp = Invoke-WebRequest -Uri $url -Method Post -Headers @{ 'x-api-key' = $ApiKey } `
				-ContentType 'application/octet-stream' -InFile $outFile -UseBasicParsing -TimeoutSec 300
			$ver = ''
			try {
				$c = $resp.Content
				if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
				$ver = ($c | ConvertFrom-Json).versionNumber
			} catch {}
			Log ("✔ 發布成功!版本號:" + $ver)
			$done = $true
		} catch {
			$status = 0
			$body = ''
			if ($_.Exception.Response) {
				try { $status = [int]$_.Exception.Response.StatusCode } catch {}
				try {
					$sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
					$body = $sr.ReadToEnd()
				} catch {}
			}
			$retryable = ($status -eq 429) -or ($status -ge 500)
			if ($retryable -and $attempt -lt 3) {
				Log ("  伺服器忙碌(HTTP $status),5 秒後重試($attempt/3)…")
				Start-Sleep -Seconds 5
				continue
			}
			$hint = switch ($status) {
				401 { "API 金鑰錯誤或已過期" }
				403 { "金鑰沒有這個體驗的「Place Publishing」寫入權限,或 IP 限制擋住了(到 Creator Hub 檢查金鑰的權限與 IP)" }
				404 { "找不到體驗或地點:Universe ID / Place ID 填錯,或這個地點不屬於這個體驗" }
				400 { "檔案格式被拒(請確認是 Rojo 建置出的 .rbxl)" }
				429 { "請求太頻繁,稍後再試" }
				0 { "連不上 Roblox(網路/代理/防火牆?):" + $_.Exception.Message }
				default { "未知錯誤" }
			}
			Log ("  HTTP $status — $hint")
			if ($body) { Log ("  伺服器回應:" + $body) }
			Fail "發布失敗"
		}
	}
	Log "完成。可到 Creator Hub 檢查版本;第一次發布請記得到「設定」填名稱、縮圖、年齡分級問卷,並先設為私人測試。"
	Finish 0
} catch {
	Log ("✗ 發生未預期錯誤:" + $_.Exception.Message)
	Finish 1
}
