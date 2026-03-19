#!/bin/bash
# Install claude-notify

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${HOME}/.local/bin"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/claude-notify" "$INSTALL_DIR/claude-notify"
chmod +x "$INSTALL_DIR/claude-notify"

# Generate cached WAV files
"$INSTALL_DIR/claude-notify" --cache

echo "Installed claude-notify to $INSTALL_DIR/claude-notify"
echo ""
echo "Add the following to your ~/.claude/settings.json to enable hooks:"
echo ""
echo '  "hooks": {'
echo '    "Notification": [{"hooks": [{"type": "command", "command": "claude-notify --from-hook", "timeout": 5}]}],'
echo '    "Stop": [{"hooks": [{"type": "command", "command": "claude-notify --complete", "timeout": 5}]}]'
echo '  }'
