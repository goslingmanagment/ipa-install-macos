#!/bin/sh
# Build IpaInstall.app — a double-clickable macOS bundle around the SwiftPM binary.
# No Xcode required (uses `swift build` + manual bundle assembly + ad-hoc codesign).
#
# Usage:  ./build_app.sh        → produces gui/IpaInstall.app
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

APP="IpaInstall"
BUNDLE="$HERE/$APP.app"
BIN="$HERE/.build/release/IpaInstallGUI"

echo "==> swift build -c release"
swift build -c release

echo "==> assembling $APP.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>IPA Install</string>
  <key>CFBundleDisplayName</key>          <string>IPA Install</string>
  <key>CFBundleIdentifier</key>           <string>com.ipainstall.gui</string>
  <key>CFBundleExecutable</key>           <string>$APP</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>CFBundleShortVersionString</key>   <string>0.1.0</string>
  <key>CFBundleVersion</key>              <string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key>       <string>13.0</string>
  <key>NSPrincipalClass</key>             <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>      <true/>
  <key>LSApplicationCategoryType</key>    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Ad-hoc sign so Gatekeeper lets it launch locally.
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> done: $BUNDLE"
echo "   open it with:  open \"$BUNDLE\""
echo "   (the app finds the project's bin/Apps/Lists by walking up from its location;"
echo "    if you move it, set IPA_INSTALL_ROOT=/path/to/ipa_install_claude)"
