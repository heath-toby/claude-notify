# claude-notify

Audio notifications for [Claude Code](https://claude.com/claude-code). Plays short sine wave beep patterns when Claude needs your attention, so you don't have to keep watching the terminal.

Designed for accessibility — particularly useful for screen reader users who can't see the terminal prompts, but handy for anyone who wants to multitask while Claude works.

## Sound Patterns

| Event | Sound | Description |
|-------|-------|-------------|
| Permission prompt | Single 500ms beep | Claude needs permission to use a tool |
| Question | Four quick beeps | Claude is asking you a question |
| Task complete | Ascending arpeggio (C-E-G-C) | Claude has finished the current task |

All sounds are generated as sine waves at ~25% amplitude — audible but not startling.

## Requirements

**Linux**: PipeWire or PulseAudio, Python 3, Claude Code with hooks support

**Windows**: PowerShell 5.1+ (included with Windows), Claude Code with hooks support

## Installation

### Linux

```bash
git clone https://github.com/heath-toby/claude-notify
cd claude-notify
./install.sh
```

This will:
1. Copy the script to `~/.local/bin/`
2. Generate cached WAV files in `~/.cache/claude-notify/`
3. Automatically add the necessary hooks to your `~/.claude/settings.json` (preserving any existing settings)

To uninstall: `./uninstall.sh`

### Windows

```powershell
git clone https://github.com/heath-toby/claude-notify
cd claude-notify
pwsh -File claude-notify.ps1 --install
```

This configures Claude Code hooks to call the PowerShell script. No compilation or additional software needed — it uses Windows' built-in `Console.Beep()`.

To test: `pwsh -File claude-notify.ps1 --complete`

Sounds will play automatically in your next Claude Code session on both platforms.

### Manual Setup

If you prefer to configure the hooks yourself, add this to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-notify --from-hook",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-notify --complete",
            "timeout": 5
          }
        ]
      }
    ]
  }
}

## How It Works

1. **First run**: Python generates four short WAV files in `~/.cache/claude-notify/` (takes about 1 second)
2. **Every subsequent run**: A bash script calls `paplay` on the cached WAV file — executes in ~3ms
3. **Claude Code hooks**: The `Notification` hook fires when Claude needs input. The `Stop` hook fires when Claude finishes a task. Both call the script with the appropriate flag.

The `--from-hook` mode reads the JSON notification from stdin and plays the correct sound based on the message content:
- "needs your permission" → single beep (permission prompt)
- "needs your attention" → four beeps (question from Claude)

## Manual Usage

You can also use the script independently:

```bash
claude-notify --permission        # Single 500ms beep at 440Hz
claude-notify --permission-strict # Two 250ms beeps at 440Hz
claude-notify --question          # Four 125ms beeps at 440Hz
claude-notify --complete          # Ascending arpeggio (C5-E5-G5-C6)
claude-notify --from-hook         # Auto-detect from stdin JSON
claude-notify --cache             # Regenerate cached WAV files
```

## Customisation

The script is a single bash file with an embedded Python snippet for WAV generation. To change the sounds:

1. Delete `~/.cache/claude-notify/`
2. Edit the `generate_cache()` function in `claude-notify`:
   - `AMP` — amplitude (0.0 to 1.0, default 0.25)
   - `tone(freq, duration)` — change frequencies or durations
   - Add new patterns by adding entries to the `files` dictionary
3. Run `claude-notify --cache` to regenerate

## Known Limitations

- Claude Code currently sends the same notification type (`permission_prompt`) for both yes/always/no prompts and yes/no-only prompts, so they can't be distinguished with different sounds. The `--permission-strict` pattern (two beeps) exists but has no automatic trigger yet.
- The `Stop` hook fires whenever Claude stops generating, including when it pauses for tool use. You may occasionally hear the arpeggio mid-task. This is a Claude Code hook behaviour, not a bug in the script.

## Licence

MIT
