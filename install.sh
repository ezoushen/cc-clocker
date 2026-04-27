#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${PREFIX:-$HOME/.local/bin}"
mkdir -p "$TARGET_DIR"

ln -sf "$PROJECT_ROOT/bin/cc-clocker" "$TARGET_DIR/cc-clocker"
echo "installed: $TARGET_DIR/cc-clocker -> $PROJECT_ROOT/bin/cc-clocker"

cat <<EOF

Autostart options:

  macOS (launchd):
    cp $PROJECT_ROOT/contrib/launchd/com.ezou.cc-clocker.plist ~/Library/LaunchAgents/
    launchctl load ~/Library/LaunchAgents/com.ezou.cc-clocker.plist

  Linux (systemd --user):
    mkdir -p ~/.config/systemd/user
    cp $PROJECT_ROOT/contrib/systemd/cc-clocker.service ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now cc-clocker

  Universal:
    nohup cc-clocker run >/tmp/cc-clocker.log 2>&1 &
EOF
