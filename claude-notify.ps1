# claude-notify.ps1 - Audio notifications for Claude Code on Windows
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

# Volume: 0.0 (silent) to 1.0 (max). Adjust this to taste.
$Volume = 0.15

function Play-Tone([int]$Frequency, [int]$DurationMs) {
    $sampleRate = 44100
    $samples = [int]($sampleRate * $DurationMs / 1000)
    $fadeSamples = [Math]::Min(200, [int]($samples / 4))
    $bytes = New-Object byte[] ($samples * 2)
    for ($i = 0; $i -lt $samples; $i++) {
        $t = $i / $sampleRate
        $amp = $script:Volume
        # Fade in/out to avoid clicks
        if ($i -lt $fadeSamples) { $amp *= $i / $fadeSamples }
        if ($i -gt ($samples - $fadeSamples)) { $amp *= ($samples - $i) / $fadeSamples }
        $val = [int]([Math]::Sin(2 * [Math]::PI * $Frequency * $t) * $amp * 32767)
        $bytes[$i * 2] = [byte]($val -band 0xFF)
        $bytes[$i * 2 + 1] = [byte](($val -shr 8) -band 0xFF)
    }

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    # WAV header
    $dataSize = $bytes.Length
    $bw.Write([Text.Encoding]::ASCII.GetBytes("RIFF"))
    $bw.Write([int](36 + $dataSize))
    $bw.Write([Text.Encoding]::ASCII.GetBytes("WAVE"))
    $bw.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
    $bw.Write([int]16)          # chunk size
    $bw.Write([int16]1)         # PCM
    $bw.Write([int16]1)         # mono
    $bw.Write([int]$sampleRate)
    $bw.Write([int]($sampleRate * 2))  # byte rate
    $bw.Write([int16]2)         # block align
    $bw.Write([int16]16)        # bits per sample
    $bw.Write([Text.Encoding]::ASCII.GetBytes("data"))
    $bw.Write([int]$dataSize)
    $bw.Write($bytes)
    $ms.Position = 0

    $player = New-Object System.Media.SoundPlayer($ms)
    $player.PlaySync()
    $player.Dispose()
    $bw.Dispose()
    $ms.Dispose()
}

function Play-Permission {
    Play-Tone 440 500
}

function Play-PermissionStrict {
    Play-Tone 440 250
    Start-Sleep -Milliseconds 100
    Play-Tone 440 250
}

function Play-Question {
    Play-Tone 440 125
    Start-Sleep -Milliseconds 80
    Play-Tone 440 125
    Start-Sleep -Milliseconds 80
    Play-Tone 440 125
    Start-Sleep -Milliseconds 80
    Play-Tone 440 125
}

function Play-Complete {
    Play-Tone 523 125
    Start-Sleep -Milliseconds 60
    Play-Tone 659 125
    Start-Sleep -Milliseconds 60
    Play-Tone 784 125
    Start-Sleep -Milliseconds 60
    Play-Tone 1047 125
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

    # Use pwsh (PowerShell 7+) if available, otherwise fall back to powershell (5.1)
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        $psExe = "pwsh"
    } else {
        $psExe = "powershell"
    }
    $notifyCmd = "$psExe -NoProfile -ExecutionPolicy Bypass -Command `"& '$scriptPath' '--from-hook'`""
    $completeCmd = "$psExe -NoProfile -ExecutionPolicy Bypass -Command `"& '$scriptPath' '--complete'`""

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

function Uninstall-Hooks {
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"

    if (-not (Test-Path $settingsPath)) {
        Write-Host "No settings file found at $settingsPath"
        return
    }

    $raw = Get-Content $settingsPath -Raw
    if ($raw -notmatch "claude-notify") {
        Write-Host "No claude-notify hooks found in $settingsPath"
        return
    }

    $settings = $raw | ConvertFrom-Json

    if ($settings.hooks.Notification) {
        $settings.hooks.Notification = @(
            $settings.hooks.Notification | Where-Object {
                $keep = $true
                foreach ($h in $_.hooks) {
                    if ($h.command -match "claude-notify") { $keep = $false }
                }
                $keep
            }
        )
        if ($settings.hooks.Notification.Count -eq 0) {
            $settings.hooks.PSObject.Properties.Remove("Notification")
        }
    }

    if ($settings.hooks.Stop) {
        $settings.hooks.Stop = @(
            $settings.hooks.Stop | Where-Object {
                $keep = $true
                foreach ($h in $_.hooks) {
                    if ($h.command -match "claude-notify") { $keep = $false }
                }
                $keep
            }
        )
        if ($settings.hooks.Stop.Count -eq 0) {
            $settings.hooks.PSObject.Properties.Remove("Stop")
        }
    }

    # Remove hooks key if empty
    $hookProps = $settings.hooks.PSObject.Properties | Measure-Object
    if ($hookProps.Count -eq 0) {
        $settings.PSObject.Properties.Remove("hooks")
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "Removed claude-notify hooks from $settingsPath"
    Write-Host ""
    Write-Host "You can safely delete the claude-notify folder now."
}

# Main
switch ($Command) {
    "--permission"        { Play-Permission }
    "--permission-strict" { Play-PermissionStrict }
    "--question"          { Play-Question }
    "--complete"          { Play-Complete }
    "--from-hook"         { From-Hook }
    "--install"           { Install-Hooks }
    "--uninstall"         { Uninstall-Hooks }
    default {
        Write-Host "claude-notify.ps1 - Audio notifications for Claude Code"
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "  claude-notify.ps1 --permission        Single beep"
        Write-Host "  claude-notify.ps1 --permission-strict  Two beeps"
        Write-Host "  claude-notify.ps1 --question           Four quick beeps"
        Write-Host "  claude-notify.ps1 --complete           Ascending arpeggio"
        Write-Host "  claude-notify.ps1 --from-hook          Auto-detect from JSON"
        Write-Host "  claude-notify.ps1 --install            Configure Claude Code hooks"
        Write-Host "  claude-notify.ps1 --uninstall          Remove hooks from settings"
    }
}
