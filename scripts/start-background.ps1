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

function Get-NodeCommand {
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) {
    $command = Get-Command node -ErrorAction SilentlyContinue
  }

  if ($command) {
    return $command.Source
  }

  $fallbacks = @(
    (Join-Path $env:ProgramFiles "nodejs\node.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "nodejs\node.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\nodejs\node.exe")
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

  foreach ($candidate in $fallbacks) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "Node.js was not found. Install Node.js from https://nodejs.org, then run Setup.bat."
}

function Get-EffectivePath {
  $pathValues = @(
    [Environment]::GetEnvironmentVariable("Path", "Process"),
    [Environment]::GetEnvironmentVariable("PATH", "Process"),
    [Environment]::GetEnvironmentVariable("Path", "User"),
    [Environment]::GetEnvironmentVariable("Path", "Machine")
  )

  $segments = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($pathValue in $pathValues) {
    if ([string]::IsNullOrWhiteSpace($pathValue)) {
      continue
    }

    foreach ($segment in ($pathValue -split ';')) {
      $trimmed = $segment.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed)) {
        continue
      }

      if ($seen.Add($trimmed)) {
        [void]$segments.Add($trimmed)
      }
    }
  }

  return [string]::Join(';', $segments)
}

function Get-EffectiveHome {
  $homeValue = [Environment]::GetEnvironmentVariable("HOME", "Process")
  if (-not [string]::IsNullOrWhiteSpace($homeValue)) {
    return $homeValue
  }

  $userProfile = [Environment]::GetEnvironmentVariable("USERPROFILE", "Process")
  if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
    return $userProfile
  }

  return $null
}

function Get-BackgroundEnvironment {
  $effectivePath = Get-EffectivePath
  $effectiveHome = Get-EffectiveHome
  $userProfile = [Environment]::GetEnvironmentVariable("USERPROFILE", "Process")

  return [pscustomobject]@{
    Path = $effectivePath
    Home = $effectiveHome
    UserProfile = $userProfile
    PathPresent = -not [string]::IsNullOrWhiteSpace($effectivePath)
    PathLength = if ([string]::IsNullOrWhiteSpace($effectivePath)) { 0 } else { $effectivePath.Length }
    HomePresent = -not [string]::IsNullOrWhiteSpace($effectiveHome)
    UserProfilePresent = -not [string]::IsNullOrWhiteSpace($userProfile)
  }
}

function Set-ProcessPathValue {
  param([AllowNull()][string]$Value)

  # Windows treats environment keys case-insensitively, so remove PATH before
  # writing the canonical Path key that the child process will inherit.
  [Environment]::SetEnvironmentVariable("PATH", $null, "Process")

  if ([string]::IsNullOrWhiteSpace($Value)) {
    [Environment]::SetEnvironmentVariable("Path", "", "Process")
    return
  }

  [Environment]::SetEnvironmentVariable("Path", $Value, "Process")
}

