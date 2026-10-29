# upload-assets.ps1 的離線自動測試:本機假 Roblox API(HttpListener),不需要網路與真的金鑰。
# 驗證:multipart 格式/標頭、等待 operation、Decal→Image 轉換、快取不重傳、改圖才重傳、查不到 Image ID 的退路、錯誤碼提示、金鑰不外洩。
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here 'upload-assets.ps1'
$work = Join-Path $env:TEMP ('scg-ua-' + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $work 'proj'
New-Item -ItemType Directory -Path (Join-Path $proj 'assets\ui') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $proj 'src\shared\Data') -Force | Out-Null
$pass = 0
$fail = 0
function Check([string]$name, $cond) {
	if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "  ✗ $name" -ForegroundColor Red }
}
# 最小的合法 PNG 檔頭 + 一點不同內容,讓 SHA 不同
function Fake-Png([string]$name, [string]$tag) {
	$bytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) + [Text.Encoding]::ASCII.GetBytes($tag)
	[IO.File]::WriteAllBytes((Join-Path $proj "assets\ui\$name.png"), $bytes)
}
Fake-Png 'btn_blue' 'AAA'
Fake-Png 'item_Ore' 'BBB'

$port = Get-Random -Minimum 20000 -Maximum 40000
$base = "http://127.0.0.1:$port"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("$base/")
$listener.Start()

