#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Seek"
BUNDLE_ID="com.local.Seek"
APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"
SKIP_INSTALL=false
PACKAGE_RELEASE=false

for arg in "$@"; do
    case "$arg" in
        --skip-install) SKIP_INSTALL=true ;;
        --package) PACKAGE_RELEASE=true ;;
    esac
done

echo "🔨 Building ${APP_NAME} Universal binary (arm64 + x86_64)..."
cd "${PROJECT_DIR}"
swift build -c release --arch arm64
swift build -c release --arch x86_64

ARM64_BIN="${PROJECT_DIR}/.build/arm64-apple-macosx/release/${APP_NAME}"
X86_BIN="${PROJECT_DIR}/.build/x86_64-apple-macosx/release/${APP_NAME}"
HOST_ARCH="$(uname -m)"
TEST_BIN="${ARM64_BIN}"
if [ "${HOST_ARCH}" = "x86_64" ]; then
    TEST_BIN="${X86_BIN}"
fi

echo "🧪 Running automated ${APP_NAME} QA & self-test suite..."
"${TEST_BIN}" --self-test

echo "📦 Assembling ${APP_NAME}.app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

lipo -create -output "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" "${ARM64_BIN}" "${X86_BIN}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

if [ -f "${PROJECT_DIR}/Assets/LogoKit/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Assets/LogoKit/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    cp "${PROJECT_DIR}/Assets/LogoKit/MenuBarTemplate.png" "${APP_BUNDLE}/Contents/Resources/MenuBarTemplate.png"
    cp "${PROJECT_DIR}/Assets/LogoKit/MenuBarTemplate@2x.png" "${APP_BUNDLE}/Contents/Resources/MenuBarTemplate@2x.png"
fi

cat << EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
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
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Seek optionally uses Accessibility permissions to find and switch directly to your open app windows.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Seek optionally uses Automation for Dark Mode toggle, Finder editor launch, and clean browser URL copy.</string>
</dict>
</plist>
EOF

SIGN_IDENTITY="${SEEK_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Development|Seek Local|WindowWheel Local" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi

if [ -n "${SIGN_IDENTITY}" ]; then
    echo "✍️ Code signing ${APP_NAME}.app with identity: ${SIGN_IDENTITY}"
    codesign --force --deep --sign "${SIGN_IDENTITY}" --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"
else
    echo "✍️ Ad-hoc code signing ${APP_NAME}.app..."
    codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"
fi

if [ "${SKIP_INSTALL}" = false ]; then
    echo "📲 Installing ${APP_NAME}.app to ${INSTALL_PATH}..."
    rm -rf "${INSTALL_PATH}"
    cp -R "${APP_BUNDLE}" "${INSTALL_PATH}"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALL_PATH}" || true
fi

if [ "${PACKAGE_RELEASE}" = true ]; then
    echo "🗜️  Packaging ${APP_NAME}-macOS-Universal.zip and ${APP_NAME}-macOS-Universal.dmg..."
    ZIP_PATH="${PROJECT_DIR}/${APP_NAME}-macOS-Universal.zip"
    DMG_PATH="${PROJECT_DIR}/${APP_NAME}-macOS-Universal.dmg"
    DMG_STAGE="$(mktemp -d)"
    rm -f "${ZIP_PATH}" "${DMG_PATH}"
    ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
    cp -R "${APP_BUNDLE}" "${DMG_STAGE}/${APP_NAME}.app"
    ln -s /Applications "${DMG_STAGE}/Applications"
    hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DMG_PATH}" >/dev/null
    rm -rf "${DMG_STAGE}"
fi

echo "✅ Successfully created: ${APP_BUNDLE}"
if [ "${SKIP_INSTALL}" = false ]; then
    echo "✅ Installed to: ${INSTALL_PATH}"
    echo "🚀 To run it, execute:"
    echo "   open ${INSTALL_PATH}"
fi
