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
  return -1
}

function Test-WatcherProcessByPid {
  param(
    [int]$PidValue,
    [string]$ProjectRoot,
    [string]$WatcherScript
  )

  $process = Get-Process -Id $PidValue -ErrorAction SilentlyContinue
  if (-not $process) {
    return [pscustomobject]@{
      IsValid = $false
      Reason = "missing"
      Process = $null
      ProcessName = $null
      CommandLine = ""
    }
  }

  $query = "ProcessId = $PidValue"
  $cim = Get-CimInstance -ClassName Win32_Process -Filter $query -ErrorAction SilentlyContinue
  $commandLine = if ($cim) { [string]$cim.CommandLine } else { "" }
  $lowerCommandLine = $commandLine.ToLowerInvariant()
  $lowerProjectRoot = $ProjectRoot.ToLowerInvariant()
  $lowerWatcherScript = $WatcherScript.ToLowerInvariant()
  $processName = [string]$process.ProcessName

  $isNode = $processName -ieq "node" -or $processName -ieq "node.exe"
  $hasWatcherScript = $lowerCommandLine.Contains("src\watcher.js") -or
    $lowerCommandLine.Contains("src/watcher.js") -or
    $lowerCommandLine.Contains($lowerWatcherScript)
  $hasProjectRoot = $lowerCommandLine.Contains($lowerProjectRoot) -or
    $lowerCommandLine.Contains($lowerWatcherScript)

  return [pscustomobject]@{
    IsValid = $isNode -and $hasWatcherScript -and $hasProjectRoot
    Reason = if (-not $isNode) { "wrongProcessName" } elseif (-not $hasWatcherScript) { "missingWatcherScript" } elseif (-not $hasProjectRoot) { "missingProjectRoot" } else { "valid" }
    Process = $process
    ProcessName = $processName
    CommandLine = $commandLine
  }
}

function Stop-ChildProcesses {
  param([int]$ParentPid)

  $children = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $ParentPid" -ErrorAction SilentlyContinue
  foreach ($child in $children) {
    Stop-ChildProcesses -ParentPid ([int]$child.ProcessId)
    Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction SilentlyContinue
  }
}

function Write-WatcherState {
  param(
    [string]$Path,
    [string]$Status,
    [int]$PidValue,
    [string]$Message
  )

  $state = [ordered]@{
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    status = $Status
    pid = $PidValue
    message = $Message
  }

  try {
    $state | ConvertTo-Json | Set-Content -LiteralPath $Path
  } catch {
    # Status metadata is helpful but should never block start/stop operations.
  }
}

try {
  $projectRoot = Find-ProjectRoot
  $watcherScript = Join-Path $projectRoot "src\watcher.js"
  $pidFile = Join-Path $projectRoot ".watcher.pid"
  $stateFile = Join-Path $projectRoot ".watcher-state.json"

  $pidValue = Read-PidFile -Path $pidFile
  if (-not $pidValue) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-WatcherState -Path $stateFile -Status "stopped" -PidValue 0 -Message "No background watcher PID file was present."
    Write-Host "Codex Limit Watcher is not running in background mode."
    exit 0
  }

  if ($pidValue -lt 0) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-WatcherState -Path $stateFile -Status "stalePidCleaned" -PidValue 0 -Message "PID file existed but did not contain a valid process ID."
    Write-Host "Cleaned up stale background watcher state."
    Write-Host "The PID file did not contain a valid process ID."
    exit 0
  }

  $validation = Test-WatcherProcessByPid -PidValue $pidValue -ProjectRoot $projectRoot -WatcherScript $watcherScript
  if (-not $validation.IsValid) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-WatcherState -Path $stateFile -Status "stalePidCleaned" -PidValue $pidValue -Message "PID file was stale or pointed to a different process."
    if ($validation.Reason -eq "missing") {
      Write-Host "Codex Limit Watcher is not running. Cleaned up the old PID file."
    } else {
      Write-Host "The saved PID points to a different process, so it was not stopped."
      Write-Host "Cleaned up the unsafe PID file."
      Write-Host "Process name: $($validation.ProcessName)"
    }
    exit 0
  }

  Write-Host "Stopping Codex Limit Watcher..."
  Write-Host "PID: $pidValue"
  Stop-ChildProcesses -ParentPid $pidValue
  Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue

  Start-Sleep -Seconds 2
  $stillValid = Test-WatcherProcessByPid -PidValue $pidValue -ProjectRoot $projectRoot -WatcherScript $watcherScript
  if ($stillValid.IsValid) {
    Write-WatcherState -Path $stateFile -Status "stopFailed" -PidValue $pidValue -Message "Stop was requested, but the watcher still appears to be running."
    Write-Host "The watcher did not stop yet."
    Write-Host "Try Stop Watcher.bat again, or use Watcher Status.bat to check it."
    exit 1
  }

  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  Write-WatcherState -Path $stateFile -Status "stopped" -PidValue $pidValue -Message "Background watcher stopped."
  Write-Host "Codex Limit Watcher stopped."
  exit 0
} catch {
  Write-Host "Could not stop Codex Limit Watcher."
  Write-Host $_.Exception.Message
  exit 1
}
