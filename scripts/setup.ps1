$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "== $Message =="
}

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
      (Test-Path -LiteralPath (Join-Path $candidate "scripts\notify.ps1"))
    ) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  throw "Could not find the Codex Limit Watcher project folder. Run Setup.bat from the project folder."
}

function Get-NpmCommand {
  $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $command) {
    $command = Get-Command npm -ErrorAction SilentlyContinue
  }
  if (-not $command) {
    throw "npm was not found. Install Node.js from https://nodejs.org, then run Setup.bat again."
  }
  return $command.Source
}

try {
  Write-Host "Codex Limit Watcher beginner setup"
  Write-Host "This will prepare the folder, create config.json if needed, and test notifications."

  $projectRoot = Find-ProjectRoot
  Set-Location -LiteralPath $projectRoot
  Write-Host "Project folder: $projectRoot"

  Write-Step "Checking npm"
  $npm = Get-NpmCommand
  Write-Host "Found npm: $npm"

  if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "node_modules"))) {
    Write-Step "Installing Node packages"
    Write-Host "node_modules is missing, so setup will run npm install."
    & $npm install
    if ($LASTEXITCODE -ne 0) {
      throw "npm install failed. Check the messages above, then run Setup.bat again."
    }
  } else {
    Write-Step "Checking Node packages"
    Write-Host "node_modules already exists. Skipping npm install."
  }

  $configPath = Join-Path $projectRoot "config.json"
  $examplePath = Join-Path $projectRoot "config.example.json"
  Write-Step "Checking config"
  if (-not (Test-Path -LiteralPath $configPath)) {
    if (-not (Test-Path -LiteralPath $examplePath)) {
      throw "config.example.json is missing, so setup cannot create config.json."
    }
    Copy-Item -LiteralPath $examplePath -Destination $configPath
    Write-Host "Created config.json from config.example.json."
  } else {
    Write-Host "config.json already exists. Keeping your current settings."
  }

  Write-Step "Testing notifications"
  Write-Host "This may play the alert sound and show the billboard."
  & $npm run diagnose:notifications
  if ($LASTEXITCODE -ne 0) {
    throw "Notification diagnostics reported an issue. Read the messages above for details."
  }

  Write-Step "What to do next"
  Write-Host "1. Double-click Test Notification.bat"
  Write-Host "2. Double-click Start Watcher.bat"
  Write-Host "3. Optional future step: setup autostart"
  Write-Host ""
  Write-Host "Setup is complete."
  exit 0
} catch {
  Write-Host ""
  Write-Host "Setup could not finish."
  Write-Host $_.Exception.Message
  exit 1
}
