#!/usr/bin/env bash
# =============================================================================
# inject.sh - Inject roscheat.dylib into RosCambo IPA & Repackage
# Usage: ./inject.sh <input_ipa> [output_ipa]
# =============================================================================
set -e

INPUT_IPA="${1:-RoS-Cambo-iOS-v6-fullscreen.ipa}"
OUTPUT_IPA="${2:-RoS-Cambo-Modded.ipa}"
DYLIB_NAME="roscheat.dylib"

if [ ! -f "$INPUT_IPA" ]; then
    echo "[-] Error: Input IPA '$INPUT_IPA' not found!"
    exit 1
fi

if [ ! -f "$DYLIB_NAME" ]; then
    echo "[-] Error: '$DYLIB_NAME' not found! Run ./build.sh first."
    exit 1
fi

echo "[*] Unpacking $INPUT_IPA..."
rm -rf tmp_ipa
mkdir -p tmp_ipa
unzip -q "$INPUT_IPA" -d tmp_ipa

APP_DIR=$(find tmp_ipa/Payload -name "*.app" -type d | head -n 1)
if [ -z "$APP_DIR" ]; then
    echo "[-] Error: Payload/*.app not found in IPA!"
    exit 1
fi

EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_DIR/Info.plist" 2>/dev/null || echo "client")
EXECUTABLE_PATH="$APP_DIR/$EXECUTABLE_NAME"

echo "[*] Target App: $APP_DIR"
echo "[*] Main Executable: $EXECUTABLE_PATH"

echo "[*] Copying $DYLIB_NAME into application bundle..."
cp "$DYLIB_NAME" "$APP_DIR/"

echo "[*] Injecting LC_LOAD_DYLIB load command..."
if which optool > /dev/null 2>&1; then
    optool install -c load -p "@executable_path/$DYLIB_NAME" -t "$EXECUTABLE_PATH"
elif which insert_dylib > /dev/null 2>&1; then
    insert_dylib --inplace "@executable_path/$DYLIB_NAME" "$EXECUTABLE_PATH"
else
    echo "[-] Error: Neither 'optool' nor 'insert_dylib' found! Please install optool."
    exit 1
fi

echo "[*] Re-signing binaries with ldid..."
if which ldid > /dev/null 2>&1; then
    ldid -S "$APP_DIR/$DYLIB_NAME"
    ldid -S "$EXECUTABLE_PATH"
fi

echo "[*] Packaging into $OUTPUT_IPA..."
cd tmp_ipa
zip -qry "../$OUTPUT_IPA" Payload/
cd ..
rm -rf tmp_ipa

echo "[+] Success! Modded IPA created at: $OUTPUT_IPA"
ls -lh "$OUTPUT_IPA"
