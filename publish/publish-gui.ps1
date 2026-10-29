# 一鍵發布 — 圖形介面。雙擊專案根目錄的「一鍵發布Roblox.bat」開啟。
# 做法:按鈕啟動子行程跑 publish.ps1 / package.ps1,子行程把訊息寫進 log 檔,這裡用 Timer 定時讀取顯示
# (不用 Register-ObjectEvent,避免高頻事件卡死畫面)。
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$publishPs1 = Join-Path $here 'publish.ps1'
$packagePs1 = Join-Path $here 'package.ps1'
$cfgDir = Join-Path $env:APPDATA 'StarCoreGuardian'
$cfgFile = Join-Path $cfgDir 'publish.json'
$keyFile = Join-Path $cfgDir 'apikey.dat'
if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir | Out-Null }

# ── 設定讀寫(金鑰用 Windows DPAPI 加密,只有這個使用者在這台電腦能解開)──
function Load-Config {
	$c = @{ UniverseId = ''; PlaceId = ''; CreatorUserId = ''; VersionType = 'Published'; RunTests = $true }
	if (Test-Path $cfgFile) {
		try {
			$j = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
			if ($j.UniverseId) { $c.UniverseId = [string]$j.UniverseId }
			if ($j.PlaceId) { $c.PlaceId = [string]$j.PlaceId }
			if ($j.CreatorUserId) { $c.CreatorUserId = [string]$j.CreatorUserId }
			if ($j.VersionType) { $c.VersionType = [string]$j.VersionType }
			if ($null -ne $j.RunTests) { $c.RunTests = [bool]$j.RunTests }
		} catch {}
	}
	return $c
}
function Load-Key {
	if (-not (Test-Path $keyFile)) { return '' }
	try {
		$sec = Get-Content $keyFile -Raw | ConvertTo-SecureString
		return (New-Object System.Management.Automation.PSCredential('x', $sec)).GetNetworkCredential().Password
	} catch { return '' }
}
function Save-All([string]$uid, [string]$pid2, [string]$ver, [bool]$tests, [string]$key, [bool]$rememberKey) {
	$o = @{ UniverseId = $uid; PlaceId = $pid2; CreatorUserId = $txtCreator.Text.Trim(); VersionType = $ver; RunTests = $tests }
	($o | ConvertTo-Json) | Set-Content -Path $cfgFile -Encoding UTF8
	if ($rememberKey -and $key) {
		(ConvertTo-SecureString $key -AsPlainText -Force | ConvertFrom-SecureString) | Set-Content -Path $keyFile
	} elseif (-not $rememberKey -and (Test-Path $keyFile)) {
		Remove-Item $keyFile -Force
	}
}
$cfg = Load-Config

# 專案根目錄的 publish.config.json(有的話優先於上次記住的設定),讓雙擊 bat 就不用再輸入
$projCfgPath = Join-Path $root 'publish.config.json'
$projKey = ''
$projCfgNote = ''
if (Test-Path $projCfgPath) {
	try {
		$pj = Get-Content $projCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
		if ($pj.UniverseId) { $cfg.UniverseId = [string]$pj.UniverseId }
		if ($pj.PlaceId) { $cfg.PlaceId = [string]$pj.PlaceId }
		if ($pj.CreatorUserId) { $cfg.CreatorUserId = [string]$pj.CreatorUserId }
		if ($pj.VersionType -in @('Published', 'Saved')) { $cfg.VersionType = [string]$pj.VersionType }
		if ($null -ne $pj.RunTests) { $cfg.RunTests = [bool]$pj.RunTests }
		if ($pj.ApiKey) { $projKey = [string]$pj.ApiKey }
		$projCfgNote = '已讀取 publish.config.json'
	} catch {
		$projCfgNote = '! publish.config.json 格式錯誤,已忽略'
	}
}

# 預設值 publish.defaults.json(不含金鑰、會跟著打包):還是空白的欄位才填
$defCfgPath = Join-Path $root 'publish.defaults.json'
if (Test-Path $defCfgPath) {
	try {
		$dj = Get-Content $defCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
		if (-not $cfg.UniverseId -and $dj.UniverseId) { $cfg.UniverseId = [string]$dj.UniverseId }
		if (-not $cfg.PlaceId -and $dj.PlaceId) { $cfg.PlaceId = [string]$dj.PlaceId }
		if (-not $cfg.CreatorUserId -and $dj.CreatorUserId) { $cfg.CreatorUserId = [string]$dj.CreatorUserId }
	} catch {}
}

