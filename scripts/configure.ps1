$ErrorActionPreference = "Stop"

$AllowedPositions = @("bottomRight", "bottomLeft", "topRight", "topLeft", "center")
$DefaultWidth = 400
$DefaultHeight = 300
$RecommendedWidth = 400
$RecommendedHeight = 300
$MinimumWidth = 200
$MaximumWidth = 800
$MinimumHeight = 150
$MaximumHeight = 600

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

  throw "Could not find the Codex Limit Watcher project folder. Run Configure Watcher.bat from the project folder."
}

function Get-NpmCommand {
  $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $command) {
    $command = Get-Command npm -ErrorAction SilentlyContinue
  }
  if (-not $command) {
    throw "npm was not found. Install Node.js from https://nodejs.org, then run Setup.bat."
  }
  return $command.Source
}

function Get-JsonObject {
  param(
    [string]$Path,
    [string]$Label
  )

  try {
    $raw = Get-Content -LiteralPath $Path -Raw
  } catch {
    throw "Could not read $Label at $Path."
  }

  try {
    return $raw | ConvertFrom-Json
  } catch {
    throw "$Label is not valid JSON. Fix it before using Configure Watcher.bat."
  }
}

function Ensure-ConfigFile {
  param(
    [string]$ConfigPath,
    [string]$ExamplePath
  )

  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    if (-not (Test-Path -LiteralPath $ExamplePath)) {
      throw "config.example.json is missing, so the menu cannot create config.json."
    }

    Copy-Item -LiteralPath $ExamplePath -Destination $ConfigPath
    Write-Host "Created config.json from config.example.json."
  }

  $null = Get-JsonObject -Path $ConfigPath -Label "config.json"
}

function Get-BackupDirectory {
  param([string]$ProjectRoot)

  return (Join-Path (Join-Path $ProjectRoot "logs") "config-backups")
}

function Ensure-BackupDirectory {
  param([string]$ProjectRoot)

  $backupDir = Get-BackupDirectory -ProjectRoot $ProjectRoot
  if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  }
  return $backupDir
}

function Backup-ConfigFile {
  param(
    [string]$ProjectRoot,
    [string]$ConfigPath
  )

  $backupDir = Ensure-BackupDirectory -ProjectRoot $ProjectRoot
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
  $backupPath = Join-Path $backupDir "config-$timestamp.json"
  Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
  return $backupPath
}

function Write-ConfigFile {
  param(
    [string]$ConfigPath,
    [object]$ConfigObject
  )

  $tempPath = Join-Path (Split-Path -Parent $ConfigPath) ("config.write-" + [guid]::NewGuid().ToString("N") + ".tmp")

  try {
    $json = $ConfigObject | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $tempPath -Value $json -Encoding UTF8
    $null = Get-JsonObject -Path $tempPath -Label "the updated config"
    Copy-Item -LiteralPath $tempPath -Destination $ConfigPath -Force
    $null = Get-JsonObject -Path $ConfigPath -Label "the saved config"
  } finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  }
}

function Save-ConfigChange {
  param(
    [string]$ProjectRoot,
    [string]$ConfigPath,
    [object]$ConfigObject,
    [string]$SuccessMessage
  )

  $backupPath = Backup-ConfigFile -ProjectRoot $ProjectRoot -ConfigPath $ConfigPath
  Write-ConfigFile -ConfigPath $ConfigPath -ConfigObject $ConfigObject
  Write-Host $SuccessMessage
  Write-Host "Backup created: $backupPath"
}

function Get-ConfigSection {
  param(
    [object]$Config,
    [string]$SectionName,
    [switch]$Create
  )

  $property = $Config.PSObject.Properties[$SectionName]
  if (-not $property) {
    if (-not $Create) {
      return $null
    }

    $section = [pscustomobject]@{}
    $Config | Add-Member -NotePropertyName $SectionName -NotePropertyValue $section
    return $section
  }

  if ($null -eq $property.Value) {
    if (-not $Create) {
      return $null
    }

    $property.Value = [pscustomobject]@{}
    return $property.Value
  }

  if ($property.Value -isnot [pscustomobject]) {
    throw "The $SectionName section in config.json is not shaped like an object. Fix it before using this menu."
  }

  return $property.Value
}

