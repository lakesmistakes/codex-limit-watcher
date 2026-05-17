param(
  [string]$Title = "Codex Limit Restored",
  [string]$Message = "Codex usage is back.",
  [string]$Bucket = "weekly",
  [string]$OldUsed = "unknown",
  [string]$NewUsed = "unknown",
  [string]$ResetTime = "unknown",
  [string]$ScheduledText = "Scheduled time unavailable",
  [string]$TriggeredText = "Triggered time unavailable",
  [string]$ImagePath = "",
  [int]$Seconds = 30,
  [int]$Width = 400,
  [int]$Height = 300,
  [string]$AlwaysOnTop = "True",
  [string]$Borderless = "True",
  [string]$ShowTaskbarIcon = "False",
  [string]$Mode = "imageWithSmallBadge",
  [string]$Fit = "contain",
  [string]$Position = "bottomRight",
  [int]$ScreenMargin = 24,
  [string]$BackgroundColor = "#000000",
  [int]$BadgeFontSize = 11,
  [int]$BadgePadding = 8,
  [double]$BadgeOpacity = 0.72,
  [string]$ShowCustomDismissButton = "False",
  [string]$ClickToDismiss = "True",
  [string]$EmitReady = "False"
)

$ErrorActionPreference = "Stop"

try {
  Add-Type -AssemblyName PresentationFramework
  Add-Type -AssemblyName PresentationCore
  Add-Type -AssemblyName WindowsBase

  $window = New-Object System.Windows.Window
  $window.Title = "Codex Limit Watcher"
  $window.Width = [Math]::Max(1, $Width)
  $window.Height = [Math]::Max(1, $Height)
  $window.WindowStartupLocation = "Manual"
  $window.Topmost = [System.Convert]::ToBoolean($AlwaysOnTop)
  $window.ShowInTaskbar = [System.Convert]::ToBoolean($ShowTaskbarIcon)
  $window.WindowStyle = if ([System.Convert]::ToBoolean($Borderless)) { "None" } else { "SingleBorderWindow" }
  $window.ResizeMode = "NoResize"
  $window.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($BackgroundColor))

  $grid = New-Object System.Windows.Controls.Grid
  $window.Content = $grid

  $imageExists = $ImagePath -and (Test-Path -LiteralPath $ImagePath)
  $normalizedMode = if ($Mode -eq "imageOnly" -or $Mode -eq "imageWithSmallBadge") { $Mode } else { "imageWithSmallBadge" }
  $stretchMode = switch ($Fit) {
    "fill" { "UniformToFill" }
    "stretch" { "Fill" }
    default { "Uniform" }
  }

  if ($imageExists) {
    $image = New-Object System.Windows.Controls.Image
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = New-Object System.Uri((Resolve-Path -LiteralPath $ImagePath).Path)
    $bitmap.EndInit()
    $image.Source = $bitmap
    $image.Stretch = $stretchMode
    $grid.Children.Add($image) | Out-Null
  }

  if ($imageExists -and $normalizedMode -eq "imageWithSmallBadge") {
    $clampedBadgeOpacity = [Math]::Min(1.0, [Math]::Max(0.0, $BadgeOpacity))
    $badgeAlpha = [byte][Math]::Round(255 * $clampedBadgeOpacity)
    $badge = New-Object System.Windows.Controls.Border
    $badge.HorizontalAlignment = "Right"
    $badge.VerticalAlignment = "Bottom"
    $badge.Margin = "0,0,10,10"
    $badge.Padding = "$BadgePadding,$BadgePadding,$BadgePadding,$BadgePadding"
    $badge.CornerRadius = "8"
    $badge.MaxWidth = [Math]::Max(140, [Math]::Floor($window.Width * 0.45))
    $badge.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb($badgeAlpha, 0, 0, 0))

    $badgeStack = New-Object System.Windows.Controls.StackPanel
    $badge.Child = $badgeStack

    foreach ($line in @($ScheduledText, $TriggeredText)) {
      $block = New-Object System.Windows.Controls.TextBlock
      $block.Text = $line
      $block.FontSize = $BadgeFontSize
      $block.FontWeight = "SemiBold"
      $block.Foreground = [System.Windows.Media.Brushes]::White
      $block.TextWrapping = "Wrap"
      $block.Margin = "0,1,0,1"
      $block.MaxWidth = [Math]::Max(120, [Math]::Floor($window.Width * 0.45) - ($BadgePadding * 2))
      $badgeStack.Children.Add($block) | Out-Null
    }

    $grid.Children.Add($badge) | Out-Null
  }

  if (-not $imageExists) {
    $overlay = New-Object System.Windows.Controls.Border
    $overlay.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(216, 0, 0, 0))
    $overlay.Padding = "28"
    $overlay.Margin = "16"
    $overlay.CornerRadius = "16"
    $overlay.VerticalAlignment = "Center"
    $overlay.HorizontalAlignment = "Center"
    $overlay.MaxWidth = [Math]::Max(160, $window.Width - 32)
    $grid.Children.Add($overlay) | Out-Null

    $stack = New-Object System.Windows.Controls.StackPanel
    $overlay.Child = $stack

    function Add-Text($Text, $Size, $Weight, $Color) {
      $block = New-Object System.Windows.Controls.TextBlock
      $block.Text = $Text
      $block.FontSize = $Size
      $block.FontWeight = $Weight
      $block.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
      $block.TextWrapping = "Wrap"
      $block.HorizontalAlignment = "Center"
      $block.TextAlignment = "Center"
      $block.Margin = "0,4,0,4"
      $stack.Children.Add($block) | Out-Null
    }

    Add-Text $Title 34 "Bold" "#38f5a5"
    Add-Text $Message 20 "SemiBold" "#ffffff"
    Add-Text $ScheduledText 18 "SemiBold" "#ffdf5d"
    Add-Text $TriggeredText 16 "Normal" "#d5d5d5"
    Add-Text "Bucket: $Bucket    Old: $OldUsed%    New: $NewUsed%" 16 "Normal" "#d5d5d5"
  }

  if ([System.Convert]::ToBoolean($ShowCustomDismissButton)) {
    $button = New-Object System.Windows.Controls.Button
    $button.Content = "Dismiss"
    $button.FontSize = 16
    $button.FontWeight = "SemiBold"
    $button.Padding = "18,8,18,8"
    $button.Margin = "0,0,20,20"
    $button.HorizontalAlignment = "Right"
    $button.VerticalAlignment = "Top"
    $button.Add_Click({ $window.Close() })
    $grid.Children.Add($button) | Out-Null
  }

  $workArea = [System.Windows.SystemParameters]::WorkArea
  $windowWidth = $window.Width
  $windowHeight = $window.Height
  $normalizedPosition = switch ($Position) {
    "bottomRight" { "bottomRight" }
    "bottomLeft" { "bottomLeft" }
    "topRight" { "topRight" }
    "topLeft" { "topLeft" }
    default { "center" }
  }

  $left = 0.0
  $top = 0.0
  switch ($normalizedPosition) {
    "bottomRight" {
      $left = $workArea.Right - $windowWidth - $ScreenMargin
      $top = $workArea.Bottom - $windowHeight - $ScreenMargin
    }
    "bottomLeft" {
      $left = $workArea.Left + $ScreenMargin
      $top = $workArea.Bottom - $windowHeight - $ScreenMargin
    }
    "topRight" {
      $left = $workArea.Right - $windowWidth - $ScreenMargin
      $top = $workArea.Top + $ScreenMargin
    }
    "topLeft" {
      $left = $workArea.Left + $ScreenMargin
      $top = $workArea.Top + $ScreenMargin
    }
    default {
      $left = $workArea.Left + (($workArea.Width - $windowWidth) / 2)
      $top = $workArea.Top + (($workArea.Height - $windowHeight) / 2)
    }
  }

  $maxLeft = [Math]::Max($workArea.Left, $workArea.Right - $windowWidth)
  $maxTop = [Math]::Max($workArea.Top, $workArea.Bottom - $windowHeight)
  $window.Left = [Math]::Min($maxLeft, [Math]::Max($workArea.Left, $left))
  $window.Top = [Math]::Min($maxTop, [Math]::Max($workArea.Top, $top))

  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromSeconds([Math]::Max(5, $Seconds))
  $timer.Add_Tick({
    $timer.Stop()
    $window.Close()
  })
  $window.Add_PreviewKeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
      $window.Close()
    }
  })
  if ([System.Convert]::ToBoolean($ClickToDismiss)) {
    $grid.Add_MouseLeftButtonUp({ $window.Close() })
  }
  $window.Add_ContentRendered({
    if ([System.Convert]::ToBoolean($EmitReady)) {
      $workAreaData = [ordered]@{
        left = [Math]::Round($workArea.Left)
        top = [Math]::Round($workArea.Top)
        right = [Math]::Round($workArea.Right)
        bottom = [Math]::Round($workArea.Bottom)
        width = [Math]::Round($workArea.Width)
        height = [Math]::Round($workArea.Height)
      }
      $meta = [ordered]@{
        workAreaSource = "SystemParameters.WorkArea"
        workArea = $workAreaData
        screenWorkingArea = $workAreaData
        position = $normalizedPosition
        screenMargin = $ScreenMargin
        dpiSafe = $true
        windowLeft = [Math]::Round($window.Left)
        windowTop = [Math]::Round($window.Top)
        windowWidth = [Math]::Round($windowWidth)
        windowHeight = [Math]::Round($windowHeight)
      } | ConvertTo-Json -Compress
      [Console]::Out.WriteLine("BILLBOARD_META $meta")
      [Console]::Out.WriteLine("BILLBOARD_READY")
    }
    $timer.Start()
    $window.Activate()
  })
  $window.ShowDialog() | Out-Null
  exit 0
} catch {
  $message = $_.Exception.Message
  if (-not $message) {
    $message = $_.ToString()
  }
  Write-Error $message
  exit 1
}