# ── 介面 ──
$form = New-Object System.Windows.Forms.Form
$form.Text = '星核守護者 — 一鍵發布到 Roblox'
$form.Size = New-Object System.Drawing.Size(800, 726)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(720, 600)
$form.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)

function New-Label([string]$t, [int]$x, [int]$y, [int]$w, [int]$h) {
	$l = New-Object System.Windows.Forms.Label
	$l.Text = $t
	$l.Location = New-Object System.Drawing.Point($x, $y)
	$l.Size = New-Object System.Drawing.Size($w, $h)
	$form.Controls.Add($l)
	return $l
}
function New-Text([int]$x, [int]$y, [int]$w) {
	$t = New-Object System.Windows.Forms.TextBox
	$t.Location = New-Object System.Drawing.Point($x, $y)
	$t.Size = New-Object System.Drawing.Size($w, 26)
	$t.Anchor = 'Top,Left,Right'
	$form.Controls.Add($t)
	return $t
}

$null = New-Label 'API 金鑰' 16 18 110 24
$txtKey = New-Text 130 15 520
$txtKey.UseSystemPasswordChar = $true
if ($projKey) { $txtKey.Text = $projKey } else { $txtKey.Text = Load-Key }
$chkRemember = New-Object System.Windows.Forms.CheckBox
$chkRemember.Text = '記住(加密)'
$chkRemember.Location = New-Object System.Drawing.Point(660, 16)
$chkRemember.Size = New-Object System.Drawing.Size(110, 24)
$chkRemember.Anchor = 'Top,Right'
$chkRemember.Checked = (Test-Path $keyFile)
$form.Controls.Add($chkRemember)

$null = New-Label 'Universe ID' 16 54 110 24
$txtUni = New-Text 130 51 200
$txtUni.Text = $cfg.UniverseId
$null = New-Label 'Place ID' 350 54 70 24
$txtPlace = New-Text 424 51 226
$txtPlace.Text = $cfg.PlaceId

# 介面圖片(assets\ui)上傳到這個 Roblox 帳號名下;空白 = 不上傳,遊戲介面用備用樣式
$null = New-Label '創作者 User ID' 16 90 110 24
$txtCreator = New-Text 130 87 200
$txtCreator.Anchor = 'Top,Left'
$txtCreator.Text = $cfg.CreatorUserId
$null = New-Label '上傳介面圖片用(個人頁網址 /users/數字/profile 的數字)' 340 90 440 24

$null = New-Label '發布方式' 16 126 110 24
$cmbVer = New-Object System.Windows.Forms.ComboBox
$cmbVer.DropDownStyle = 'DropDownList'
$cmbVer.Location = New-Object System.Drawing.Point(130, 123)
$cmbVer.Size = New-Object System.Drawing.Size(330, 26)
[void]$cmbVer.Items.Add('Published — 正式發布(玩家馬上看到新版)')
[void]$cmbVer.Items.Add('Saved — 只存檔(不發布,可在 Studio 開啟檢查)')
if ($cfg.VersionType -eq 'Saved') { $cmbVer.SelectedIndex = 1 } else { $cmbVer.SelectedIndex = 0 }
$form.Controls.Add($cmbVer)

$chkTests = New-Object System.Windows.Forms.CheckBox
$chkTests.Text = '發布前先跑自動測試(建議;沒全過就不發布)'
$chkTests.Location = New-Object System.Drawing.Point(480, 124)
$chkTests.Size = New-Object System.Drawing.Size(290, 24)
$chkTests.Anchor = 'Top,Right'
$chkTests.Checked = $cfg.RunTests
$form.Controls.Add($chkTests)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = '① 檢查環境'
$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = '② 只建置 .rbxl'
$btnPublish = New-Object System.Windows.Forms.Button
$btnPublish.Text = '③ 建置並發布 ★'
$btnPublish.BackColor = [System.Drawing.Color]::FromArgb(40, 120, 220)
$btnPublish.ForeColor = [System.Drawing.Color]::White
$btnPack = New-Object System.Windows.Forms.Button
$btnPack.Text = '打包(搬到外網)'
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = '怎麼拿 ID 與金鑰?'
$x = 16
foreach ($b in @($btnCheck, $btnBuild, $btnPublish, $btnPack, $btnHelp)) {
	$b.Location = New-Object System.Drawing.Point($x, 162)
	$b.Size = New-Object System.Drawing.Size(145, 38)
	$b.FlatStyle = 'Flat'
	$form.Controls.Add($b)
	$x += 152
}
$btnPublish.Size = New-Object System.Drawing.Size(160, 38)
$btnPack.Location = New-Object System.Drawing.Point((16 + 152 * 2 + 168), 162)
$btnHelp.Location = New-Object System.Drawing.Point((16 + 152 * 3 + 168), 162)

