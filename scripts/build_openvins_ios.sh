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

if [ -z "$CMAKE_PREFIX_PATH" ] && command -v brew >/dev/null 2>&1; then
  prefixes=()
  for formula in eigen opencv boost ceres-solver metis suite-sparse; do
    if prefix="$(brew --prefix "$formula" 2>/dev/null)"; then
      prefixes+=("$prefix")
    fi
  done
  if [ "${#prefixes[@]}" -gt 0 ]; then
    CMAKE_PREFIX_PATH="$(IFS=';'; echo "${prefixes[*]}")"
  fi
fi

EIGEN3_DIR="${EIGEN3_DIR:-}"
OPENCV_DIR="${OPENCV_DIR:-}"
CERES_DIR="${CERES_DIR:-}"
SUITESPARSE_DIR="${SUITESPARSE_DIR:-}"
METIS_INCLUDE_DIR="${METIS_INCLUDE_DIR:-}"
METIS_LIBRARY="${METIS_LIBRARY:-}"

if [ -z "$EIGEN3_DIR" ] && [ -d "/opt/homebrew/opt/eigen/share/eigen3/cmake" ]; then
  EIGEN3_DIR="/opt/homebrew/opt/eigen/share/eigen3/cmake"
fi
if [ -z "$OPENCV_DIR" ] && [ -d "/opt/homebrew/opt/opencv/lib/cmake/opencv4" ]; then
  OPENCV_DIR="/opt/homebrew/opt/opencv/lib/cmake/opencv4"
fi
if [ -z "$CERES_DIR" ] && [ -d "/opt/homebrew/opt/ceres-solver/lib/cmake/Ceres" ]; then
  CERES_DIR="/opt/homebrew/opt/ceres-solver/lib/cmake/Ceres"
fi
if [ -z "$SUITESPARSE_DIR" ] && [ -d "/opt/homebrew/opt/suite-sparse/lib/cmake/SuiteSparse" ]; then
  SUITESPARSE_DIR="/opt/homebrew/opt/suite-sparse/lib/cmake/SuiteSparse"
fi
if [ -z "$METIS_INCLUDE_DIR" ] && [ -f "/opt/homebrew/opt/metis/include/metis.h" ]; then
  METIS_INCLUDE_DIR="/opt/homebrew/opt/metis/include"
fi
if [ -z "$METIS_LIBRARY" ] && [ -f "/opt/homebrew/opt/metis/lib/libmetis.dylib" ]; then
  METIS_LIBRARY="/opt/homebrew/opt/metis/lib/libmetis.dylib"
fi

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
  -DCMAKE_CXX_FLAGS="-include cassert" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
  -DEigen3_DIR="$EIGEN3_DIR" \
  -DOpenCV_DIR="$OPENCV_DIR" \
  -DCeres_DIR="$CERES_DIR" \
  -DSuiteSparse_DIR="$SUITESPARSE_DIR" \
  -DMETIS_INCLUDE_DIR="$METIS_INCLUDE_DIR" \
  -DMETIS_LIBRARY="$METIS_LIBRARY" \
  -DENABLE_ROS=OFF \
  -DENABLE_ARUCO_TAGS=OFF \
  -DBUILD_OPENVINS_TOOLS=OFF \
  -DOPENVINS_LIBRARY_TYPE=STATIC \
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
