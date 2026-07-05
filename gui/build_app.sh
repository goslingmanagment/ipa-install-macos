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

# Bundle the download engine + offline catalog so the .app works standalone
# (outside the repo it stores data in ~/Library/Application Support/IpaInstall
# and downloads into ~/Downloads/IPA). ideviceinstaller stays a Homebrew dep.
cp "$HERE/../bin/ipatool" "$BUNDLE/Contents/Resources/ipatool"
cp "$HERE/../assets/Apps_ID_List.txt" "$BUNDLE/Contents/Resources/Apps_ID_List.txt"

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

# Ad-hoc sign so Gatekeeper lets it launch locally (nested binary first).
codesign --force --sign - "$BUNDLE/Contents/Resources/ipatool" >/dev/null 2>&1 || echo "   (codesign ipatool skipped)"
codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> done: $BUNDLE"
echo "   open it with:  open \"$BUNDLE\""
echo "   (inside the repo the app shares the project's bin/Apps/Lists; moved elsewhere"
echo "    it runs standalone: bundled ipatool, data in ~/Library/Application Support/IpaInstall,"
echo "    downloads in ~/Downloads/IPA. Override with IPA_INSTALL_ROOT=/path/to/repo.)"
