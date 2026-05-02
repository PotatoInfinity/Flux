import os
import subprocess
import time
import shutil

def run(cmd):
    print(f"Executing: {cmd}")
    subprocess.run(cmd, shell=True, check=True)

# Build configurations
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
BUILD_DIR = os.path.join(PROJECT_ROOT, "build_temp")
APP_NAME = "Flux"
APP_BUNDLE = f"{APP_NAME}.app"
FINAL_APP_PATH = os.path.expanduser(f'/Applications/{APP_BUNDLE}')
DMG_NAME = f"{APP_NAME}_Universal.dmg"

# Ensure clean build directory
if os.path.exists(BUILD_DIR):
    shutil.rmtree(BUILD_DIR)
os.makedirs(f"{BUILD_DIR}/{APP_BUNDLE}/Contents/MacOS", exist_ok=True)
os.makedirs(f"{BUILD_DIR}/{APP_BUNDLE}/Contents/Resources", exist_ok=True)
os.makedirs(f"{BUILD_DIR}/{APP_BUNDLE}/Contents/PlugIns/FluxFinder.appex/Contents/MacOS", exist_ok=True)

res_path = f"{BUILD_DIR}/{APP_BUNDLE}/Contents/Resources"
plugins_path = f"{BUILD_DIR}/{APP_BUNDLE}/Contents/PlugIns/FluxFinder.appex"

# 1. Generate Icon using a temporary Swift script
icon_script = '''
import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0).setFill()
NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 220, yRadius: 220).fill()

if let symbol = NSImage(systemSymbolName: "rectangle.grid.2x2.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 600, weight: .regular)
    let configuredSymbol = symbol.withSymbolConfiguration(config)!
    configuredSymbol.isTemplate = true
    NSColor.white.set()
    let drawRect = NSRect(x: 212, y: 212, width: 600, height: 600)
    configuredSymbol.draw(in: drawRect)
}

image.unlockFocus()

if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "icon_1024.png"))
}
'''
with open('gen_icon.swift', 'w') as f:
    f.write(icon_script)

print("Generating App Icon...")
run('swift gen_icon.swift')
os.remove('gen_icon.swift')

# Create .icns
os.makedirs('AppIcon.iconset', exist_ok=True)
sizes = [16, 32, 64, 128, 256, 512]
for s in sizes:
    run(f'sips -z {s} {s} icon_1024.png --out AppIcon.iconset/icon_{s}x{s}.png > /dev/null')
    s2 = s * 2
    run(f'sips -z {s2} {s2} icon_1024.png --out AppIcon.iconset/icon_{s}x{s}@2x.png > /dev/null')

run('iconutil -c icns AppIcon.iconset')
run(f'mv AppIcon.icns {res_path}/AppIcon.icns')
os.remove('icon_1024.png')
shutil.rmtree('AppIcon.iconset')

print("Compiling Swift (Universal Binary)...")
archs = ["arm64", "x86_64"]
for arch in archs:
    print(f"  Compiling for {arch}...")
    # Compile Main App
    run(f'swiftc -parse-as-library -target {arch}-apple-macos13.0 -O {PROJECT_ROOT}/FluxApp.swift -o {BUILD_DIR}/Flux_{arch}')
    # Compile Finder Extension
    run(f'swiftc -target {arch}-apple-macos13.0 -O {PROJECT_ROOT}/FinderExtension.swift -o {BUILD_DIR}/FluxFinder_{arch} -Xlinker -bundle')

# Combine into Universal Binaries
print("Merging into Universal Binaries...")
run(f'lipo -create {BUILD_DIR}/Flux_arm64 {BUILD_DIR}/Flux_x86_64 -output {BUILD_DIR}/{APP_BUNDLE}/Contents/MacOS/Flux')
run(f'lipo -create {BUILD_DIR}/FluxFinder_arm64 {BUILD_DIR}/FluxFinder_x86_64 -output {plugins_path}/Contents/MacOS/FluxFinder')

# Cleanup temp arch binaries
for arch in archs:
    os.remove(f'{BUILD_DIR}/Flux_{arch}')
    os.remove(f'{BUILD_DIR}/FluxFinder_{arch}')

# 2. Copy Resources
print("Copying Resources...")
run(f'mkdir -p {res_path}/Icons')
run(f'cp {PROJECT_ROOT}/Resources/Icons/*.svg {res_path}/Icons/')

print("Writing Property Lists...")
# 3. Create Info.plist for App
with open(f'{BUILD_DIR}/{APP_BUNDLE}/Contents/Info.plist', 'w') as f:
    f.write('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.flux.ui</string>
    <key>CFBundleExecutable</key><string>Flux</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>''')

# 4. Create Info.plist for Extension
with open(f'{plugins_path}/Contents/Info.plist', 'w') as f:
    f.write('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.flux.ui.finder</string>
    <key>CFBundleExecutable</key><string>FluxFinder</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key><string>FluxFinder.FinderSync</string>
    </dict>
</dict>
</plist>''')

print("Signing Binaries...")
# 5. Sign
run(f'codesign -f -s "-" {plugins_path}')
run(f'codesign -f -s "-" {BUILD_DIR}/{APP_BUNDLE}')

print("Creating DMG...")
# Create a folder for the DMG content
dmg_src = os.path.join(BUILD_DIR, "dmg_root")
os.makedirs(dmg_src, exist_ok=True)
run(f'cp -R {BUILD_DIR}/{APP_BUNDLE} {dmg_src}/')
run(f'ln -s /Applications {dmg_src}/Applications')

# Remove existing DMG if it exists
if os.path.exists(DMG_NAME):
    os.remove(DMG_NAME)

run(f'hdiutil create -volname "{APP_NAME}" -srcfolder {dmg_src} -ov -format UDZO {DMG_NAME}')

print(f"Installing to /Applications...")
run(f'rm -rf {FINAL_APP_PATH}')
run(f'cp -R {BUILD_DIR}/{APP_BUNDLE} {FINAL_APP_PATH}')

# Cleanup
shutil.rmtree(BUILD_DIR)

print(f"\nBuild complete!")
print(f"Universal App: {FINAL_APP_PATH}")
print(f"Disk Image: {os.path.join(PROJECT_ROOT, DMG_NAME)}")

print("\nLaunching App...")
run('killall Flux || true')
time.sleep(1)
run(f'open {FINAL_APP_PATH}')
