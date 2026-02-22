$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $projectRoot "local_saves"
$stateDir = Join-Path $projectRoot ".backup_state"
$stateFile = Join-Path $stateDir "last_source_utc.txt"
$maxBackups = 120

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$placeFile = Get-ChildItem -Path $projectRoot -File -Filter "*.rbxlx" |
    Where-Object { $_.Name -notlike "*.rojo.rbxlx" } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

if (-not $placeFile) {
    Write-Output "No non-Rojo .rbxlx place file found."
    exit 0
}

$currentStamp = $placeFile.LastWriteTimeUtc.ToString("o")
$previousStamp = $null
if (Test-Path -LiteralPath $stateFile) {
    $previousStamp = (Get-Content -LiteralPath $stateFile -Raw).Trim()
}

if ($previousStamp -eq $currentStamp) {
    Write-Output "No changes detected for '$($placeFile.Name)'."
    exit 0
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$destinationName = "{0}-{1}.rbxlx" -f [System.IO.Path]::GetFileNameWithoutExtension($placeFile.Name), $timestamp
$destinationPath = Join-Path $backupDir $destinationName

Copy-Item -LiteralPath $placeFile.FullName -Destination $destinationPath -Force
Set-Content -LiteralPath $stateFile -Value $currentStamp -NoNewline

$backups = Get-ChildItem -Path $backupDir -File -Filter "*.rbxlx" | Sort-Object LastWriteTimeUtc -Descending
if ($backups.Count -gt $maxBackups) {
    $toDelete = $backups | Select-Object -Skip $maxBackups
    $toDelete | Remove-Item -Force
}

Write-Output "Backup saved: $destinationPath"
