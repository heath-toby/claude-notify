#!/bin/bash
# Install claude-notify — audio notifications for Claude Code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"
SETTINGS_FILE="${HOME}/.claude/settings.json"

# Step 1: Install the script
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/claude-notify" "$INSTALL_DIR/claude-notify"
chmod +x "$INSTALL_DIR/claude-notify"

# Step 2: Generate cached WAV files
"$INSTALL_DIR/claude-notify" --cache

# Step 3: Configure Claude Code hooks
mkdir -p "$(dirname "$SETTINGS_FILE")"

if [ -f "$SETTINGS_FILE" ]; then
    # Check if hooks are already configured
    if grep -q "claude-notify" "$SETTINGS_FILE" 2>/dev/null; then
        echo "Hooks already configured in $SETTINGS_FILE"
    else
        # Merge hooks into existing settings using Python (handles JSON properly)
        python3 -c "
import json, sys

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})

# Add Notification hook if not present
if 'Notification' not in hooks:
    hooks['Notification'] = []
hooks['Notification'].append({
    'hooks': [{'type': 'command', 'command': 'claude-notify --from-hook', 'timeout': 5}]
})

# Add Stop hook if not present
if 'Stop' not in hooks:
    hooks['Stop'] = []
hooks['Stop'].append({
    'hooks': [{'type': 'command', 'command': 'claude-notify --complete', 'timeout': 5}]
})

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print('Added hooks to $SETTINGS_FILE')
"
    fi
else
    # Create new settings file with just the hooks
    cat > "$SETTINGS_FILE" << 'SETTINGS'
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
SETTINGS
    echo "Created $SETTINGS_FILE with hooks"
fi

echo ""
echo "claude-notify installed successfully!"
echo ""
echo "Test the sounds:"
echo "  claude-notify --permission   # Single beep"
echo "  claude-notify --question     # Four quick beeps"
echo "  claude-notify --complete     # Ascending arpeggio"
echo ""
echo "Sounds will play automatically in your next Claude Code session."
