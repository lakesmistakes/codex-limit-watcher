$ErrorActionPreference = "Stop"

function Get-StatusFunctionPrelude {
  param([string]$Path)

  $lines = Get-Content -LiteralPath $Path
  $prelude = New-Object System.Collections.Generic.List[string]

  foreach ($line in $lines) {
    if ($line -match '^try\s*\{$') {
      break
    }
    [void]$prelude.Add($line)
  }

  return [string]::Join([Environment]::NewLine, $prelude)
}

try {
  $statusScript = Join-Path $PSScriptRoot "status.ps1"
  $prelude = Get-StatusFunctionPrelude -Path $statusScript
  Invoke-Expression $prelude

  $sinceUtc = (Get-Date).ToUniversalTime()
  $entries = @(
    [pscustomobject]@{
      timestamp = $sinceUtc.AddMinutes(-1).ToString("o")
      error = "before-window"
      source = "codex-app-server"
    },
    [pscustomobject]@{
      timestamp = $sinceUtc.AddMinutes(1).ToString("o")
      error = "after-window"
      source = "codex-app-server"
    },
    [pscustomobject]@{
      timestamp = "not-a-date"
      error = "bad-timestamp"
      source = "codex-app-server"
    },
    [pscustomobject]@{
      timestamp = $sinceUtc.AddMinutes(2).ToString("o")
      error = $null
      source = "codex-app-server"
    }
  )

  $recentErrors = @(Get-RecentAppErrors -Entries $entries -SinceUtc $sinceUtc)
  if ($recentErrors.Count -ne 1) {
    throw "Expected 1 recent error after filtering, got $($recentErrors.Count)."
  }

  if ($recentErrors[0].error -ne "after-window") {
    throw "Expected the recent error to be after-window, got '$($recentErrors[0].error)'."
  }

  $allErrors = @(Get-RecentAppErrors -Entries $entries -SinceUtc $null)
  if ($allErrors.Count -ne 3) {
    throw "Expected 3 total errors when SinceUtc is null, got $($allErrors.Count)."
  }

  Write-Host "status running filter regression passed"
  exit 0
} catch {
  Write-Host "status running filter regression failed"
  Write-Host $_.Exception.Message
  exit 1
}
