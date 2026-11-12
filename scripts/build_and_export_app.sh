#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="Torrent Manager"
BUNDLE_ID="com.torrentmanager.desktop"
VERSION="1.0.0"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DESTINATION_DIR="/Applications"

echo "========================================================"
echo "🔨 Building ${APP_NAME} for macOS (Release Pipeline)"
echo "========================================================"

cd "${PROJECT_DIR}"

# 1. Compile in Release Mode
echo "==> Step 1: Compiling Swift package in release mode..."
swift build -c release

RELEASE_BIN="$(swift build -c release --show-bin-path)/TorrentManager"

if [ ! -f "${RELEASE_BIN}" ]; then
    echo "❌ Error: Release binary not found at ${RELEASE_BIN}"
    exit 1
fi

echo "✅ Compiled binary: ${RELEASE_BIN}"

# 2. Prepare App Bundle Structure
echo "==> Step 2: Assembling macOS App Bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 3. Copy Executable & Icon
cp "${RELEASE_BIN}" "${APP_BUNDLE}/Contents/MacOS/TorrentManager"
chmod +x "${APP_BUNDLE}/Contents/MacOS/TorrentManager"

if [ -f "${PROJECT_DIR}/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# 4. Generate Info.plist
cat << EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TorrentManager</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>BitTorrent Magnet URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>magnet</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>BitTorrent File</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>torrent</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
        </dict>
    </array>
</dict>
</plist>
EOF

# 5. Write PkgInfo
printf "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# 6. Ad-hoc code signing for local macOS gatekeeper compatibility
echo "==> Step 3: Ad-hoc signing the application bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# 7. Export / Install to Applications Folder
echo "==> Step 4: Exporting to ${DESTINATION_DIR}..."
TARGET_APP="${DESTINATION_DIR}/${APP_NAME}.app"

if [ -w "${DESTINATION_DIR}" ]; then
    rm -rf "${TARGET_APP}"
    cp -R "${APP_BUNDLE}" "${DESTINATION_DIR}/"
    echo "✅ Successfully installed: ${TARGET_APP}"
else
    # Fallback to User Applications folder if root /Applications is restricted
    USER_APP_DIR="${HOME}/Applications"
    mkdir -p "${USER_APP_DIR}"
    USER_TARGET="${USER_APP_DIR}/${APP_NAME}.app"
    rm -rf "${USER_TARGET}"
    cp -R "${APP_BUNDLE}" "${USER_APP_DIR}/"
    echo "✅ Successfully installed to user folder: ${USER_TARGET}"
fi

echo "========================================================"
echo "🎉 Build and export completed successfully!"
echo "   App is located at: ${TARGET_APP}"
echo "========================================================"

