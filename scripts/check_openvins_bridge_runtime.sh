#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${SDK:-iphonesimulator}"
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"

cd "$ROOT_DIR"

# Resolve Eigen headers: prefer vendored copy, fall back to Homebrew.
EIGEN_INCLUDE=""
if [ -d "$ROOT_DIR/third_party/eigen/Eigen" ]; then
  EIGEN_INCLUDE="$ROOT_DIR/third_party/eigen"
elif [ -d "/opt/homebrew/opt/eigen/include/eigen3/Eigen" ]; then
  EIGEN_INCLUDE="/opt/homebrew/opt/eigen/include/eigen3"
else
  echo "error: Eigen headers not found. Run scripts/fetch_eigen.sh or install via Homebrew." >&2
  exit 1
fi

# Resolve OpenCV headers: prefer vendored xcframework, fall back to Homebrew.
OPENCV_INCLUDE=""
if [ -d "$ROOT_DIR/Vendor/opencv2.xcframework/ios-arm64-simulator/Headers" ]; then
  OPENCV_INCLUDE="$ROOT_DIR/Vendor/opencv2.xcframework/ios-arm64-simulator/Headers"
elif [ -d "$ROOT_DIR/Vendor/opencv-ios/SIMULATORARM64/include/opencv4" ]; then
  OPENCV_INCLUDE="$ROOT_DIR/Vendor/opencv-ios/SIMULATORARM64/include/opencv4"
elif [ -d "/opt/homebrew/opt/opencv/include/opencv4" ]; then
  OPENCV_INCLUDE="/opt/homebrew/opt/opencv/include/opencv4"
else
  echo "warning: OpenCV headers not found; bridge may fail to parse." >&2
fi

OPENCV_FLAGS=()
[ -n "$OPENCV_INCLUDE" ] && OPENCV_FLAGS+=("-I$OPENCV_INCLUDE")

xcrun --sdk "$SDK" clang++ \
  -fobjc-arc \
  -fsyntax-only \
  -std=gnu++20 \
  -x objective-c++ \
  -DCAMERASUTRA_ENABLE_OPENVINS_RUNTIME=1 \
  -Ithird_party/open_vins/ov_msckf/src \
  -Ithird_party/open_vins/ov_core/src \
  -Ithird_party/open_vins/ov_init/src \
  -IVendor/OpenVINS/SIMULATORARM64/include/open_vins \
  -I"$EIGEN_INCLUDE" \
  "${OPENCV_FLAGS[@]}" \
  -I/opt/homebrew/opt/boost/include \
  -I/opt/homebrew/opt/ceres-solver/include \
  -I/opt/homebrew/opt/glog/include \
  -I/opt/homebrew/opt/gflags/include \
  -I/opt/homebrew/opt/suite-sparse/include/suitesparse \
  -isysroot "$SDK_PATH" \
  camerasutra/VIO/OpenVINSBridge.mm
