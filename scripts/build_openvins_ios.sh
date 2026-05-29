#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENVINS_DIR="$ROOT_DIR/third_party/open_vins"
BUILD_DIR="$ROOT_DIR/build/openvins-ios"
INSTALL_DIR="$ROOT_DIR/Vendor/OpenVINS"

PLATFORM="${PLATFORM:-OS64}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-17.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
SDK="${SDK:-iphoneos}"
ARCHS="${ARCHS:-arm64}"
CC="$(xcrun --sdk "$SDK" --find clang)"
CXX="$(xcrun --sdk "$SDK" --find clang++)"
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
GENERATOR="${GENERATOR:-Ninja}"
CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required" >&2
  exit 1
fi

if [ ! -d "$OPENVINS_DIR/ov_msckf" ]; then
  echo "error: OpenVINS submodule is missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi

echo "Building OpenVINS for iOS"
echo "  platform: $PLATFORM"
echo "  sdk: $SDK"
echo "  archs: $ARCHS"
echo "  deployment target: $DEPLOYMENT_TARGET"
echo "  build type: $BUILD_TYPE"
echo "  install dir: $INSTALL_DIR"
if [ -n "$CMAKE_PREFIX_PATH" ]; then
  echo "  dependency prefixes: $CMAKE_PREFIX_PATH"
fi

cmake -S "$OPENVINS_DIR/ov_msckf" \
  -B "$BUILD_DIR/$PLATFORM" \
  -G "$GENERATOR" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/$PLATFORM" \
  -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DENABLE_ROS=OFF \
  -DENABLE_ARUCO_TAGS=OFF \
  -DDISABLE_MATPLOTLIB=ON

cmake --build "$BUILD_DIR/$PLATFORM" --config "$BUILD_TYPE" --target ov_msckf_lib
cmake --install "$BUILD_DIR/$PLATFORM" --config "$BUILD_TYPE"

cat <<EOF

OpenVINS iOS build finished.

Next integration step:
  1. Build dependency slices for Eigen/OpenCV/Boost/Ceres if CMake cannot find them.
  2. Package device/simulator outputs into an XCFramework.
  3. Link the XCFramework into the app target and replace the current bridge stub.
EOF