function Start-HiddenWatcherProcess {
  param(
    [pscustomobject]$BackgroundEnvironment,
    [string]$WatcherScript,
    [string]$ProjectRoot,
    [string]$StdoutLog,
    [string]$StderrLog
  )

  Set-ProcessPathValue -Value $BackgroundEnvironment.Path
  if ([string]::IsNullOrWhiteSpace($BackgroundEnvironment.Home)) {
    Remove-Item Env:HOME -ErrorAction SilentlyContinue
  } else {
    $env:HOME = $BackgroundEnvironment.Home
  }

  $node = Get-NodeCommand

  return Start-Process `
    -FilePath $node `
    -ArgumentList @("`"$WatcherScript`"") `
    -WorkingDirectory $ProjectRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $StdoutLog `
    -RedirectStandardError $StderrLog `
    -PassThru
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

  if (-not $isNode) {
    return [pscustomobject]@{
      IsValid = $false
      Reason = "wrongProcessName"
      Process = $process
      ProcessName = $processName
      CommandLine = $commandLine
    }
  }

  if (-not $hasWatcherScript) {
    return [pscustomobject]@{
      IsValid = $false
      Reason = "missingWatcherScript"
      Process = $process
      ProcessName = $processName
      CommandLine = $commandLine
    }
  }

  if (-not $hasProjectRoot) {
    return [pscustomobject]@{
      IsValid = $false
      Reason = "missingProjectRoot"
      Process = $process
      ProcessName = $processName
      CommandLine = $commandLine
    }
  }

  return [pscustomobject]@{
    IsValid = $true
    Reason = "valid"
    Process = $process
    ProcessName = $processName
    CommandLine = $commandLine
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

function Show-RecentLogLines {
  param(
    [string]$Path,
    [string]$Label
  )

  Write-Host "${Label}: $Path"
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "  No log file exists yet."
    return
  }

  $lines = @(Get-Content -LiteralPath $Path -Tail 6 -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

  if ($lines.Count -eq 0) {
    Write-Host "  No recent lines."
    return
  }

  foreach ($line in $lines) {
    Write-Host "  $line"
  }
}

try {
  $projectRoot = Find-ProjectRoot
  $watcherScript = Join-Path $projectRoot "src\watcher.js"
  $pidFile = Join-Path $projectRoot ".watcher.pid"
  $stateFile = Join-Path $projectRoot ".watcher-state.json"
  $logsDir = Join-Path $projectRoot "logs"
  $stdoutLog = Join-Path $logsDir "watcher-background.out.log"
  $stderrLog = Join-Path $logsDir "watcher-background.err.log"

  New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

  $existingPid = Read-PidFile -Path $pidFile
  if ($existingPid) {
    if ($existingPid -lt 0) {
      Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
      Write-WatcherState -Path $stateFile -Status "stalePidCleaned" -PidValue 0 -Message "PID file existed but did not contain a valid process ID."
      Write-Host "Cleaned up an old watcher PID file that did not contain a valid process ID."
    } else {
      $existingValidation = Test-WatcherProcessByPid -PidValue $existingPid -ProjectRoot $projectRoot -WatcherScript $watcherScript
      if ($existingValidation.IsValid) {
        Write-Host "Codex Limit Watcher is already running in the background."
        Write-Host "PID: $existingPid"
        Write-Host "Process: $($existingValidation.ProcessName)"
        Write-Host "Logs: $logsDir"
        exit 0
      }

      Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
      Write-WatcherState -Path $stateFile -Status "stalePidCleaned" -PidValue $existingPid -Message "PID file was stale or pointed to a different process."
      Write-Host "Cleaned up stale background watcher state."
      if ($existingValidation.Reason -eq "missing") {
        Write-Host "The saved PID was not running anymore."
      } else {
        Write-Host "The saved PID pointed to a different process, so it was not touched."
      }
    }
  }

  Write-Host "Starting Codex Limit Watcher in the background..."
  Write-Host "Project folder: $projectRoot"
  Write-Host "Logs: $logsDir"
  $backgroundEnvironment = Get-BackgroundEnvironment
  Write-Host "Path present: $($backgroundEnvironment.PathPresent.ToString().ToLowerInvariant())"
  Write-Host "Path length: $($backgroundEnvironment.PathLength)"
  Write-Host "HOME present: $($backgroundEnvironment.HomePresent.ToString().ToLowerInvariant())"
  Write-Host "USERPROFILE present: $($backgroundEnvironment.UserProfilePresent.ToString().ToLowerInvariant())"
  Remove-Item -LiteralPath $stdoutLog -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stderrLog -Force -ErrorAction SilentlyContinue

  $process = Start-HiddenWatcherProcess `
    -BackgroundEnvironment $backgroundEnvironment `
    -WatcherScript $watcherScript `
    -ProjectRoot $projectRoot `
    -StdoutLog $stdoutLog `
    -StderrLog $stderrLog

  Set-Content -LiteralPath $pidFile -Value ([string]$process.Id) -NoNewline
  Write-WatcherState -Path $stateFile -Status "starting" -PidValue $process.Id -Message "Background watcher process was started and is being verified."

  Start-Sleep -Seconds 5

  $validation = Test-WatcherProcessByPid -PidValue $process.Id -ProjectRoot $projectRoot -WatcherScript $watcherScript
  if (-not $validation.IsValid) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-WatcherState -Path $stateFile -Status "exitedImmediately" -PidValue $process.Id -Message "Watcher started but exited during startup verification."
    Write-Host "The watcher started, then stopped right away."
    Write-Host "No unrelated process was stopped."
    Write-Host "Check these logs:"
    Show-RecentLogLines -Path $stdoutLog -Label "Background output log"
    Show-RecentLogLines -Path $stderrLog -Label "Background error log"
    exit 1
  }

  Write-WatcherState -Path $stateFile -Status "running" -PidValue $process.Id -Message "Background watcher passed startup verification."
  Write-Host "Codex Limit Watcher is now running in the background."
  Write-Host "PID: $($process.Id)"
  Write-Host "Use Watcher Status.bat to check it."
  Write-Host "Use Stop Watcher.bat to stop it."
  exit 0
} catch {
  Write-Host "Could not start Codex Limit Watcher in the background."
  Write-Host $_.Exception.Message
  exit 1
}
