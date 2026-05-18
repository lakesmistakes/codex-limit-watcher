$ErrorActionPreference = "Stop"

$taskName = "Codex Limit Watcher"
$taskPath = "\"

function Find-ProjectRoot {
  $candidates = @()

  if ($PSScriptRoot) {
    $candidates += (Split-Path -Parent $PSScriptRoot)
  }

  $current = (Get-Location).Path
  while ($current) {
    $candidates += $current
    $parent = Split-Path -Parent $current
    if (-not $parent -or $parent -eq $current) {
      break
    }
    $current = $parent
  }

  foreach ($candidate in ($candidates | Select-Object -Unique)) {
    if (
      (Test-Path -LiteralPath (Join-Path $candidate "package.json")) -and
      (Test-Path -LiteralPath (Join-Path $candidate "src\watcher.js")) -and
      (Test-Path -LiteralPath (Join-Path $candidate "scripts\start-background.ps1"))
    ) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "Could not find the Codex Limit Watcher project folder. Run Setup Autostart.bat from the project folder."
}

function Assert-ScheduledTaskSupport {
  $requiredCommands = @(
    "Get-ScheduledTask",
    "Register-ScheduledTask",
    "New-ScheduledTaskAction",
    "New-ScheduledTaskPrincipal",
    "New-ScheduledTaskTrigger"
  )

  foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
      throw "This Windows PowerShell session does not have the Task Scheduler cmdlets needed for autostart. Open the project in normal Windows PowerShell and try again."
    }
  }
}

try {
  $projectRoot = Find-ProjectRoot
  $startScript = Join-Path $projectRoot "scripts\start-background.ps1"
  $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

  Assert-ScheduledTaskSupport

  $actionArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`""
  $actionParameters = @{
    Execute = "powershell.exe"
    Argument = $actionArguments
  }

  $actionCommand = Get-Command -Name New-ScheduledTaskAction -ErrorAction Stop
  $workingDirectorySupported = $actionCommand.Parameters.ContainsKey("WorkingDirectory")
  if ($workingDirectorySupported) {
    $actionParameters.WorkingDirectory = $projectRoot
  }

  $action = New-ScheduledTaskAction @actionParameters
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
  $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
  $description = "Starts Codex Limit Watcher in background mode when you sign in."
  $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

  Register-ScheduledTask `
    -TaskName $taskName `
    -TaskPath $taskPath `
    -Action $action `
    -Trigger $trigger `
    -Description $description `
    -Principal $principal `
    -Force | Out-Null

  if ($existingTask) {
    Write-Host "Updated the Codex Limit Watcher autostart task."
  } else {
    Write-Host "Created the Codex Limit Watcher autostart task."
  }

  Write-Host "Task name: $taskName"
  Write-Host "Task path: $taskPath"
  Write-Host "Trigger: At logon for $currentUser"
  Write-Host "Action: powershell.exe $actionArguments"
  Write-Host "Project folder: $projectRoot"
  if ($workingDirectorySupported) {
    Write-Host "Working directory: $projectRoot"
  } else {
    Write-Host "Working directory: this Windows PowerShell version does not expose WorkingDirectory on New-ScheduledTaskAction."
  }
  Write-Host "How to test: Open Task Scheduler and run the task manually, or sign out and sign back in."
  Write-Host "How to remove: Double-click Remove Autostart.bat"
  exit 0
} catch {
  Write-Host "Could not set up Codex Limit Watcher autostart."
  Write-Host $_.Exception.Message
  exit 1
}
