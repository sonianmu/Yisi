#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Yisi"
BUNDLE_ID="com.sonianmu.yisi"
# Auto-detect version from latest git tag (strips leading "v")
if [ -z "${VERSION:-}" ]; then
    GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    VERSION="${GIT_TAG#v}"
fi
if [ -z "${VERSION}" ]; then
    echo "ERROR: No VERSION set and no git tag found. Usage: VERSION=x.y.z bash $0"
    exit 1
fi
echo "Building ${APP_NAME} v${VERSION}"
BUILD_DIR="build-app/Release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

# Clean previous build artifacts
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# === Icon Generation Phase ===
echo "Generating app icon..."
swift scripts/generate_icon.swift
if [ ! -f "icon_1024x1024.png" ]; then
  echo "ERROR: icon_1024x1024.png not found. Aborting."
  exit 1
fi

mkdir -p AppIcon.iconset
sips -z 16 16     icon_1024x1024.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     icon_1024x1024.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     icon_1024x1024.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     icon_1024x1024.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   icon_1024x1024.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   icon_1024x1024.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   icon_1024x1024.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   icon_1024x1024.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   icon_1024x1024.png --out AppIcon.iconset/icon_512x512.png
cp icon_1024x1024.png AppIcon.iconset/icon_512x512@2x.png

iconutil -c icns AppIcon.iconset -o AppIcon.icns
cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Cleanup icon build artifacts
rm -rf AppIcon.iconset icon_1024x1024.png AppIcon.icns
echo "App icon generated successfully."

# Build Universal Binary (arm64 + x86_64)
echo "Building arm64..."
swift build -c release --arch arm64
ARM64_BIN="${BUILD_DIR}/${APP_NAME}-arm64"
# Some SwiftPM build systems reuse the same product directory for both architectures.
cp "$(swift build -c release --arch arm64 --show-bin-path)/${APP_NAME}" "${ARM64_BIN}"

echo "Building x86_64..."
swift build -c release --arch x86_64
X86_BIN="${BUILD_DIR}/${APP_NAME}-x86_64"
cp "$(swift build -c release --arch x86_64 --show-bin-path)/${APP_NAME}" "${X86_BIN}"

echo "Creating Universal Binary..."
lipo -create -output "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" "${ARM64_BIN}" "${X86_BIN}"
lipo "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" -verify_arch arm64
lipo "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" -verify_arch x86_64
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Ad-hoc code sign the universal binary
# Ad-hoc signatures are not stable across builds; macOS may require renewed authorization.
codesign --force -s - "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Generate Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# === DMG Background Generation ===
echo "Generating DMG background..."
SWIFT_GEN_SCRIPT="${BUILD_DIR}/generate_dmg_background.swift"
mkdir -p "${BUILD_DIR}"

cat > "${SWIFT_GEN_SCRIPT}" <<SWIFT
import Cocoa

let width: CGFloat = 480
let height: CGFloat = 292

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// Background: warm off-white gradient
let topColor = CGColor(red: 0.965, green: 0.957, blue: 0.949, alpha: 1.0)
let bottomColor = CGColor(red: 0.933, green: 0.925, blue: 0.918, alpha: 1.0)
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [topColor, bottomColor] as CFArray,
    locations: [0.0, 1.0]
)!
cg.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: height),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// HarmonicFlow bars: 3 horizontal lines between icon positions
// Icons will be at roughly x=120 and x=360, centered at y=160
// Bars sit between them (x: 195 to 285), stacked vertically near center
let barColor = NSColor(calibratedRed: 0.72, green: 0.74, blue: 0.76, alpha: 0.35)
barColor.setFill()

let barHeight: CGFloat = 3.0
let barGap: CGFloat = 6.0
let barX: CGFloat = 195.0
let centerY: CGFloat = 160.0

// 3 bars with decreasing widths (matching menu bar icon proportions: 14, 9, 5 -> scaled)
let barWidths: [CGFloat] = [90, 58, 36]
let totalHeight = CGFloat(barWidths.count) * barHeight + CGFloat(barWidths.count - 1) * barGap
let startY = centerY + totalHeight / 2.0

for (i, w) in barWidths.enumerated() {
    let y = startY - CGFloat(i) * (barHeight + barGap)
    let rect = NSRect(x: barX, y: y, width: w, height: barHeight)
    let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
    path.fill()
}

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
let url = URL(fileURLWithPath: "dmg_background.png")
try! data.write(to: url)
SWIFT

swift "${SWIFT_GEN_SCRIPT}"
rm -f "${SWIFT_GEN_SCRIPT}"

# Stage DMG contents (app + Applications symlink)
DMG_STAGE="${BUILD_DIR}/dmg_stage"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}/.background"

# Sign the complete app bundle (after all resources are in place)
codesign --force --deep -s - "${APP_BUNDLE}"
plutil -lint "${APP_BUNDLE}/Contents/Info.plist"
codesign --verify --deep --strict "${APP_BUNDLE}"
echo "App bundle signed and verified (ad-hoc)."

cp -R "${APP_BUNDLE}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"
mv dmg_background.png "${DMG_STAGE}/.background/background.png"

# Create temporary read-write DMG
DMG_TEMP="${BUILD_DIR}/${APP_NAME}_temp.dmg"
rm -f "${DMG_TEMP}" "${APP_NAME}.dmg"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGE}" -ov -format UDRW -fs HFS+ "${DMG_TEMP}"

# Mount read-write DMG
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_TEMP}" | head -1 | awk '{print $1}')
MOUNT_DIR="/Volumes/${APP_NAME}"
echo "Mounted device ${DEVICE} at ${MOUNT_DIR}"

sleep 2

# Style the DMG window via AppleScript
osascript <<APPLESCRIPT || echo "Warning: AppleScript styling partially failed, continuing..."
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {300, 200, 780, 520}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        set position of item "${APP_NAME}.app" of container window to {120, 132}
        set position of item "Applications" of container window to {360, 132}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 2
hdiutil detach "${DEVICE}" -quiet || hdiutil detach "${DEVICE}" -force

# Convert to compressed read-only DMG
hdiutil convert "${DMG_TEMP}" -format UDZO -o "${APP_NAME}.dmg"
rm -f "${DMG_TEMP}"

echo "Build complete: ${APP_NAME}.dmg"