function Get-ConfigValue {
  param(
    [object]$Config,
    [string]$SectionName,
    [string]$PropertyName,
    $DefaultValue
  )

  $section = Get-ConfigSection -Config $Config -SectionName $SectionName
  if ($null -eq $section) {
    return $DefaultValue
  }

  $property = $section.PSObject.Properties[$PropertyName]
  if (-not $property -or $null -eq $property.Value) {
    return $DefaultValue
  }

  return $property.Value
}

function Set-ConfigValue {
  param(
    [object]$Config,
    [string]$SectionName,
    [string]$PropertyName,
    $Value
  )

  $section = Get-ConfigSection -Config $Config -SectionName $SectionName -Create
  $property = $section.PSObject.Properties[$PropertyName]
  if ($property) {
    $property.Value = $Value
  } else {
    $section | Add-Member -NotePropertyName $PropertyName -NotePropertyValue $Value
  }
}

function Convert-ToBooleanOrDefault {
  param(
    $Value,
    [bool]$DefaultValue
  )

  if ($null -eq $Value) {
    return $DefaultValue
  }

  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $parsed = $false
  if ([bool]::TryParse(([string]$Value), [ref]$parsed)) {
    return $parsed
  }

  return $DefaultValue
}

function Convert-ToIntegerOrDefault {
  param(
    $Value,
    [int]$DefaultValue
  )

  if ($null -eq $Value) {
    return $DefaultValue
  }

  $parsed = 0
  if ([int]::TryParse(([string]$Value), [ref]$parsed)) {
    return $parsed
  }

  return $DefaultValue
}

function Get-BooleanSetting {
  param(
    [object]$Config,
    [string]$SectionName,
    [string]$PropertyName,
    [bool]$DefaultValue
  )

  $value = Get-ConfigValue -Config $Config -SectionName $SectionName -PropertyName $PropertyName -DefaultValue $DefaultValue
  return (Convert-ToBooleanOrDefault -Value $value -DefaultValue $DefaultValue)
}

function Get-IntegerSetting {
  param(
    [object]$Config,
    [string]$SectionName,
    [string]$PropertyName,
    [int]$DefaultValue
  )

  $value = Get-ConfigValue -Config $Config -SectionName $SectionName -PropertyName $PropertyName -DefaultValue $DefaultValue
  return (Convert-ToIntegerOrDefault -Value $value -DefaultValue $DefaultValue)
}

function Get-StringSetting {
  param(
    [object]$Config,
    [string]$SectionName,
    [string]$PropertyName,
    [string]$DefaultValue
  )

  $value = Get-ConfigValue -Config $Config -SectionName $SectionName -PropertyName $PropertyName -DefaultValue $DefaultValue
  if ($value -is [string] -and $value.Trim()) {
    return $value.Trim()
  }

  return $DefaultValue
}

function Get-ResolvedAssetPath {
  param(
    [string]$ProjectRoot,
    [string]$ConfiguredPath
  )

  if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) {
    return $ConfiguredPath
  }

  return (Join-Path $ProjectRoot $ConfiguredPath)
}

function Get-AssetStatusLabel {
  param(
    [string]$ProjectRoot,
    [string]$ConfiguredPath
  )

  if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) {
    return "not set"
  }

  $resolvedPath = Get-ResolvedAssetPath -ProjectRoot $ProjectRoot -ConfiguredPath $ConfiguredPath
  if ($resolvedPath -and (Test-Path -LiteralPath $resolvedPath)) {
    return "found"
  }

  return "missing right now"
}

function Format-OnOff {
  param([bool]$Value)

  if ($Value) {
    return "On"
  }

  return "Off"
}

