#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/OpenVINS"
OUTPUT="$VENDOR_DIR/OpenVINS.xcframework"

DEVICE_LIB="$VENDOR_DIR/OS64/lib/libov_msckf_lib.a"
DEVICE_HEADERS="$VENDOR_DIR/OS64/include"
SIM_LIB="$VENDOR_DIR/SIMULATORARM64/lib/libov_msckf_lib.a"
SIM_HEADERS="$VENDOR_DIR/SIMULATORARM64/include"

for path in "$DEVICE_LIB" "$DEVICE_HEADERS" "$SIM_LIB" "$SIM_HEADERS"; do
  if [ ! -e "$path" ]; then
    echo "error: missing OpenVINS build output: $path" >&2
    echo "Run scripts/build_openvins_ios.sh for OS64 and SIMULATORARM64 first." >&2
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

cat <<EOF

OpenVINS XCFramework created:
  $OUTPUT

This framework contains OpenVINS only. The app target still needs matching
iOS/simulator slices for OpenCV, Boost, Ceres, SuiteSparse, glog, and gflags
before the real OpenVINS bridge can be linked.
EOF
