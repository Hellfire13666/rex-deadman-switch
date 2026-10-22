# Rex's Deadman Switch — Windows. Per-user scheduled task, no admin.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here "deadman.py"
if (-not (Test-Path $src)) { $src = Join-Path (Split-Path $here -Parent) "deadman.py" }
if (-not (Test-Path $src)) { throw "deadman.py is not next to this installer" }

$py = $null
foreach ($name in @("py", "python", "python3")) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) { throw "Install Python 3.10 or newer, then run this again." }

$destDir = Join-Path $env:LOCALAPPDATA "RexDeadman"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$script = Join-Path $destDir "deadman.py"
Copy-Item $src $script -Force

$cmdFile = Join-Path $destDir "deadman.cmd"
"@echo off`r`n`"$py`" `"$script`" %*`r`n" | Set-Content -Encoding ASCII $cmdFile

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
if ($userPath -notlike "*${destDir}*") {
  $joined = if ($userPath) { "$userPath;$destDir" } else { $destDir }
  [Environment]::SetEnvironmentVariable("Path", $joined, "User")
}

$service = New-Object -ComObject Schedule.Service
$service.Connect()
$folder = $service.GetFolder("\")
$task = $service.NewTask(0)
$task.RegistrationInfo.Description = "Rex's Deadman Switch"
$trigger = $task.Triggers.Create(2)
$trigger.StartBoundary = (Get-Date).Date.AddHours(8).ToString("yyyy-MM-ddTHH:mm:ss")
$trigger.DaysInterval = 1
$action = $task.Actions.Create(0)
$action.Path = $py
$action.Arguments = "`"$script`" run"
# 6 = create or update, 3 = interactive token (current user)
$folder.RegisterTaskDefinition("RexDeadman", $task, 6, $null, $null, 3) | Out-Null

$cfg = Join-Path $env:USERPROFILE ".config\deadman\config.json"
if (-not (Test-Path $cfg)) { & $py $script init }

Write-Host "Installed $script"
Write-Host "Daily task RexDeadman at 08:00."
Write-Host "Open a new terminal and run: deadman ping"
