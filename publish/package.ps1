# 打包專案成 zip(搬到外網機器用):排除 build、.git、node_modules、Packages、暫存檔。
param(
	[string]$ProjectRoot = '',
	[string]$OutDir = '',
	[string]$LogFile = ''
)
$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
	$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
function Log([string]$msg) {
	Write-Host $msg
	if ($LogFile) { [IO.File]::AppendAllText($LogFile, $msg + "`r`n", [Text.Encoding]::UTF8) }
}
try {
	if (-not $OutDir) { $OutDir = Split-Path -Parent $ProjectRoot }
	$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
	$zip = Join-Path $OutDir ("StarCoreGuardian-transfer-$stamp.zip")
	$tmp = Join-Path $env:TEMP ("scg-pack-" + [guid]::NewGuid().ToString('N'))
	Log "=== 打包專案 ==="
	Log "來源:$ProjectRoot"
	New-Item -ItemType Directory -Path $tmp | Out-Null
	$dest = Join-Path $tmp 'StarCoreGuardian'
	# robocopy:/E 含子資料夾、/XD 排除資料夾、/XF 排除檔案;結束碼 < 8 都算成功
	$null = & robocopy $ProjectRoot $dest /E /XD build .git node_modules Packages ServerPackages /XF *.rbxl *.rbxlx *.log publish.config.json /NFL /NDL /NJH /NJS /NP
	if ($LASTEXITCODE -ge 8) { throw "複製失敗(robocopy 結束碼 $LASTEXITCODE)" }
	Compress-Archive -Path $dest -DestinationPath $zip -Force
	Remove-Item $tmp -Recurse -Force
	$mb = [math]::Round((Get-Item $zip).Length / 1MB, 2)
	Log "✔ 已打包:$zip($mb MB)"
	Log "搬到外網機器後解壓縮,雙擊「一鍵發布Roblox.bat」即可。"
	Log "##EXIT:0"
	exit 0
} catch {
	Log ("✗ 打包失敗:" + $_.Exception.Message)
	Log "##EXIT:1"
	exit 1
}
