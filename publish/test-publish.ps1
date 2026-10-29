# publish.ps1 的離線自動測試:假 Rojo + 本機假 Roblox API(HttpListener),不需要網路與真的金鑰。
# 驗證:建置步驟、上傳網址/標頭/檔案內容、成功與各種錯誤碼的處理、設定不完整時不會上傳。
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$publish = Join-Path $here 'publish.ps1'
$work = Join-Path $env:TEMP ('scg-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$pass = 0
$fail = 0
function Check([string]$name, $cond) {
	if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "  ✗ $name" -ForegroundColor Red }
}

# 假 rojo:rojo build <專案> -o <輸出> → 把輸出檔寫成固定內容(.cmd 版,Windows 可直接執行)
$fakeRojo = Join-Path $work 'fake-rojo.cmd'
Set-Content -Path $fakeRojo -Encoding ASCII -Value "@echo off`r`necho FAKE-RBXL-CONTENT> `"%~4`"`r`nexit /b 0"
$badRojo = Join-Path $work 'bad-rojo.cmd'
Set-Content -Path $badRojo -Encoding ASCII -Value "@echo off`r`necho boom 1>&2`r`nexit /b 1"

# 本機假 API:依序回應 $codes 裡的狀態碼;記錄收到的請求
$port = Get-Random -Minimum 20000 -Maximum 40000
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()

function Run-Publish([string[]]$extra, [int[]]$codes, [string]$rojoPath, [string]$rootOverride = '') {
	$useRoot = if ($rootOverride) { $rootOverride } else { $root }
	$log = Join-Path $work ([guid]::NewGuid().ToString('N') + '.log')
	$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$publish`"", '-ProjectRoot', "`"$useRoot`"",
		'-LogFile', "`"$log`"", '-SkipTests', '-SkipAssets', '-ApiBase', "http://127.0.0.1:$port", '-RojoPath', "`"$rojoPath`"") + $extra
	$p = Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden -PassThru
	$requests = @()
	foreach ($code in $codes) {
		$ar = $listener.BeginGetContext($null, $null)
		if (-not $ar.AsyncWaitHandle.WaitOne(15000)) { break }
		$ctx = $listener.EndGetContext($ar)
		$ms = New-Object IO.MemoryStream
		$ctx.Request.InputStream.CopyTo($ms)
		$requests += [pscustomobject]@{
			Url = $ctx.Request.Url.PathAndQuery; Method = $ctx.Request.HttpMethod
			Key = $ctx.Request.Headers['x-api-key']; Type = $ctx.Request.ContentType
			Body = [Text.Encoding]::ASCII.GetString($ms.ToArray()).Trim()
		}
		$ctx.Response.StatusCode = $code
		$bytes = [Text.Encoding]::UTF8.GetBytes($(if ($code -eq 200) { '{"versionNumber":42}' } else { '{"error":"x"}' }))
		$ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
		$ctx.Response.Close()
	}
	[void]$p.WaitForExit(60000)
	$text = ''
	if (Test-Path $log) { $text = [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8) }
	return [pscustomobject]@{ Log = $text; Requests = $requests; Exit = $p.ExitCode }
}