# 跑一次上傳腳本,同時當假伺服器。$mode:ok / nodelivery / forbidden
function Run-Upload([string]$mode) {
	$log = Join-Path $work ([guid]::NewGuid().ToString('N') + '.log')
	$env:SCG_API_KEY = 'secretkey_abcdefghijklmnopqrstuvwxyz'
	$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", '-ProjectRoot', "`"$proj`"",
		'-CreatorUserId', '987654', '-ApiBase', $base, '-LogFile', "`"$log`"", '-PollSeconds', '0')
	$p = Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden -PassThru
	$env:SCG_API_KEY = $null
	$reqs = @()
	$nextId = 5550001
	$deadline = (Get-Date).AddSeconds(60)
	while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
		# 等待中的 BeginGetContext 跨回合沿用:上一回合沒等到請求就結束的話,不能丟著不管(會吃掉下一回合的第一個請求)
		if (-not $script:pending) { $script:pending = $listener.BeginGetContext($null, $null) }
		$ar = $script:pending
		while (-not $ar.AsyncWaitHandle.WaitOne(200)) {
			if ($p.HasExited) { break }
		}
		if (-not $ar.IsCompleted) { break }
		$script:pending = $null
		$ctx = $listener.EndGetContext($ar)
		$ms = New-Object IO.MemoryStream
		$ctx.Request.InputStream.CopyTo($ms)
		$path = $ctx.Request.Url.AbsolutePath
		$reqs += [pscustomobject]@{ Method = $ctx.Request.HttpMethod; Path = $path; Key = $ctx.Request.Headers['x-api-key']
			Type = $ctx.Request.ContentType; Body = [Text.Encoding]::UTF8.GetString($ms.ToArray()) }
		$code = 200
		$out = '{}'
		if ($ctx.Request.HttpMethod -eq 'POST' -and $path -eq '/assets/v1/assets') {
			if ($mode -eq 'forbidden') { $code = 403; $out = '{"message":"Forbidden"}' }
			else { $out = '{"path":"operations/op' + $nextId + '","operationId":"op' + $nextId + '","done":false}' }
		} elseif ($path -like '/assets/v1/operations/op*') {
			$id = $path.Substring($path.LastIndexOf('op') + 2)
			$out = '{"done":true,"response":{"assetId":"' + $id + '"}}'
		} elseif ($path -like '/asset-delivery-api/v1/assetId/*') {
			if ($mode -eq 'nodelivery') { $code = 403; $out = '{}' }
			else { $out = '{"location":"' + $base + '/deliver/' + ($path -split '/')[-1] + '"}' }
		} elseif ($path -like '/deliver/*') {
			$img = [int64](($path -split '/')[-1]) + 2220000
			$out = '<roblox><Item class="Decal"><Properties><Content name="Texture"><url>http://www.roblox.com/asset/?id=' + $img + '</url></Content></Properties></Item></roblox>'
		} else { $code = 404 }
		if ($path -like '/assets/v1/operations/*') { $nextId++ }
		$ctx.Response.StatusCode = $code
		$b = [Text.Encoding]::UTF8.GetBytes($out)
		$ctx.Response.OutputStream.Write($b, 0, $b.Length)
		$ctx.Response.Close()
	}
	[void]$p.WaitForExit(30000)
	$text = if (Test-Path $log) { [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8) } else { '' }
	$luau = Join-Path $proj 'src\shared\Data\UiAssets.luau'
	return [pscustomobject]@{ Exit = $p.ExitCode; Log = $text; Reqs = $reqs
		Uploads = @($reqs | Where-Object { $_.Method -eq 'POST' }); Luau = $(if (Test-Path $luau) { [IO.File]::ReadAllText($luau) } else { '' }) }
}

try {
	Write-Host '▶ 第一次上傳(2 張)'
	$r = Run-Upload 'ok'
	Check '結束碼 0' ($r.Exit -eq 0)
	Check '上傳 2 次' ($r.Uploads.Count -eq 2)
	if ($r.Uploads.Count -ge 1) {
		$u = $r.Uploads[0]
		Check '帶 x-api-key' ($u.Key -eq 'secretkey_abcdefghijklmnopqrstuvwxyz')
		Check 'multipart/form-data' ($u.Type -like 'multipart/form-data*')
		Check '有 request 欄位' ($u.Body -match 'name="?request"?')
		Check 'assetType 是 Decal' ($u.Body -match '"assetType":"Decal"')
		Check '帶創作者 userId' ($u.Body -match '"userId":"987654"')
		Check '有 fileContent 檔案欄位' ($u.Body -match 'name="?fileContent"?')
		Check '檔案是 image/png' ($u.Body -match 'Content-Type: image/png')
		Check '檔案內容有送出' ($u.Body -match 'PNG')
	}
	Check '有查詢 operation' (@($r.Reqs | Where-Object { $_.Path -like '/assets/v1/operations/*' }).Count -eq 2)
	Check 'Luau:btn_blue 轉成 Image ID' ($r.Luau -match 'btn_blue = \{ id = 7770001, kind = "image" \}')
	Check 'Luau:item_Ore 轉成 Image ID' ($r.Luau -match 'item_Ore = \{ id = 7770002, kind = "image" \}')
	Check 'Luau 開頭有 --!strict' ($r.Luau.StartsWith('--!strict'))
	Check '快取檔存在' (Test-Path (Join-Path $proj 'assets\ui\uploaded.json'))
	Check '日誌沒有洩漏金鑰' ($r.Log -notmatch 'secretkey_')
	Check '日誌有完成標記' ($r.Log -match '##ASSETS:0')

	Write-Host '▶ 再跑一次:沒變的圖不重傳'
	$r = Run-Upload 'ok'
	Check '結束碼 0' ($r.Exit -eq 0)
	Check '上傳 0 次' ($r.Uploads.Count -eq 0)
	Check 'Luau 內容保留' ($r.Luau -match 'btn_blue = \{ id = 7770001')
	Check '日誌顯示 0 張要上傳' ($r.Log -match '這次要上傳 0 張')

	Write-Host '▶ 改了一張圖 + 查不到 Image ID'
	Fake-Png 'btn_blue' 'CCC'
	$r = Run-Upload 'nodelivery'
	Check '結束碼 0' ($r.Exit -eq 0)
	Check '只重傳 1 張' ($r.Uploads.Count -eq 1)
	Check 'btn_blue 改存 Decal ID(kind=decal)' ($r.Luau -match 'btn_blue = \{ id = 5550001, kind = "decal" \}')
	Check 'item_Ore 不受影響' ($r.Luau -match 'item_Ore = \{ id = 7770002, kind = "image" \}')

	Write-Host '▶ 金鑰沒有 Assets 權限(403)'
	Fake-Png 'btn_red' 'DDD'
	$r = Run-Upload 'forbidden'
	Check '結束碼 1' ($r.Exit -eq 1)
	Check '日誌提示權限' ($r.Log -match 'asset:write')
	Check '日誌說明不影響發布' ($r.Log -match '不影響發布')
	Check '舊的對照仍寫回 Luau' ($r.Luau -match 'item_Ore = \{ id = 7770002')
	Check 'btn_red 沒寫進 Luau' ($r.Luau -notmatch 'btn_red')
	Check '日誌沒有洩漏金鑰' ($r.Log -notmatch 'secretkey_')
} finally {
	$listener.Stop()
	Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("通過 {0},失敗 {1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
