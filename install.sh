#!/usr/bin/env bash
# Install cc-clocker by copying the app (bin/ + lib/) to a stable, non-TCC
# location and symlinking the entrypoint into ~/.local/bin.
#
# Why copy instead of symlink the source tree:
#   On macOS, launchd-spawned bash cannot read scripts under TCC-protected
#   directories like ~/Desktop, ~/Documents, ~/Downloads. A symlink target
#   inside one of those paths fails with "Operation not permitted" at load
#   time. Copying to ~/.cc-clocker/app sidesteps this entirely.
#
# Re-run this script after any edit to bin/ or lib/ to refresh the install.
#
# Env overrides:
#   PREFIX     where the cc-clocker symlink lives (default: ~/.local/bin)
#   APP_DIR    where the app is copied (default: ~/.cc-clocker/app)

set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${PREFIX:-$HOME/.local/bin}"
APP_DIR="${APP_DIR:-$HOME/.cc-clocker/app}"

mkdir -p "$TARGET_DIR" "$APP_DIR"

# Copy app payload (bin + lib only). Tests, docs, fixtures, contrib stay in
# the source tree.
rm -rf "${APP_DIR:?}/bin" "${APP_DIR:?}/lib"
cp -R "$SOURCE_ROOT/bin" "$APP_DIR/bin"
cp -R "$SOURCE_ROOT/lib" "$APP_DIR/lib"
chmod +x "$APP_DIR/bin/cc-clocker"

ln -sf "$APP_DIR/bin/cc-clocker" "$TARGET_DIR/cc-clocker"

# Render the launchd plist from the template, substituting env-driven values.
# Anchors and delay are optional — empty placeholders are stripped from the
# rendered plist so launchd doesn't pass empty env vars.
PLIST_TEMPLATE="$SOURCE_ROOT/contrib/launchd/com.github.ezoushen.cc-clocker.plist.template"
PLIST_RENDERED="$APP_DIR/com.github.ezoushen.cc-clocker.plist"
if [ -f "$PLIST_TEMPLATE" ]; then
    sed \
        -e "s|__CC_CLOCKER_5H_ANCHOR__|${CC_CLOCKER_5H_ANCHOR:-}|g" \
        -e "s|__CC_CLOCKER_7D_ANCHOR__|${CC_CLOCKER_7D_ANCHOR:-}|g" \
        -e "s|__CC_CLOCKER_PING_DELAY_SECONDS__|${CC_CLOCKER_PING_DELAY_SECONDS:-30}|g" \
        "$PLIST_TEMPLATE" > "$PLIST_RENDERED"
fi

echo "installed:"
echo "  app:    $APP_DIR"
echo "  link:   $TARGET_DIR/cc-clocker -> $APP_DIR/bin/cc-clocker"
echo "  plist:  $PLIST_RENDERED"

cat <<EOF

Autostart options:

  macOS (launchd):
    cp $PLIST_RENDERED ~/Library/LaunchAgents/
    launchctl load ~/Library/LaunchAgents/com.github.ezoushen.cc-clocker.plist

  Linux (systemd --user):
    mkdir -p ~/.config/systemd/user
    cp $SOURCE_ROOT/contrib/systemd/cc-clocker.service ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now cc-clocker

  Universal:
    nohup cc-clocker run >/tmp/cc-clocker.log 2>&1 &
EOF