$good = @('-UniverseId', '1234567', '-PlaceId', '7654321', '-ApiKey', 'abcdefghijklmnopqrstuvwxyz0123456789')
try {
	Write-Host '▶ 成功發布'
	$r = Run-Publish ($good + @('-VersionType', 'Published')) @(200) $fakeRojo
	Check '結束碼 0' ($r.Exit -eq 0)
	Check '送出 1 次請求' ($r.Requests.Count -eq 1)
	if ($r.Requests.Count -ge 1) {
		$q = $r.Requests[0]
		Check '用 POST' ($q.Method -eq 'POST')
		Check '網址含 universe/place 與 Published' ($q.Url -eq '/universes/v1/1234567/places/7654321/versions?versionType=Published')
		Check '帶 x-api-key' ($q.Key -eq 'abcdefghijklmnopqrstuvwxyz0123456789')
		Check 'Content-Type 是 octet-stream' ($q.Type -eq 'application/octet-stream')
		Check '上傳的是建置出的檔案內容' ($q.Body -eq 'FAKE-RBXL-CONTENT')
	}
	Check '日誌顯示版本號 42' ($r.Log -match '版本號:42')
	Check '日誌沒有洩漏金鑰' ($r.Log -notmatch 'abcdefghijklmnopqrstuvwxyz')
	Check '日誌有結束標記' ($r.Log -match '##EXIT:0')

	Write-Host '▶ 從 publish.config.json 讀設定(命令列沒給任何 ID/金鑰)'
	$proj = Join-Path $work 'proj'
	New-Item -ItemType Directory -Path $proj | Out-Null
	Set-Content -Path (Join-Path $proj 'default.project.json') -Value '{}' -Encoding ASCII
	Set-Content -Path (Join-Path $proj 'publish.config.json') -Encoding UTF8 -Value '{"ApiKey":"cfgkey_abcdefghijklmnopqrstuvwxyz","UniverseId":"1111111","PlaceId":"2222222","VersionType":"Saved","RunTests":false}'
	$r = Run-Publish @() @(200) $fakeRojo $proj
	Check '設定檔:成功' ($r.Exit -eq 0 -and $r.Requests.Count -eq 1)
	if ($r.Requests.Count -ge 1) {
		Check '設定檔:網址用設定檔的 ID 與 Saved' ($r.Requests[0].Url -eq '/universes/v1/1111111/places/2222222/versions?versionType=Saved')
		Check '設定檔:金鑰來自設定檔' ($r.Requests[0].Key -eq 'cfgkey_abcdefghijklmnopqrstuvwxyz')
	}
	Check '設定檔:日誌有提示且不洩漏金鑰' ($r.Log -match '已讀取設定檔' -and $r.Log -notmatch 'cfgkey_abcdefghij')
	Write-Host '▶ 命令列參數優先於設定檔'
	$r = Run-Publish @('-UniverseId', '9999999') @(200) $fakeRojo $proj
	Check '命令列 Universe 蓋過設定檔' ($r.Requests.Count -eq 1 -and $r.Requests[0].Url -like '/universes/v1/9999999/places/2222222/*')
	Set-Content -Path (Join-Path $proj 'publish.config.json') -Value '{壞掉的json' -Encoding UTF8
	$r = Run-Publish @() @() $fakeRojo $proj
	Check '設定檔格式錯誤:不當機、提示並因設定不完整而停止' ($r.Exit -eq 1 -and $r.Log -match '格式錯誤' -and $r.Requests.Count -eq 0)

	Write-Host '▶ 只存檔(Saved)'

	$r = Run-Publish ($good + @('-VersionType', 'Saved')) @(200) $fakeRojo
	Check 'Saved 網址' ($r.Requests.Count -eq 1 -and $r.Requests[0].Url -like '*versionType=Saved')

	Write-Host '▶ 只建置不上傳'
	$r = Run-Publish @('-BuildOnly') @() $fakeRojo
	Check 'BuildOnly 結束碼 0' ($r.Exit -eq 0)
	Check 'BuildOnly 沒有任何請求' ($r.Requests.Count -eq 0)
	Check 'BuildOnly 產生 .rbxl' (Test-Path (Join-Path $root 'build\StarCoreGuardian.rbxl'))

	Write-Host '▶ 設定不完整 → 不上傳'
	$r = Run-Publish @('-UniverseId', 'abc', '-PlaceId', '7654321', '-ApiKey', 'short') @() $fakeRojo
	Check '結束碼 1' ($r.Exit -eq 1)
	Check '列出 Universe ID 問題' ($r.Log -match 'Universe ID')
	Check '列出 API 金鑰問題' ($r.Log -match 'API 金鑰')
	Check '沒有請求送出' ($r.Requests.Count -eq 0)

	Write-Host '▶ Rojo 建置失敗 → 不上傳'
	$r = Run-Publish $good @() $badRojo
	Check '結束碼 1' ($r.Exit -eq 1)
	Check '提示建置失敗' ($r.Log -match 'Rojo 建置失敗')
	Check '沒有請求送出' ($r.Requests.Count -eq 0)

	Write-Host '▶ 各種 HTTP 錯誤的提示'
	foreach ($case in @(@(401, 'API 金鑰錯誤'), @(403, 'Place Publishing'), @(404, 'Place ID 填錯'))) {
		$r = Run-Publish $good @($case[0]) $fakeRojo
		Check ("HTTP $($case[0]) 結束碼 1") ($r.Exit -eq 1)
		Check ("HTTP $($case[0]) 提示") ($r.Log -match $case[1])
	}

	Write-Host '▶ 伺服器忙碌(503)會自動重試,第二次成功'
	$r = Run-Publish $good @(503, 200) $fakeRojo
	Check '重試後成功' ($r.Exit -eq 0 -and $r.Requests.Count -eq 2)
	Check '日誌有重試訊息' ($r.Log -match '重試')
} finally {
	$listener.Stop()
	Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ("通過 $pass,失敗 $fail")
if ($fail -gt 0) { exit 1 } else { exit 0 }
