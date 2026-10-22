#!/data/data/com.termux/files/usr/bin/sh
# Rex's Deadman Switch — Android via Termux. Not a Play Store app.
set -eu
if ! command -v pkg >/dev/null 2>&1; then
  echo "Run this inside Termux. Android itself has no cron." >&2
  exit 1
fi
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
src=$here/deadman.py
[ -f "$src" ] || src=$here/../deadman.py
[ -f "$src" ] || { echo "deadman.py is not next to this installer" >&2; exit 1; }
pkg install -y python cronie
mkdir -p "$HOME/.config/deadman"
dest="${PREFIX:-$HOME}/bin/deadman"
cp "$src" "$dest"
chmod 755 "$dest"
if [ ! -f "$HOME/.config/deadman/config.json" ]; then
  DEADMAN_HOME="$HOME/.config/deadman" python "$dest" init
fi
py=$(command -v python)
line="0 8 * * * DEADMAN_HOME=$HOME/.config/deadman $py $dest run # RexDeadman"
tmp=$(mktemp)
crontab -l 2>/dev/null | grep -v 'RexDeadman' | grep -v '^$' >"$tmp" || true
printf '%s\n' "$line" >>"$tmp"
crontab "$tmp"
rm -f "$tmp"
crond 2>/dev/null || true
echo "Installed $dest"
echo "Daily at 08:00 inside Termux. Allow Termux to run in the background."
echo "Check in with: deadman ping"
