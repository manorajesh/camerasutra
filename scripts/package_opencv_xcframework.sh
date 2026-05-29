#!/usr/bin/env bash
# Packages the two platform slices built by build_opencv_ios.sh into
# Vendor/opencv2.xcframework, then injects stub headers for display-only
# OpenCV modules (highgui, imgcodecs where missing) that OpenVINS headers
# include but the iOS build does not need at runtime.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/opencv-ios"
VENDOR_DIR="$ROOT_DIR/Vendor"
OUTPUT="$VENDOR_DIR/opencv2.xcframework"

DEVICE_LIB="$BUILD_DIR/OS64/libopencv.a"
DEVICE_HEADERS="$VENDOR_DIR/opencv-ios/OS64/include/opencv4"
SIM_LIB="$BUILD_DIR/SIMULATORARM64/libopencv.a"
SIM_HEADERS="$VENDOR_DIR/opencv-ios/SIMULATORARM64/include/opencv4"

for path in "$DEVICE_LIB" "$DEVICE_HEADERS" "$SIM_LIB" "$SIM_HEADERS"; do
  if [ ! -e "$path" ]; then
    echo "error: missing OpenCV build output: $path" >&2
    echo "Run scripts/build_opencv_ios.sh for OS64 and SIMULATORARM64 first." >&2
    exit 1
  fi
done

rm -rf "$OUTPUT"

xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" \
  -headers "$DEVICE_HEADERS" \
  -library "$SIM_LIB" \
  -headers "$SIM_HEADERS" \
  -output "$OUTPUT"

# ── Inject stubs for display-only modules ────────────────────────────────────
# highgui is not built for iOS; OpenVINS headers reference it for debug display
# functions that are never called from the production bridge path. Inject no-op
# stubs into each xcframework slice so the bridge file compiles cleanly.

HIGHGUI_STUB=$(cat << 'HIGHGUI'
// highgui stub for iOS — display functions are no-ops on this platform.
#pragma once
#include <opencv2/core.hpp>
#include <string>
namespace cv {
    inline void imshow(const std::string &, InputArray) {}
    inline int waitKey(int = 0) { return -1; }
    inline void namedWindow(const std::string &, int = 1) {}
    inline void destroyWindow(const std::string &) {}
    inline void destroyAllWindows() {}
}
HIGHGUI
)

OPENCV_HPP=$(cat << 'OVHPP'
// Minimal opencv.hpp for iOS VIO — only the modules built for this target.
#pragma once
#include "opencv2/core.hpp"
#include "opencv2/imgproc.hpp"
#include "opencv2/features2d.hpp"
#include "opencv2/video.hpp"
#include "opencv2/calib3d.hpp"
#include "opencv2/flann.hpp"
#include "opencv2/imgcodecs.hpp"
#include "opencv2/highgui/highgui.hpp"
OVHPP
)

for SLICE_DIR in "$OUTPUT"/*/Headers; do
  CV="$SLICE_DIR/opencv2"
  mkdir -p "$CV/highgui"
  printf '%s\n' "$HIGHGUI_STUB" > "$CV/highgui/highgui.hpp"
  printf '#pragma once\n#include "opencv2/highgui/highgui.hpp"\n' > "$CV/highgui.hpp"
  printf '%s\n' "$OPENCV_HPP" > "$CV/opencv.hpp"
done

echo ""
echo "opencv2.xcframework created:"
echo "  $OUTPUT"
