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

function Read-WatcherState {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    return $null
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
    # Status metadata is helpful but should never block diagnostics.
  }
}

function Get-UsefulTail {
  param(
    [string]$Path,
    [int]$Count = 6
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return @("No log file exists yet.")
  }

  $lines = @(Get-Content -LiteralPath $Path -Tail 60 -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Last $Count)

  if ($lines.Count -eq 0) {
    return @("No recent lines.")
  }

  return $lines
}

function Format-AppLogLine {
  param([string]$Line)

  if ([string]::IsNullOrWhiteSpace($Line) -or $Line -eq "No log file exists yet." -or $Line -eq "No recent lines.") {
    return $Line
  }

  try {
    $entry = $Line | ConvertFrom-Json
    if ($entry.error) {
      return "$($entry.timestamp) $($entry.source) error: $($entry.error)"
    }
    if ($entry.primary -or $entry.secondary) {
      return "$($entry.timestamp) quota read: primary $($entry.primary); secondary $($entry.secondary)"
    }
    if ($entry.mode) {
      return "$($entry.timestamp) $($entry.source) $($entry.mode)"
    }
    return "$($entry.timestamp) $($entry.source)"
  } catch {
    return $Line
  }
}

function Get-AppLogEntries {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  $entries = @()
  $lines = @(Get-Content -LiteralPath $Path -Tail 80 -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

  foreach ($line in $lines) {
    try {
      $entry = $line | ConvertFrom-Json
      $entry | Add-Member -NotePropertyName RawLine -NotePropertyValue $line -Force
      $entries += $entry
    } catch {
    }
  }

  return $entries
}

function Get-RecentAppErrors {
  param(
    [array]$Entries,
    [Nullable[datetime]]$SinceUtc
  )

  $errors = @()
  foreach ($entry in $Entries) {
    if (-not $entry.error) {
      continue
    }

    if ($SinceUtc -ne $null) {
      [datetime]$entryTime = [datetime]::MinValue
      if (-not [datetime]::TryParse([string]$entry.timestamp, [ref]$entryTime)) {
        continue
      }
      if ($entryTime.ToUniversalTime() -lt $SinceUtc.Value.ToUniversalTime()) {
        continue
      }
    }

    $errors += $entry
  }
  return $errors
}

function Write-Section {
  param([string]$Title)
  Write-Host ""
  Write-Host $Title
}

function Write-LogPreview {
  param(
    [string]$Label,
    [string]$Path
  )

  Write-Section $Label
  Write-Host $Path
  foreach ($line in (Get-UsefulTail -Path $Path -Count 5)) {
    Write-Host "  $line"
  }
}

try {
  $projectRoot = Find-ProjectRoot
  $watcherScript = Join-Path $projectRoot "src\watcher.js"
  $pidFile = Join-Path $projectRoot ".watcher.pid"
  $stateFile = Join-Path $projectRoot ".watcher-state.json"
  $logsDir = Join-Path $projectRoot "logs"
  $appLog = Join-Path $logsDir "codex-limit-watcher.log"
  $stdoutLog = Join-Path $logsDir "watcher-background.out.log"
  $stderrLog = Join-Path $logsDir "watcher-background.err.log"
  $configPath = Join-Path $projectRoot "config.json"
  $pidFileExists = Test-Path -LiteralPath $pidFile
  $pidValue = Read-PidFile -Path $pidFile
  $state = Read-WatcherState -Path $stateFile
  $appEntries = @(Get-AppLogEntries -Path $appLog)
  $latestAppLine = if ($appEntries.Count -gt 0) { Format-AppLogLine -Line $appEntries[-1].RawLine } else { "No app log line yet." }

  Write-Host "Codex Limit Watcher status"
  Write-Host "Project folder: $projectRoot"
  Write-Host "config.json exists: $((Test-Path -LiteralPath $configPath).ToString().ToLowerInvariant())"
  Write-Host "PID file exists: $($pidFileExists.ToString().ToLowerInvariant())"
  if ($pidFileExists) {
    Write-Host "Saved PID: $pidValue"
  }

  Write-Host "App log: $appLog"
  Write-Host "Background output log: $stdoutLog"
  Write-Host "Background error log: $stderrLog"

  $stateLabel = "Stopped"
  $processName = "n/a"
  $recentErrors = @()

  if ($pidFileExists -and $pidValue -lt 0) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-WatcherState -Path $stateFile -Status "stalePidCleaned" -PidValue 0 -Message "PID file existed but did not contain a valid process ID."
    $stateLabel = "PID file exists but watcher is not running"
    Write-Section "Status"
    Write-Host $stateLabel
    Write-Host "The PID file did not contain a valid process ID, so it was cleaned up."
  } elseif ($pidFileExists -and $pidValue) {
    $validation = Test-WatcherProcessByPid -PidValue $pidValue -ProjectRoot $projectRoot -WatcherScript $watcherScript
    $processName = if ($validation.ProcessName) { $validation.ProcessName } else { "n/a" }
    if ($validation.IsValid) {
      $startedUtc = $validation.Process.StartTime.ToUniversalTime()
      $recentErrors = @(Get-RecentAppErrors -Entries $appEntries -SinceUtc $startedUtc)
      $stateLabel = if ($recentErrors.Count -gt 0) { "Watcher running, but recent quota/app-server errors found in logs" } else { "Running normally" }
      Write-Section "Status"
      Write-Host $stateLabel
      Write-Host "PID is running: true"
      Write-Host "Process name: $processName"
      Write-Host "Started: $($validation.Process.StartTime)"
    } else {
      Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
      Write-WatcherState -Path $stateFile -Status "stalePidCleaned" -PidValue $pidValue -Message "PID file was stale or pointed to a different process."
      $stateLabel = if ($validation.Reason -eq "missing") { "PID file exists but watcher is not running" } else { "PID file exists but points to a different process" }
      Write-Section "Status"
      Write-Host $stateLabel
      Write-Host "PID is running: $(([bool]$validation.Process).ToString().ToLowerInvariant())"
      Write-Host "Process name: $processName"
      Write-Host "The unsafe PID file was cleaned up. No unrelated process was stopped."
    }
  } elseif ($state -and $state.status -eq "exitedImmediately") {
    $stateLabel = "Watcher started but exited immediately"
    Write-Section "Status"
    Write-Host $stateLabel
    Write-Host $state.message
  } else {
    Write-Section "Status"
    Write-Host $stateLabel
    Write-Host "PID is running: false"
  }

  if ($stateLabel -ne "Running normally" -and $appEntries.Count -gt 0) {
    $recentStoppedErrors = @(Get-RecentAppErrors -Entries $appEntries -SinceUtc $null)
    if ($recentStoppedErrors.Count -gt 0) {
      Write-Host "Recent quota/app-server errors were found in the app log."
      Write-Host "If background mode keeps failing, try Start Watcher.bat to see live errors."
    }
  }

  if ($stateLabel -eq "Watcher running, but recent quota/app-server errors found in logs") {
    Write-Host "The watcher process is running, but the app log has recent errors from this run."
  }

  Write-Host "Most recent app log line: $(Format-AppLogLine -Line $latestAppLine)"
  Write-LogPreview -Label "Recent background output" -Path $stdoutLog
  Write-LogPreview -Label "Recent background errors" -Path $stderrLog
  exit 0
} catch {
  Write-Host "Could not read Codex Limit Watcher status."
  Write-Host $_.Exception.Message
  exit 1
}