function Show-CurrentSettings {
  param(
    [object]$Config,
    [string]$ProjectRoot,
    [string]$ConfigPath
  )

  $toastEnabled = Get-BooleanSetting -Config $Config -SectionName "notifications" -PropertyName "toastEnabled" -DefaultValue $true
  $soundEnabled = Get-BooleanSetting -Config $Config -SectionName "notifications" -PropertyName "soundEnabled" -DefaultValue $true
  $billboardEnabled = Get-BooleanSetting -Config $Config -SectionName "notifications" -PropertyName "billboardEnabled" -DefaultValue $true
  $soundFile = Get-StringSetting -Config $Config -SectionName "notifications" -PropertyName "soundFile" -DefaultValue "assets/sounds/gem-alarm.wav"
  $billboardImage = Get-StringSetting -Config $Config -SectionName "notifications" -PropertyName "billboardImage" -DefaultValue "assets/billboards/usage-reset-lock-in.png"
  $maxWidth = Get-IntegerSetting -Config $Config -SectionName "billboard" -PropertyName "maxWidth" -DefaultValue $DefaultWidth
  $maxHeight = Get-IntegerSetting -Config $Config -SectionName "billboard" -PropertyName "maxHeight" -DefaultValue $DefaultHeight
  $position = Get-StringSetting -Config $Config -SectionName "billboard" -PropertyName "position" -DefaultValue "bottomRight"

  Write-Host ""
  Write-Host "Codex Limit Watcher beginner configuration menu"
  Write-Host "Config file: $ConfigPath"
  Write-Host "Backups folder: $(Get-BackupDirectory -ProjectRoot $ProjectRoot)"
  Write-Host ""
  Write-Host "Current settings"
  Write-Host "- Toast pop-up: $(Format-OnOff -Value $toastEnabled)"
  Write-Host "- Sound alert: $(Format-OnOff -Value $soundEnabled)"
  Write-Host "- Billboard pop-up: $(Format-OnOff -Value $billboardEnabled)"
  Write-Host "- Sound file path: $soundFile ($(Get-AssetStatusLabel -ProjectRoot $ProjectRoot -ConfiguredPath $soundFile))"
  Write-Host "- Billboard image path: $billboardImage ($(Get-AssetStatusLabel -ProjectRoot $ProjectRoot -ConfiguredPath $billboardImage))"
  Write-Host "- Billboard max width: $maxWidth"
  Write-Host "- Billboard max height: $maxHeight"
  Write-Host "- Billboard position: $position"
  Write-Host "- Beginner size guidance: ${RecommendedWidth}x${RecommendedHeight}"
}

function Show-Menu {
  Write-Host ""
  Write-Host "Choose an option"
  Write-Host "1. Turn toast pop-up on or off"
  Write-Host "2. Turn sound alert on or off"
  Write-Host "3. Turn billboard pop-up on or off"
  Write-Host "4. Change the sound file path"
  Write-Host "5. Change the billboard image path"
  Write-Host "6. Change the billboard max width"
  Write-Host "7. Change the billboard max height"
  Write-Host "8. Change the billboard position"
  Write-Host "9. Test notifications now"
  Write-Host "10. Restore config from backup"
  Write-Host "0. Exit"
}

function Read-YesNoChoice {
  param([string]$Prompt)

  while ($true) {
    $response = Read-Host "$Prompt Type yes or no, or press Enter to cancel"
    if ([string]::IsNullOrWhiteSpace($response)) {
      return $null
    }

    switch ($response.Trim().ToLowerInvariant()) {
      "y" { return $true }
      "yes" { return $true }
      "n" { return $false }
      "no" { return $false }
      default { Write-Host "Please type yes or no." }
    }
  }
}

function Read-IntegerChoice {
  param(
    [string]$Prompt,
    [int]$Minimum,
    [int]$Maximum
  )

  while ($true) {
    $response = Read-Host "$Prompt Type a whole number from $Minimum to $Maximum, or press Enter to cancel"
    if ([string]::IsNullOrWhiteSpace($response)) {
      return $null
    }

    $value = 0
    if ([int]::TryParse($response.Trim(), [ref]$value) -and $value -ge $Minimum -and $value -le $Maximum) {
      return $value
    }

    Write-Host "Please enter a whole number from $Minimum to $Maximum."
  }
}

