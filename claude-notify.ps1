# claude-notify.ps1 — Audio notifications for Claude Code on Windows
# Plays beep patterns when Claude needs your attention.
#
# Usage:
#   claude-notify.ps1 --permission        Single 500ms beep
#   claude-notify.ps1 --permission-strict  Two 250ms beeps
#   claude-notify.ps1 --question           Four quick beeps
#   claude-notify.ps1 --complete           Ascending arpeggio
#   claude-notify.ps1 --from-hook          Auto-detect from stdin JSON
#   claude-notify.ps1 --install            Configure Claude Code hooks

param(
    [Parameter(Position=0)]
    [string]$Command
)

function Play-Permission {
    [Console]::Beep(440, 500)
}

function Play-PermissionStrict {
    [Console]::Beep(440, 250)
    Start-Sleep -Milliseconds 100
    [Console]::Beep(440, 250)
}

function Play-Question {
    [Console]::Beep(440, 125)
    Start-Sleep -Milliseconds 80
    [Console]::Beep(440, 125)
    Start-Sleep -Milliseconds 80
    [Console]::Beep(440, 125)
    Start-Sleep -Milliseconds 80
    [Console]::Beep(440, 125)
}

function Play-Complete {
    [Console]::Beep(523, 125)
    Start-Sleep -Milliseconds 60
    [Console]::Beep(659, 125)
    Start-Sleep -Milliseconds 60
    [Console]::Beep(784, 125)
    Start-Sleep -Milliseconds 60
    [Console]::Beep(1047, 125)
}

function From-Hook {
    $input_text = [Console]::In.ReadToEnd()
    try {
        $data = $input_text | ConvertFrom-Json
        $message = $data.message
        if ($message -match "needs your permission") {
            Play-Permission
        } elseif ($message -match "needs your attention") {
            Play-Question
        } else {
            Play-Permission
        }
    } catch {
        Play-Permission
    }
}

function Install-Hooks {
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    $scriptPath = $PSCommandPath -replace '\\', '/'

    # Build the hook commands using pwsh
    $notifyCmd = "pwsh -NoProfile -File `"$scriptPath`" --from-hook"
    $completeCmd = "pwsh -NoProfile -File `"$scriptPath`" --complete"

    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

        # Check if hooks already configured
        $raw = Get-Content $settingsPath -Raw
        if ($raw -match "claude-notify") {
            Write-Host "Hooks already configured in $settingsPath"
            return
        }
    } else {
        $settings = @{}
        $dir = Split-Path $settingsPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Add hooks
    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{}
    }

    $settings.hooks.Notification = @(
        @{
            hooks = @(
                @{
                    type = "command"
                    command = $notifyCmd
                    timeout = 5
                }
            )
        }
    )

    $settings.hooks.Stop = @(
        @{
            hooks = @(
                @{
                    type = "command"
                    command = $completeCmd
                    timeout = 5
                }
            )
        }
    )

    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "Hooks configured in $settingsPath"
    Write-Host ""
    Write-Host "Test the sounds:"
    Write-Host "  pwsh -File `"$scriptPath`" --permission"
    Write-Host "  pwsh -File `"$scriptPath`" --question"
    Write-Host "  pwsh -File `"$scriptPath`" --complete"
    Write-Host ""
    Write-Host "Sounds will play automatically in your next Claude Code session."
}

# Main
switch ($Command) {
    "--permission"        { Play-Permission }
    "--permission-strict" { Play-PermissionStrict }
    "--question"          { Play-Question }
    "--complete"          { Play-Complete }
    "--from-hook"         { From-Hook }
    "--install"           { Install-Hooks }
    default {
        Write-Host "claude-notify.ps1 — Audio notifications for Claude Code"
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "  claude-notify.ps1 --permission        Single beep"
        Write-Host "  claude-notify.ps1 --permission-strict  Two beeps"
        Write-Host "  claude-notify.ps1 --question           Four quick beeps"
        Write-Host "  claude-notify.ps1 --complete           Ascending arpeggio"
        Write-Host "  claude-notify.ps1 --from-hook          Auto-detect from JSON"
        Write-Host "  claude-notify.ps1 --install            Configure Claude Code hooks"
    }
}
