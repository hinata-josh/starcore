# 介面圖片上傳:assets/ui/*.png → Roblox Open Cloud(Assets API)→ 產生 src/shared/Data/UiAssets.luau
# 只上傳「新增或內容有變」的圖(以 SHA256 比對 assets/ui/uploaded.json),重跑不會重複上傳。
# 金鑰需要權限:Assets API → asset:read + asset:write(把圖上傳到 CreatorUserId 這個帳號名下)。
# 選用:Legacy Assets/Asset Delivery 讀取權限 → 能把 Decal ID 轉成 Image ID;沒有也能用(遊戲改用 rbxthumb 顯示)。
# 用法:powershell -File upload-assets.ps1 -ApiKey xxx -CreatorUserId 123 [-ApiBase http://127.0.0.1:port] [-LogFile log]
param(
	[string]$ProjectRoot = '',
	[string]$ApiKey = '',
	[string]$CreatorUserId = '',
	[string]$ApiBase = 'https://apis.roblox.com',
	[string]$LogFile = '',
	[int]$PollSeconds = 1
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
if (-not $ApiKey) { $ApiKey = $env:SCG_API_KEY }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
Add-Type -AssemblyName System.Net.Http

$SHOW_LOG = $true
function Log([string]$msg) {
	if (-not $SHOW_LOG) { return }
	Write-Host $msg
	if ($LogFile) { [IO.File]::AppendAllText($LogFile, $msg + "`r`n", [Text.Encoding]::UTF8) }
}

$uiDir = Join-Path $ProjectRoot 'assets\ui'
$cacheFile = Join-Path $uiDir 'uploaded.json'
$luauFile = Join-Path $ProjectRoot 'src\shared\Data\UiAssets.luau'

# ── 讀上傳紀錄 { key: { sha, id, kind } }(kind = image:可直接 rbxassetid / decal:要用 rbxthumb)──
$cache = @{}
if (Test-Path $cacheFile) {
	$j = Get-Content $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
	foreach ($p in $j.PSObject.Properties) { $cache[$p.Name] = @{ sha = [string]$p.Value.sha; id = [string]$p.Value.id; kind = [string]$p.Value.kind } }
}
function Save-Cache {
	$o = [ordered]@{}
	foreach ($k in ($cache.Keys | Sort-Object)) { $o[$k] = [ordered]@{ sha = $cache[$k].sha; id = $cache[$k].id; kind = $cache[$k].kind } }
	[IO.File]::WriteAllText($cacheFile, ($o | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding($false)))
}

# 產生 Luau 對照表(沒上傳成功的 key 不寫 → 遊戲端自動用備用樣式)
function Write-Luau {
	$lines = @(
		'--!strict',
		'-- 自動產生(publish/upload-assets.ps1),請勿手改。key = assets/ui 的檔名;沒有的 key 介面會用備用樣式。',
		'-- kind:image = 直接 rbxassetid;decal = 只拿到 Decal ID,用 rbxthumb 顯示(Skin.luau 處理)。',
		'return {'
	)
	foreach ($k in ($cache.Keys | Sort-Object)) {
		$c = $cache[$k]
		if ($c.id) { $lines += "`t$k = { id = $($c.id), kind = `"$($c.kind)`" }," }
	}
	$lines += '}'
	[IO.File]::WriteAllText($luauFile, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
}

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(60)
$client.DefaultRequestHeaders.Add('x-api-key', $ApiKey)

function Send-Upload([string]$key, [byte[]]$bytes) {
	$meta = @{
		assetType = 'Decal'; displayName = "SCG_$key"; description = 'StarCoreGuardian UI'
		creationContext = @{ creator = @{ userId = $CreatorUserId } }
	} | ConvertTo-Json -Depth 5 -Compress
	for ($try = 1; $try -le 4; $try++) {
		$form = New-Object System.Net.Http.MultipartFormDataContent
		$form.Add((New-Object System.Net.Http.StringContent($meta, [Text.Encoding]::UTF8, 'application/json')), 'request')
		$file = New-Object System.Net.Http.ByteArrayContent -ArgumentList (, $bytes)
		$file.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('image/png')
		$form.Add($file, 'fileContent', "$key.png")
		$resp = $client.PostAsync("$ApiBase/assets/v1/assets", $form).Result
		$body = $resp.Content.ReadAsStringAsync().Result
		$code = [int]$resp.StatusCode
		if ($code -eq 200) { return ($body | ConvertFrom-Json) }
		if ($code -eq 429 -or $code -ge 500) {
			Log "    伺服器忙碌($code),$([math]::Pow(2, $try)) 秒後重試…"
			Start-Sleep -Seconds ([math]::Pow(2, $try))
			continue
		}
		$hint = switch ($code) {
			401 { '金鑰錯誤或過期' }
			403 { '金鑰沒有 Assets API 的 asset:write 權限,或 CreatorUserId 不是金鑰擁有者' }
			400 { '圖片或參數被拒(格式/尺寸/名稱)' }
			default { '' }
		}
		throw "上傳 $key 失敗 HTTP $code $hint"
	}
	throw "上傳 $key 失敗:重試多次仍忙碌"
}

function Wait-Operation($op) {
	$opId = if ($op.operationId) { $op.operationId } else { ($op.path -split '/')[-1] }
	for ($i = 0; $i -lt 60; $i++) {
		if ($op.done -and $op.response) { return [string]$op.response.assetId }
		Start-Sleep -Seconds $PollSeconds
		$r = $client.GetAsync("$ApiBase/assets/v1/operations/$opId").Result
		if ([int]$r.StatusCode -eq 200) { $op = $r.Content.ReadAsStringAsync().Result | ConvertFrom-Json }
	}
	throw "等待上傳完成逾時(operation $opId)"
}

# Decal → Image ID:Decal 的內容是一段 XML,裡面 <url>…id=影像ID</url>。拿不到就回 $null。
function Resolve-ImageId([string]$decalId) {
	try {
		$r = $client.GetAsync("$ApiBase/asset-delivery-api/v1/assetId/$decalId").Result
		if ([int]$r.StatusCode -ne 200) { return $null }
		$loc = ($r.Content.ReadAsStringAsync().Result | ConvertFrom-Json).location
		if (-not $loc) { return $null }
		$xml = (New-Object System.Net.Http.HttpClient).GetStringAsync($loc).Result
		if ($xml -match '<url>[^<]*?id=(\d+)') { return $Matches[1] }
	} catch {}
	return $null
}

try {
	Log '── 介面圖片上傳 ──'
	if (-not (Test-Path $uiDir)) { throw "找不到 $uiDir" }
	$files = Get-ChildItem $uiDir -Filter *.png | Sort-Object Name
	$todo = @()
	foreach ($f in $files) {
		$key = $f.BaseName
		$sha = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
		if ($cache.ContainsKey($key) -and $cache[$key].sha -eq $sha -and $cache[$key].id) { continue }
		$todo += [pscustomobject]@{ Key = $key; Path = $f.FullName; Sha = $sha }
	}
	Log ("共 {0} 張,已上傳 {1} 張,這次要上傳 {2} 張" -f $files.Count, ($files.Count - $todo.Count), $todo.Count)
	if ($todo.Count -gt 0) {
		if (-not $ApiKey) { throw '沒有 API 金鑰' }
		if ($CreatorUserId -notmatch '^\d+$') { throw '沒有 Creator User ID(你的 Roblox 使用者 ID,個人頁網址 /users/數字/profile 的數字)' }
	}
	$n = 0
	foreach ($t in $todo) {
		$n++
		Log ("  [{0}/{1}] {2}" -f $n, $todo.Count, $t.Key)
		$op = Send-Upload $t.Key ([IO.File]::ReadAllBytes($t.Path))
		$decalId = Wait-Operation $op
		$imageId = Resolve-ImageId $decalId
		if ($imageId) {
			$cache[$t.Key] = @{ sha = $t.Sha; id = $imageId; kind = 'image' }
			Log "    ✓ Decal $decalId → Image $imageId"
		} else {
			$cache[$t.Key] = @{ sha = $t.Sha; id = $decalId; kind = 'decal' }
			Log "    ✓ Decal $decalId(查不到 Image ID,遊戲內改用縮圖顯示)"
		}
		Save-Cache # 每張存一次:中途失敗,已傳的不用重傳
	}
	Write-Luau
	Log "✓ 介面圖片就緒,已寫入 src/shared/Data/UiAssets.luau"
	Log '##ASSETS:0'
	exit 0
} catch {
	Write-Luau
	Log ('! 介面圖片上傳未完成:' + $_.Exception.Message)
	Log '  (不影響發布,沒上傳的圖會用備用樣式;圖片要等 Roblox 審核通過才會顯示)'
	Log '##ASSETS:1'
	exit 1
}
