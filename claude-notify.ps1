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

$SampleRate = 44100
$CacheDir = Join-Path $env:LOCALAPPDATA "claude-notify"

# --- Continuous-buffer playback (matches the Linux build) ------------------
# Every pattern is rendered into ONE PCM buffer, with the gaps between tones
# baked in as silence samples. That buffer is wrapped in a single WAV and
# played once. This is what makes the Linux version sound smooth: there is no
# per-tone SoundPlayer startup/teardown and no Start-Sleep jitter between
# beeps -- the audio device opens once and streams the whole pattern, with
# sample-accurate gaps, instead of four separate clips spaced ~250ms apart.

# Append a tone (5ms fade in/out, to match Linux and avoid clicks) to $Buffer.
function Add-Tone {
    param($Buffer, [double]$Frequency, [int]$DurationMs)
    $samples = [int]($script:SampleRate * $DurationMs / 1000)
    $fade = [Math]::Min(220, [int]($samples / 4))   # 220 = 5ms @ 44.1kHz, as Linux
    for ($i = 0; $i -lt $samples; $i++) {
        $amp = $script:Volume
        if ($i -lt $fade) { $amp *= $i / $fade }
        elseif ($i -gt ($samples - $fade)) { $amp *= ($samples - $i) / $fade }
        $val = [int]([Math]::Sin(2 * [Math]::PI * $Frequency * $i / $script:SampleRate) * $amp * 32767)
        [void]$Buffer.Add([byte]($val -band 0xFF))
        [void]$Buffer.Add([byte](($val -shr 8) -band 0xFF))
    }
}

# Append a gap of silence to $Buffer.
function Add-Gap {
    param($Buffer, [int]$DurationMs)
    $bytes = [int]($script:SampleRate * $DurationMs / 1000) * 2
    for ($i = 0; $i -lt $bytes; $i++) { [void]$Buffer.Add([byte]0) }
}

# Build the PCM byte array for a named pattern.
function Get-PatternPcm {
    param([string]$Name)
    $buf = New-Object System.Collections.Generic.List[byte]
    switch ($Name) {
        "permission"        { Add-Tone $buf 440 500 }
        "permission_strict" { Add-Tone $buf 440 250; Add-Gap $buf 100; Add-Tone $buf 440 250 }
        "question"          { Add-Tone $buf 440 125; Add-Gap $buf 80; Add-Tone $buf 440 125; Add-Gap $buf 80; Add-Tone $buf 440 125; Add-Gap $buf 80; Add-Tone $buf 440 125 }
        "complete"          { Add-Tone $buf 523.25 125; Add-Gap $buf 60; Add-Tone $buf 659.25 125; Add-Gap $buf 60; Add-Tone $buf 783.99 125; Add-Gap $buf 60; Add-Tone $buf 1046.50 125 }
    }
    return $buf.ToArray()
}

# Wrap PCM bytes in a mono 16-bit WAV container.
function Build-Wav {
    param([byte[]]$Pcm)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $dataSize = $Pcm.Length
    $bw.Write([Text.Encoding]::ASCII.GetBytes("RIFF"))
    $bw.Write([int](36 + $dataSize))
    $bw.Write([Text.Encoding]::ASCII.GetBytes("WAVE"))
    $bw.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
    $bw.Write([int]16)                       # chunk size
    $bw.Write([int16]1)                      # PCM
    $bw.Write([int16]1)                      # mono
    $bw.Write([int]$script:SampleRate)
    $bw.Write([int]($script:SampleRate * 2)) # byte rate
    $bw.Write([int16]2)                      # block align
    $bw.Write([int16]16)                     # bits per sample
    $bw.Write([Text.Encoding]::ASCII.GetBytes("data"))
    $bw.Write([int]$dataSize)
    $bw.Write($Pcm)
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    return $bytes
}

# Return the path to the cached WAV for a pattern, generating it if missing.
# The volume is encoded in the filename so changing $Volume regenerates.
function Get-CachedWav {
    param([string]$Name)
    if (-not (Test-Path $script:CacheDir)) {
        New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
    }
    $vtag = [int]([Math]::Round($script:Volume * 100))
    $path = Join-Path $script:CacheDir "$Name-v$vtag.wav"
    if (-not (Test-Path $path)) {
        $wav = Build-Wav (Get-PatternPcm $Name)
        [System.IO.File]::WriteAllBytes($path, $wav)
    }
    return $path
}

# Play a pattern: one cached WAV, one PlaySync, no inter-tone sleeps.
function Play-Pattern {
    param([string]$Name)
    $player = New-Object System.Media.SoundPlayer((Get-CachedWav $Name))
    $player.PlaySync()
    $player.Dispose()
}

function Play-Permission       { Play-Pattern "permission" }
function Play-PermissionStrict { Play-Pattern "permission_strict" }
function Play-Question         { Play-Pattern "question" }
function Play-Complete         { Play-Pattern "complete" }

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

# Return the PowerShell executable to invoke from the hooks.
# Prefers pwsh (PowerShell 7+, "full"/cross-platform) when it's installed,
# and falls back to powershell (Windows PowerShell 5.1, the default that ships
# with Windows). Returns the bare command name so it resolves via PATH.
function Get-PowerShellExe {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return "pwsh"
    }
    return "powershell"
}

function Install-Hooks {
    $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
    $scriptPath = $PSCommandPath -replace '\\', '/'

    $psExe = Get-PowerShellExe
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
    "--cache"             {
        foreach ($p in "permission","permission_strict","question","complete") {
            Get-CachedWav $p | Out-Null
        }
        Write-Host "Cached WAV files in $CacheDir"
    }
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
