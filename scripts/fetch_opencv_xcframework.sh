#!/usr/bin/env bash
# Downloads the official OpenCV iOS fat-framework from GitHub releases and
# repackages it as Vendor/opencv2.xcframework.
#
# NOTE: The official ios-framework zip does not include an arm64-simulator slice.
# If you need arm64-simulator support (Apple Silicon Macs / modern CI), use
# scripts/build_opencv_ios.sh + scripts/package_opencv_xcframework.sh instead.
# This script is retained as a faster fallback for Intel-based runners.
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-4.10.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
OUTPUT="$VENDOR_DIR/opencv2.xcframework"

if [ -d "$OUTPUT" ]; then
  echo "opencv2.xcframework already present at $OUTPUT — skipping download."
  echo "Remove it and re-run this script to refresh."
  exit 0
fi

DOWNLOAD_URL="https://github.com/opencv/opencv/releases/download/${OPENCV_VERSION}/opencv-${OPENCV_VERSION}-ios-framework.zip"
ARCHIVE="$VENDOR_DIR/opencv-ios-framework.zip"

mkdir -p "$VENDOR_DIR"
echo "Downloading OpenCV ${OPENCV_VERSION} iOS framework..."
echo "  from: $DOWNLOAD_URL"
curl -L --progress-bar -o "$ARCHIVE" "$DOWNLOAD_URL"

echo "Extracting..."
EXTRACT_DIR="$VENDOR_DIR/_opencv_extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
unzip -q "$ARCHIVE" -d "$EXTRACT_DIR"
rm -f "$ARCHIVE"

# The zip may contain either opencv2.xcframework directly or opencv2.framework
# (the older fat-framework format). Handle both.
if [ -d "$EXTRACT_DIR/opencv2.xcframework" ]; then
  mv "$EXTRACT_DIR/opencv2.xcframework" "$OUTPUT"
elif [ -d "$EXTRACT_DIR/opencv2.framework" ]; then
  # Older fat framework (pre-xcframework era). Wrap it into an xcframework
  # covering arm64 device + x86_64 simulator (Intel only — no arm64-simulator
  # slice; see comment at top of file).
  FRAMEWORK_SRC="$EXTRACT_DIR/opencv2.framework"
  # Resolve the actual binary (may be a symlink through Versions/A/)
  FAT=$(find "$FRAMEWORK_SRC" -maxdepth 3 \
    -name "opencv2" -not -type d -not -type l | head -1)
  if [ -z "$FAT" ]; then
    FAT=$(find "$FRAMEWORK_SRC" -maxdepth 3 -name "opencv2" -type l | head -1)
  fi

  DEVICE_DIR="$EXTRACT_DIR/device/opencv2.framework"
  SIM_DIR="$EXTRACT_DIR/simulator/opencv2.framework"
  mkdir -p "$DEVICE_DIR" "$SIM_DIR"

  # Copy headers and resources (not the fat binary)
  for item in "$FRAMEWORK_SRC"/Headers "$FRAMEWORK_SRC"/Modules \
              "$FRAMEWORK_SRC"/Resources "$FRAMEWORK_SRC"/Info.plist; do
    [ -e "$item" ] && cp -R "$item" "$DEVICE_DIR/" && cp -R "$item" "$SIM_DIR/"
  done

  lipo "$FAT" -thin arm64 -output "$DEVICE_DIR/opencv2"
  lipo "$FAT" -thin x86_64 -output "$SIM_DIR/opencv2" 2>/dev/null \
    || lipo "$FAT" -thin arm64 -output "$SIM_DIR/opencv2"

  xcodebuild -create-xcframework \
    -framework "$DEVICE_DIR" \
    -framework "$SIM_DIR" \
    -output "$OUTPUT"
else
  echo "error: unexpected archive contents — could not locate opencv2.xcframework or opencv2.framework" >&2
  ls "$EXTRACT_DIR"
  rm -rf "$EXTRACT_DIR"
  exit 1
fi

rm -rf "$EXTRACT_DIR"

echo ""
echo "OpenCV ${OPENCV_VERSION} XCFramework ready at:"
echo "  $OUTPUT"
