#!/bin/sh
# Rex's Deadman Switch — macOS. User LaunchAgent, no root.
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
src=$here/deadman.py
[ -f "$src" ] || src=$here/../deadman.py
[ -f "$src" ] || { echo "deadman.py is not next to this installer" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Python 3.10+ is required." >&2; exit 1; }
mkdir -p "$HOME/.local/bin" "$HOME/.config/deadman" "$HOME/Library/LaunchAgents"
dest=$HOME/.local/bin/deadman
cp "$src" "$dest"
chmod 755 "$dest"
if [ ! -f "$HOME/.config/deadman/config.json" ]; then
  DEADMAN_HOME="$HOME/.config/deadman" "$dest" init
fi
py=$(command -v python3)
plist=$HOME/Library/LaunchAgents/com.rex.deadman.plist
cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.rex.deadman</string>
  <key>ProgramArguments</key>
  <array>
    <string>$py</string>
    <string>$dest</string>
    <string>run</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DEADMAN_HOME</key><string>$HOME/.config/deadman</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>8</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
</dict>
</plist>
EOF
uid=$(id -u)
launchctl bootout "gui/$uid/com.rex.deadman" 2>/dev/null || true
if ! launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null; then
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load -w "$plist"
fi
echo "Installed $dest"
echo "LaunchAgent com.rex.deadman runs daily at 08:00."
echo "Check in with: deadman ping"
echo "If the command is not found, add \$HOME/.local/bin to PATH."