function Read-PathChoice {
  param([string]$Prompt)

  while ($true) {
    $response = Read-Host "$Prompt Press Enter to cancel"
    if ([string]::IsNullOrWhiteSpace($response)) {
      return $null
    }

    $trimmed = $response.Trim()
    if ($trimmed) {
      return $trimmed
    }

    Write-Host "Please enter a file path."
  }
}

function Show-MissingPathWarning {
  param(
    [string]$ProjectRoot,
    [string]$ConfiguredPath
  )

  $resolvedPath = Get-ResolvedAssetPath -ProjectRoot $ProjectRoot -ConfiguredPath $ConfiguredPath
  if (-not $resolvedPath -or (Test-Path -LiteralPath $resolvedPath)) {
    return
  }

  Write-Host "Warning: $ConfiguredPath was not found right now."
  Write-Host "The path will still be saved so you can add the file later."
}

function Invoke-NotificationTest {
  param([string]$ProjectRoot)

  Write-Host ""
  Write-Host "Running npm run diagnose:notifications..."

  try {
    $npm = Get-NpmCommand
  } catch {
    Write-Host $_.Exception.Message
    return
  }

  Push-Location $ProjectRoot
  try {
    & $npm run diagnose:notifications
    $exitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }

  if ($exitCode -ne 0) {
    Write-Host "Notification diagnostics reported an issue. Read the output above."
    return
  }

  Write-Host "Notification diagnostics finished."
}

function Restore-ConfigFromBackup {
  param(
    [string]$ProjectRoot,
    [string]$ConfigPath
  )

  $backupDir = Ensure-BackupDirectory -ProjectRoot $ProjectRoot
  $backups = @(Get-ChildItem -LiteralPath $backupDir -Filter "config-*.json" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending)

  if ($backups.Count -eq 0) {
    Write-Host "No config backups were found yet."
    return
  }

  Write-Host ""
  Write-Host "Available config backups"
  for ($i = 0; $i -lt $backups.Count; $i++) {
    Write-Host "$($i + 1). $($backups[$i].Name) - $($backups[$i].LastWriteTime)"
  }

  while ($true) {
    $response = Read-Host "Type a backup number to restore, or press Enter to cancel"
    if ([string]::IsNullOrWhiteSpace($response)) {
      return
    }

    $selection = 0
    if ([int]::TryParse($response.Trim(), [ref]$selection) -and $selection -ge 1 -and $selection -le $backups.Count) {
      $selectedBackup = $backups[$selection - 1]
      $configObject = Get-JsonObject -Path $selectedBackup.FullName -Label $selectedBackup.Name
      Save-ConfigChange -ProjectRoot $ProjectRoot -ConfigPath $ConfigPath -ConfigObject $configObject -SuccessMessage ("Restored config.json from " + $selectedBackup.Name + ".")
      return
    }

    Write-Host "Please enter a number from 1 to $($backups.Count)."
  }
}

