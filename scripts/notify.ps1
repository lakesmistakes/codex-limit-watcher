param(
  [string]$Title = "Codex Limit Watcher",
  [string]$Body = "Codex limit status changed.",
  [string]$SoundFile = "",
  [string]$ToastEnabled = "True",
  [string]$PlaySoundOnly = "False",
  [int]$VisibleSeconds = 12
)

$ErrorActionPreference = "Stop"

try {
  if ($SoundFile) {
    if (-not (Test-Path -LiteralPath $SoundFile)) {
      throw "Sound file not found: $SoundFile"
    }

    $player = New-Object System.Media.SoundPlayer
    $player.SoundLocation = (Resolve-Path -LiteralPath $SoundFile).Path
    $player.Load()
    $player.PlaySync()
    Write-Output "SOUND_OK"
  } elseif ([System.Convert]::ToBoolean($PlaySoundOnly)) {
    throw "No sound file was provided."
  }

  if ([System.Convert]::ToBoolean($PlaySoundOnly)) {
    exit 0
  }

  if (-not [System.Convert]::ToBoolean($ToastEnabled)) {
    exit 0
  }

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $notify = New-Object System.Windows.Forms.NotifyIcon
  $notify.Icon = [System.Drawing.SystemIcons]::Information
  $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
  $notify.BalloonTipTitle = $Title
  $notify.BalloonTipText = $Body
  $notify.Visible = $true
  $notify.ShowBalloonTip([Math]::Max(1000, $VisibleSeconds * 1000))
  Write-Output "TOAST_OK"
  Start-Sleep -Seconds ([Math]::Max(2, $VisibleSeconds))
  $notify.Dispose()
  exit 0
} catch {
  $message = $_.Exception.Message
  if (-not $message) {
    $message = $_.ToString()
  }
  Write-Error $message
  exit 1
}
