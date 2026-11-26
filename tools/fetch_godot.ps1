# ゲームの起動に使う Godot 4.5.1（Windows 64bit）を公式の配布物から取ってきて、「ユーザーフォルダ\Godot\4.5.1」に置く。
# 配布元は GitHub godotengine/godot のリリース。同じリリースの SHA512-SUMS.txt で照合する。
# 使い方（プロジェクト直下で）：powershell -ExecutionPolicy Bypass -File tools/fetch_godot.ps1
param([string]$Dest = "")

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$version = "4.5.1-stable"
$dir = if ($Dest -ne "") { $Dest } else { Join-Path $env:USERPROFILE "Godot\4.5.1" }
$zipName = "Godot_v$version`_win64.exe.zip"
$base = "https://github.com/godotengine/godot/releases/download/$version"
$exe = Join-Path $dir "Godot_v$version`_win64.exe"

if (Test-Path $exe) {
    Write-Host "もう入っている：$exe"
    exit 0
}

New-Item -ItemType Directory -Force $dir | Out-Null
$zip = Join-Path $dir $zipName
$sums = Join-Path $dir "SHA512-SUMS.txt"

Write-Host "取得中：$zipName"
Invoke-WebRequest "$base/$zipName" -OutFile $zip
Invoke-WebRequest "$base/SHA512-SUMS.txt" -OutFile $sums

$line = Get-Content $sums | Where-Object { $_ -match [regex]::Escape($zipName) + '$' } | Select-Object -First 1
if (-not $line) { throw "SHA512-SUMS.txt に $zipName がない" }
$expected = ($line -split '\s+')[0].ToLower()
$actual = (Get-FileHash $zip -Algorithm SHA512).Hash.ToLower()
if ($actual -ne $expected) {
    Remove-Item $zip
    throw "SHA512 が一致しない：$zipName（期待 $expected / 実際 $actual）"
}

Expand-Archive $zip -DestinationPath $dir -Force
Remove-Item $zip, $sums
Write-Host "置いた：$dir"
Get-ChildItem $dir -Filter "*.exe" | ForEach-Object { Write-Host "  $($_.Name)" }
