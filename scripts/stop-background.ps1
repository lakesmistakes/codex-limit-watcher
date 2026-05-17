$ErrorActionPreference = "Stop"

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
      (Test-Path -LiteralPath (Join-Path $candidate "src\watcher.js"))
    ) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "Could not find the Codex Limit Watcher project folder. Run this from the project folder."
}

function Read-PidFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  $value = (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Select-Object -First 1)
  $pidValue = 0
  if ([int]::TryParse([string]$value, [ref]$pidValue)) {
    return $pidValue
  }
  return $null
}

function Test-WatcherProcess {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$WatcherScript
  )

  if (-not $Process) {
    return $false
  }

  $query = "ProcessId = $($Process.Id)"
  $cim = Get-CimInstance -ClassName Win32_Process -Filter $query -ErrorAction SilentlyContinue
  $commandLine = if ($cim) { [string]$cim.CommandLine } else { "" }

  return $commandLine.Contains($WatcherScript) -or
    $commandLine.Contains("src\watcher.js") -or
    $commandLine.Contains("src/watcher.js") -or
    $Process.ProcessName -like "node*"
}

function Stop-ChildProcesses {
  param([int]$ParentPid)

  $children = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $ParentPid" -ErrorAction SilentlyContinue
  foreach ($child in $children) {
    Stop-ChildProcesses -ParentPid ([int]$child.ProcessId)
    Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction SilentlyContinue
  }
}

try {
  $projectRoot = Find-ProjectRoot
  $watcherScript = Join-Path $projectRoot "src\watcher.js"
  $pidFile = Join-Path $projectRoot ".watcher.pid"

  $pidValue = Read-PidFile -Path $pidFile
  if (-not $pidValue) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Host "Codex Limit Watcher is not running in background mode."
    exit 0
  }

  $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
  if (-not $process) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Host "Codex Limit Watcher is not running. Cleaned up the old PID file."
    exit 0
  }

  if (-not (Test-WatcherProcess -Process $process -WatcherScript $watcherScript)) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Host "The saved PID does not look like Codex Limit Watcher anymore."
    Write-Host "Cleaned up the old PID file without stopping another program."
    exit 0
  }

  Write-Host "Stopping Codex Limit Watcher..."
  Write-Host "PID: $pidValue"
  Stop-ChildProcesses -ParentPid $pidValue
  Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue

  Start-Sleep -Seconds 1
  $stillRunning = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
  if ($stillRunning) {
    Write-Host "The watcher may still be stopping. Try Watcher Status.bat in a moment."
    exit 1
  }

  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  Write-Host "Codex Limit Watcher stopped."
  exit 0
} catch {
  Write-Host "Could not stop Codex Limit Watcher."
  Write-Host $_.Exception.Message
  exit 1
}
