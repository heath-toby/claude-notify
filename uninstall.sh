#!/bin/bash
# Uninstall claude-notify

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
SETTINGS_FILE="${HOME}/.claude/settings.json"
CACHE_DIR="${HOME}/.cache/claude-notify"

# Remove the script
if [ -f "$INSTALL_DIR/claude-notify" ]; then
    rm "$INSTALL_DIR/claude-notify"
    echo "Removed $INSTALL_DIR/claude-notify"
fi

# Remove cached WAV files
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "Removed $CACHE_DIR"
fi

# Remove hooks from settings.json
if [ -f "$SETTINGS_FILE" ] && grep -q "claude-notify" "$SETTINGS_FILE" 2>/dev/null; then
    python3 -c "
import json

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})

# Remove Notification hooks that reference claude-notify
if 'Notification' in hooks:
    hooks['Notification'] = [
        h for h in hooks['Notification']
        if not any('claude-notify' in hook.get('command', '') for hook in h.get('hooks', []))
    ]
    if not hooks['Notification']:
        del hooks['Notification']

# Remove Stop hooks that reference claude-notify
if 'Stop' in hooks:
    hooks['Stop'] = [
        h for h in hooks['Stop']
        if not any('claude-notify' in hook.get('command', '') for hook in h.get('hooks', []))
    ]
    if not hooks['Stop']:
        del hooks['Stop']

# Remove hooks key entirely if empty
if not hooks:
    settings.pop('hooks', None)

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print('Removed hooks from $SETTINGS_FILE')
"
fi

echo ""
echo "claude-notify uninstalled."
