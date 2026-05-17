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

try {
  $projectRoot = Find-ProjectRoot
  $watcherScript = Join-Path $projectRoot "src\watcher.js"
  $pidFile = Join-Path $projectRoot ".watcher.pid"
  $logsDir = Join-Path $projectRoot "logs"
  $appLog = Join-Path $logsDir "codex-limit-watcher.log"
  $stdoutLog = Join-Path $logsDir "watcher-background.out.log"
  $stderrLog = Join-Path $logsDir "watcher-background.err.log"
  $configPath = Join-Path $projectRoot "config.json"

  Write-Host "Codex Limit Watcher status"
  Write-Host "Project folder: $projectRoot"
  Write-Host "Logs folder: $logsDir"
  Write-Host "App log: $appLog"
  Write-Host "Background output log: $stdoutLog"
  Write-Host "Background error log: $stderrLog"
  Write-Host "config.json exists: $((Test-Path -LiteralPath $configPath).ToString().ToLowerInvariant())"

  $pidValue = Read-PidFile -Path $pidFile
  if (-not $pidValue) {
    Write-Host "Background watcher: not running"
    exit 0
  }

  $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
  if ($process -and (Test-WatcherProcess -Process $process -WatcherScript $watcherScript)) {
    Write-Host "Background watcher: running"
    Write-Host "PID: $pidValue"
    Write-Host "Started: $($process.StartTime)"
    exit 0
  }

  Write-Host "Background watcher: not running"
  Write-Host "A stale PID file exists and can be cleaned up by Stop Watcher.bat."
  exit 0
} catch {
  Write-Host "Could not read Codex Limit Watcher status."
  Write-Host $_.Exception.Message
  exit 1
}
