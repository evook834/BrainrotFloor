$ErrorActionPreference = "Stop"

$taskName = "BrainrotFloorAutoBackup"
$scriptPath = Join-Path $PSScriptRoot "auto_backup_place.ps1"

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Backup script not found: $scriptPath"
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Output "Registered task '$taskName'. It runs every 5 minutes while you are logged in."