$readyText = '準備就緒'
if ($projCfgNote) { $readyText = '準備就緒 — ' + $projCfgNote }
$lblStatus = New-Label $readyText 16 208 760 24
$lblStatus.Anchor = 'Top,Left,Right'

$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location = New-Object System.Drawing.Point(16, 236)
$rtb.Size = New-Object System.Drawing.Size(760, 440)
$rtb.Anchor = 'Top,Bottom,Left,Right'
$rtb.ReadOnly = $true
$rtb.BackColor = [System.Drawing.Color]::FromArgb(24, 28, 40)
$rtb.ForeColor = [System.Drawing.Color]::FromArgb(220, 228, 245)
$rtb.Font = New-Object System.Drawing.Font('Consolas', 10)
$form.Controls.Add($rtb)

# ── 執行子行程 + 定時讀 log ──
$script:proc = $null
$script:logPath = $null
$script:shown = 0
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400

function Set-Busy([bool]$busy) {
	foreach ($b in @($btnCheck, $btnBuild, $btnPublish, $btnPack)) { $b.Enabled = -not $busy }
}

function Start-Task([string]$file, [string[]]$extraArgs, [string]$title) {
	$rtb.Clear()
	$script:shown = 0
	$script:logPath = Join-Path $env:TEMP ("scg-" + [guid]::NewGuid().ToString('N') + '.log')
	[IO.File]::WriteAllText($script:logPath, '', [Text.Encoding]::UTF8)
	$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $file + '"'),
		'-ProjectRoot', ('"' + $root + '"'), '-LogFile', ('"' + $script:logPath + '"')) + $extraArgs
	$env:SCG_API_KEY = $txtKey.Text.Trim()
	$script:proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden -PassThru
	$env:SCG_API_KEY = $null
	$lblStatus.Text = $title + ' …執行中'
	Set-Busy $true
	$timer.Start()
}

$timer.Add_Tick({
	if (-not $script:logPath -or -not (Test-Path $script:logPath)) { return }
	$text = ''
	try {
		$fs = [IO.File]::Open($script:logPath, 'Open', 'Read', 'ReadWrite')
		$sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
		$text = $sr.ReadToEnd()
		$sr.Close()
		$fs.Close()
	} catch { return }
	if ($text.Length -gt $script:shown) {
		$new = $text.Substring($script:shown)
		$script:shown = $text.Length
		$rtb.AppendText($new.Replace("`r`n", "`n"))
		$rtb.SelectionStart = $rtb.TextLength
		$rtb.ScrollToCaret()
	}
	if ($script:proc -and $script:proc.HasExited -and $text -match '##EXIT:(\d+)') {
		$timer.Stop()
		Set-Busy $false
		if ($Matches[1] -eq '0') {
			$lblStatus.Text = '✔ 完成'
			$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(20, 140, 60)
		} else {
			$lblStatus.Text = '✗ 失敗(看下方訊息)'
			$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
		}
		$script:proc = $null
	} elseif ($script:proc -and $script:proc.HasExited -and $text -notmatch '##EXIT:') {
		$timer.Stop()
		Set-Busy $false
		$lblStatus.Text = '✗ 子程序異常結束'
		$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(200, 40, 40)
	}
})

function Common-Args {
	$ver = if ($cmbVer.SelectedIndex -eq 1) { 'Saved' } else { 'Published' }
	Save-All $txtUni.Text.Trim() $txtPlace.Text.Trim() $ver $chkTests.Checked $txtKey.Text.Trim() $chkRemember.Checked
	# Start-Process 不接受空字串參數(ID 還沒填時會當掉)→ 每個值都加引號,並去掉使用者誤輸入的引號
	$q = { param($v) '"' + ([string]$v -replace '"', '').Trim() + '"' }
	$a = @('-UniverseId', (& $q $txtUni.Text), '-PlaceId', (& $q $txtPlace.Text), '-CreatorUserId', (& $q $txtCreator.Text), '-VersionType', $ver)
	if (-not $chkTests.Checked) { $a += '-SkipTests' }
	return $a
}

