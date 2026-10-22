#!/bin/sh
# Rex's Deadman Switch — Linux. User crontab, no root.
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
src=$here/deadman.py
[ -f "$src" ] || src=$here/../deadman.py
[ -f "$src" ] || { echo "deadman.py is not next to this installer" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Python 3.10+ is required." >&2; exit 1; }
mkdir -p "$HOME/.local/bin" "$HOME/.config/deadman"
dest=$HOME/.local/bin/deadman
cp "$src" "$dest"
chmod 755 "$dest"
if [ ! -f "$HOME/.config/deadman/config.json" ]; then
  DEADMAN_HOME="$HOME/.config/deadman" "$dest" init
fi
py=$(command -v python3)
line="0 8 * * * DEADMAN_HOME=$HOME/.config/deadman $py $dest run # RexDeadman"
tmp=$(mktemp)
crontab -l 2>/dev/null | grep -v 'RexDeadman' | grep -v '^$' >"$tmp" || true
printf '%s\n' "$line" >>"$tmp"
crontab "$tmp"
rm -f "$tmp"
echo "Installed $dest"
echo "Daily at 08:00. Check in with: deadman ping"
echo "If the command is not found, add \$HOME/.local/bin to PATH."