try {
  $projectRoot = Find-ProjectRoot
  $configPath = Join-Path $projectRoot "config.json"
  $examplePath = Join-Path $projectRoot "config.example.json"
  Ensure-ConfigFile -ConfigPath $configPath -ExamplePath $examplePath
  Set-Location -LiteralPath $projectRoot

  Write-Host "Codex Limit Watcher configuration menu"
  Write-Host "This menu changes the beginner-friendly notification settings only."

  while ($true) {
    $config = Get-JsonObject -Path $configPath -Label "config.json"
    Show-CurrentSettings -Config $config -ProjectRoot $projectRoot -ConfigPath $configPath
    Show-Menu

    $choice = Read-Host "Enter a menu number"
    if ([string]::IsNullOrWhiteSpace($choice)) {
      Write-Host "Please enter a menu number."
      continue
    }

    switch ($choice.Trim()) {
      "1" {
        $value = Read-YesNoChoice -Prompt "Do you want toast pop-ups turned on?"
        if ($null -ne $value) {
          Set-ConfigValue -Config $config -SectionName "notifications" -PropertyName "toastEnabled" -Value ([bool]$value)
          Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage ("Toast pop-ups are now " + (Format-OnOff -Value $value) + ".")
        }
      }
      "2" {
        $value = Read-YesNoChoice -Prompt "Do you want sound alerts turned on?"
        if ($null -ne $value) {
          Set-ConfigValue -Config $config -SectionName "notifications" -PropertyName "soundEnabled" -Value ([bool]$value)
          Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage ("Sound alerts are now " + (Format-OnOff -Value $value) + ".")
        }
      }
      "3" {
        $value = Read-YesNoChoice -Prompt "Do you want billboard pop-ups turned on?"
        if ($null -ne $value) {
          Set-ConfigValue -Config $config -SectionName "notifications" -PropertyName "billboardEnabled" -Value ([bool]$value)
          Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage ("Billboard pop-ups are now " + (Format-OnOff -Value $value) + ".")
        }
      }
      "4" {
        $value = Read-PathChoice -Prompt "Enter the sound file path."
        if ($null -ne $value) {
          Show-MissingPathWarning -ProjectRoot $projectRoot -ConfiguredPath $value
          Set-ConfigValue -Config $config -SectionName "notifications" -PropertyName "soundFile" -Value $value
          Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage "Saved the sound file path."
        }
      }
      "5" {
        $value = Read-PathChoice -Prompt "Enter the billboard image path."
        if ($null -ne $value) {
          Show-MissingPathWarning -ProjectRoot $projectRoot -ConfiguredPath $value
          Set-ConfigValue -Config $config -SectionName "notifications" -PropertyName "billboardImage" -Value $value
          Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage "Saved the billboard image path."
        }
      }
      "6" {
        $value = Read-IntegerChoice -Prompt "Enter the billboard max width. Beginner guidance is 400." -Minimum $MinimumWidth -Maximum $MaximumWidth
        if ($null -ne $value) {
          Set-ConfigValue -Config $config -SectionName "billboard" -PropertyName "maxWidth" -Value ([int]$value)
          Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage ("Billboard max width is now " + $value + ".")
        }
      }
      "7" {
        $value = Read-IntegerChoice -Prompt "Enter the billboard max height. Beginner guidance is 300." -Minimum $MinimumHeight -Maximum $MaximumHeight
        if ($null -ne $value) {
          Set-ConfigValue -Config $config -SectionName "billboard" -PropertyName "maxHeight" -Value ([int]$value)
          Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage ("Billboard max height is now " + $value + ".")
        }
      }
      "8" {
        Write-Host ""
        Write-Host "Choose a billboard position"
        for ($i = 0; $i -lt $AllowedPositions.Count; $i++) {
          Write-Host "$($i + 1). $($AllowedPositions[$i])"
        }

        while ($true) {
          $response = Read-Host "Type a position number, or press Enter to cancel"
          if ([string]::IsNullOrWhiteSpace($response)) {
            break
          }

          $selection = 0
          if ([int]::TryParse($response.Trim(), [ref]$selection) -and $selection -ge 1 -and $selection -le $AllowedPositions.Count) {
            $value = $AllowedPositions[$selection - 1]
            Set-ConfigValue -Config $config -SectionName "billboard" -PropertyName "position" -Value $value
            Save-ConfigChange -ProjectRoot $projectRoot -ConfigPath $configPath -ConfigObject $config -SuccessMessage ("Billboard position is now " + $value + ".")
            break
          }

          Write-Host "Please enter a number from 1 to $($AllowedPositions.Count)."
        }
      }
      "9" {
        Invoke-NotificationTest -ProjectRoot $projectRoot
      }
      "10" {
        Restore-ConfigFromBackup -ProjectRoot $projectRoot -ConfigPath $configPath
      }
      "0" {
        Write-Host "No more changes were made."
        exit 0
      }
      default {
        Write-Host "Please choose 0 through 10."
      }
    }
  }
} catch {
  Write-Host ""
  Write-Host "The configuration menu could not finish."
  Write-Host $_.Exception.Message
  exit 1
}