$btnCheck.Add_Click({
	$lblStatus.ForeColor = [System.Drawing.Color]::Black
	Start-Task $publishPs1 ((Common-Args) + @('-CheckOnly')) '檢查環境'
})
$btnBuild.Add_Click({
	$lblStatus.ForeColor = [System.Drawing.Color]::Black
	Start-Task $publishPs1 ((Common-Args) + @('-BuildOnly')) '建置'
})
$btnPublish.Add_Click({
	$lblStatus.ForeColor = [System.Drawing.Color]::Black
	$ver = if ($cmbVer.SelectedIndex -eq 1) { '「只存檔」' } else { '「正式發布」' }
	$ans = [System.Windows.Forms.MessageBox]::Show("要把目前的專案以$ver上傳到 Roblox 嗎?", '確認發布', 'YesNo', 'Question')
	if ($ans -eq 'Yes') { Start-Task $publishPs1 (Common-Args) '發布' }
})
$btnPack.Add_Click({
	$lblStatus.ForeColor = [System.Drawing.Color]::Black
	Start-Task $packagePs1 @() '打包'
})
$btnHelp.Add_Click({
	$msg = @"
【Universe ID / Place ID】
1. 開啟 https://create.roblox.com → 建立體驗(或選你的體驗)
2. 體驗的網址 .../experiences/{Universe ID}/... 就是 Universe ID
3. 體驗 → 起始地點(Places)→ 點地點,網址中的數字或「複製 Place ID」就是 Place ID

【API 金鑰】
1. Creator Hub → Open Cloud → API 金鑰 → 建立
2. 權限選「Place Publishing(universe-places)」→ 寫入 → 加入你的體驗
3. 建立後複製金鑰貼到上面(只會顯示一次)。金鑰=密碼,不要貼給別人

【創作者 User ID + 介面圖片】
1. 打開你的 Roblox 個人頁,網址 roblox.com/users/{數字}/profile 的數字就是 User ID
2. API 金鑰再加一個權限:「Assets」→ asset:read + asset:write
3. 發布時會自動把 assets\ui 的圖片傳上去(只傳新的);圖片要等 Roblox 審核通過才看得到

【注意】
第一次發布完,請到 Creator Hub 設定:名稱、縮圖、年齡分級問卷,並先設為私人測試。
"@
	[void][System.Windows.Forms.MessageBox]::Show($msg, '怎麼拿 ID 與金鑰', 'OK', 'Information')
})

$form.Add_FormClosing({
	$ver = if ($cmbVer.SelectedIndex -eq 1) { 'Saved' } else { 'Published' }
	Save-All $txtUni.Text.Trim() $txtPlace.Text.Trim() $ver $chkTests.Checked $txtKey.Text.Trim() $chkRemember.Checked
	$timer.Stop()
})

# 測試掛勾(自動化驗證用):
#   SCG_GUI_TEST=1     → 載入完自動關閉
#   SCG_GUI_TEST=check → 自動按「檢查環境」,等結束後把 log 寫到 SCG_GUI_OUT 再關閉
if ($env:SCG_GUI_TEST -eq '1') {
	$t2 = New-Object System.Windows.Forms.Timer
	$t2.Interval = 1500
	$t2.Add_Tick({ $t2.Stop(); $form.Close() })
	$t2.Start()
} elseif ($env:SCG_GUI_TEST -eq 'check') {
	$chkTests.Checked = $false
	$t3 = New-Object System.Windows.Forms.Timer
	$t3.Interval = 700
	$t3.Add_Tick({ $t3.Stop(); $btnCheck.PerformClick() })
	$t3.Start()
	$t4 = New-Object System.Windows.Forms.Timer
	$t4.Interval = 500
	$t4.Add_Tick({
		if ($lblStatus.Text.StartsWith([string][char]0x2714) -or $lblStatus.Text.StartsWith([string][char]0x2717)) {
			$t4.Stop()
			if ($env:SCG_GUI_OUT) { [IO.File]::WriteAllText($env:SCG_GUI_OUT, $lblStatus.Text + "`
" + $rtb.Text, [Text.Encoding]::UTF8) }
			$form.Close()
		}
	})
	$t4.Start()
}

[void]$form.ShowDialog()
