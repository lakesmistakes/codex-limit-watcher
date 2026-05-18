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

  throw "Could not find the Codex Limit Watcher project folder. Run Remove Autostart.bat from the project folder."
}

function Assert-ScheduledTaskSupport {
  $requiredCommands = @(
    "Get-ScheduledTask",
    "Unregister-ScheduledTask"
  )

  foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
      throw "This Windows PowerShell session does not have the Task Scheduler cmdlets needed for autostart removal. Open the project in normal Windows PowerShell and try again."
    }
  }
}

try {
  $projectRoot = Find-ProjectRoot
  Assert-ScheduledTaskSupport

  $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
  if (-not $existingTask) {
    Write-Host "Codex Limit Watcher autostart is already removed."
    Write-Host "Task name: $taskName"
    Write-Host "Project folder: $projectRoot"
    exit 0
  }

  Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false

  Write-Host "Removed the Codex Limit Watcher autostart task."
  Write-Host "Task name: $taskName"
  Write-Host "Project folder: $projectRoot"
  Write-Host "To add it back later, double-click Setup Autostart.bat."
  exit 0
} catch {
  Write-Host "Could not remove Codex Limit Watcher autostart."
  Write-Host $_.Exception.Message
  exit 1
}
