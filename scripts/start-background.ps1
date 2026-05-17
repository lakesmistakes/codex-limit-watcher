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
  if (-not $command) {
    throw "Node.js was not found. Install Node.js from https://nodejs.org, then run Setup.bat."
  }
  return $command.Source
}

function Repair-ProcessPathEnvironment {
  $pathValue = [Environment]::GetEnvironmentVariable("Path", "Process")
  if (-not $pathValue) {
    $pathValue = [Environment]::GetEnvironmentVariable("PATH", "Process")
  }

  if ($pathValue) {
    [Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
    [Environment]::SetEnvironmentVariable("PATH", $null, "Process")
  }
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

function Get-WatcherProcessByPid {
  param(
    [int]$PidValue,
    [string]$WatcherScript
  )

  $process = Get-Process -Id $PidValue -ErrorAction SilentlyContinue
  if (-not $process) {
    return $null
  }

  $query = "ProcessId = $PidValue"
  $cim = Get-CimInstance -ClassName Win32_Process -Filter $query -ErrorAction SilentlyContinue
  $commandLine = if ($cim) { [string]$cim.CommandLine } else { "" }
  $looksLikeWatcher = $commandLine.Contains($WatcherScript) -or
    $commandLine.Contains("src\watcher.js") -or
    $commandLine.Contains("src/watcher.js")

  if ($looksLikeWatcher -or ($process.ProcessName -like "node*")) {
    return $process
  }

  return $null
}

try {
  $projectRoot = Find-ProjectRoot
  $watcherScript = Join-Path $projectRoot "src\watcher.js"
  $pidFile = Join-Path $projectRoot ".watcher.pid"
  $logsDir = Join-Path $projectRoot "logs"
  $stdoutLog = Join-Path $logsDir "watcher-background.out.log"
  $stderrLog = Join-Path $logsDir "watcher-background.err.log"

  New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

  $existingPid = Read-PidFile -Path $pidFile
  if ($existingPid) {
    $existingProcess = Get-WatcherProcessByPid -PidValue $existingPid -WatcherScript $watcherScript
    if ($existingProcess) {
      Write-Host "Codex Limit Watcher is already running in the background."
      Write-Host "PID: $existingPid"
      Write-Host "Logs: $logsDir"
      exit 0
    }

    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Host "Removed an old watcher PID file."
  }

  $node = Get-NodeCommand
  Write-Host "Starting Codex Limit Watcher in the background..."
  Write-Host "Project folder: $projectRoot"
  Write-Host "Logs: $logsDir"

  Repair-ProcessPathEnvironment

  $process = Start-Process `
    -FilePath $node `
    -ArgumentList @("`"$watcherScript`"") `
    -WorkingDirectory $projectRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -PassThru

  Start-Sleep -Seconds 5

  if ($process.HasExited) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Host "The watcher started, then stopped right away."
    Write-Host "Check these logs:"
    Write-Host "  $stdoutLog"
    Write-Host "  $stderrLog"
    exit 1
  }

  Set-Content -LiteralPath $pidFile -Value ([string]$process.Id) -NoNewline
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
