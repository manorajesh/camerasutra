#!/usr/bin/env bash
# Builds a minimal OpenCV static library for a single iOS platform slice.
# Builds only the modules required by the OpenVINS bridge:
#   core, imgproc, features2d, video, calib3d, flann
# and combines them into a single libopencv.a via libtool.
#
# Usage:
#   PLATFORM=OS64             SDK=iphoneos        ARCHS=arm64 bash build_opencv_ios.sh
#   PLATFORM=SIMULATORARM64   SDK=iphonesimulator ARCHS=arm64 bash build_opencv_ios.sh
#
# Outputs:
#   build/opencv-ios/{PLATFORM}/libopencv.a         – combined static library
#   build/opencv-ios/{PLATFORM}/include/opencv2/…   – headers
#   Vendor/opencv-ios/{PLATFORM}/…                  – install prefix
set -euo pipefail

OPENCV_VERSION="${OPENCV_VERSION:-4.13.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/opencv-ios"
INSTALL_DIR="$ROOT_DIR/Vendor/opencv-ios"

PLATFORM="${PLATFORM:-OS64}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-17.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
SDK="${SDK:-iphoneos}"
ARCHS="${ARCHS:-arm64}"
GENERATOR="${GENERATOR:-Ninja}"

CC="$(xcrun --sdk "$SDK" --find clang)"
CXX="$(xcrun --sdk "$SDK" --find clang++)"
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"

SOURCE_DIR="$ROOT_DIR/build/opencv-ios/opencv-${OPENCV_VERSION}-src"
PLATFORM_BUILD="$BUILD_DIR/$PLATFORM"
PLATFORM_INSTALL="$INSTALL_DIR/$PLATFORM"
COMBINED_LIB="$PLATFORM_BUILD/libopencv.a"

if [ -f "$COMBINED_LIB" ]; then
  echo "opencv $PLATFORM combined library already present — skipping build."
  echo "Remove $COMBINED_LIB and re-run to rebuild."
  exit 0
fi

# Download source if not present
if [ ! -d "$SOURCE_DIR" ]; then
  ARCHIVE_URL="https://github.com/opencv/opencv/archive/refs/tags/${OPENCV_VERSION}.tar.gz"
  ARCHIVE_PATH="$BUILD_DIR/opencv-${OPENCV_VERSION}.tar.gz"
  mkdir -p "$BUILD_DIR"
  echo "Downloading OpenCV ${OPENCV_VERSION} source..."
  curl -L --progress-bar -o "$ARCHIVE_PATH" "$ARCHIVE_URL"
  echo "Extracting..."
  tar -xzf "$ARCHIVE_PATH" -C "$BUILD_DIR"
  mv "$BUILD_DIR/opencv-${OPENCV_VERSION}" "$SOURCE_DIR"
  rm -f "$ARCHIVE_PATH"
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required" >&2
  exit 1
fi
if ! command -v ninja >/dev/null 2>&1 && [ "$GENERATOR" = "Ninja" ]; then
  echo "error: ninja is required (brew install ninja)" >&2
  exit 1
fi

echo "Building OpenCV ${OPENCV_VERSION} for iOS"
echo "  platform: $PLATFORM"
echo "  sdk: $SDK"
echo "  archs: $ARCHS"
echo "  deployment target: $DEPLOYMENT_TARGET"
echo "  build type: $BUILD_TYPE"
echo "  install dir: $PLATFORM_INSTALL"

mkdir -p "$PLATFORM_BUILD"
cmake -S "$SOURCE_DIR" \
  -B "$PLATFORM_BUILD" \
  -G "$GENERATOR" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_INSTALL_PREFIX="$PLATFORM_INSTALL" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF \
  -DWITH_CUDA=OFF \
  -DWITH_QT=OFF \
  -DWITH_GTK=OFF \
  -DWITH_FFMPEG=OFF \
  -DWITH_GSTREAMER=OFF \
  -DWITH_V4L=OFF \
  -DWITH_OPENCL=OFF \
  -DWITH_OPENEXR=OFF \
  -DWITH_TIFF=OFF \
  -DWITH_WEBP=OFF \
  -DWITH_JASPER=OFF \
  -DWITH_PNG=OFF \
  -DWITH_JPEG=OFF \
  -DWITH_EIGEN=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_DOCS=OFF \
  -DBUILD_opencv_apps=OFF \
  -DBUILD_JAVA=OFF \
  -DBUILD_OBJC=OFF \
  -DBUILD_ANDROID_EXAMPLES=OFF \
  -DBUILD_LIST="core,imgproc,features2d,video,calib3d,flann,imgcodecs" \
  -DBUILD_opencv_world=OFF \
  -DWITH_ZLIB=ON \
  -DBUILD_ZLIB=OFF \
  -DWITH_JPEG=OFF \
  -DWITH_PNG=OFF \
  -DWITH_TIFF=OFF \
  -DWITH_WEBP=OFF \
  -DWITH_OPENJPEG=OFF \
  -DWITH_JASPER=OFF \
  -DWITH_OPENEXR=OFF

cmake --build "$PLATFORM_BUILD" --config "$BUILD_TYPE" -j"$(sysctl -n hw.logicalcpu)"
cmake --install "$PLATFORM_BUILD" --config "$BUILD_TYPE"

# Combine all module static libs into one for easy xcframework packaging
echo "Combining module libs into single $COMBINED_LIB..."
module_libs=()
for lib in "$PLATFORM_INSTALL/lib"/libopencv_*.a; do
  [ -f "$lib" ] && module_libs+=("$lib")
done

if [ "${#module_libs[@]}" -eq 0 ]; then
  echo "error: no libopencv_*.a files found in $PLATFORM_INSTALL/lib" >&2
  exit 1
fi

libtool -static -o "$COMBINED_LIB" "${module_libs[@]}"

echo ""
echo "OpenCV ${PLATFORM} build complete."
echo "  combined lib: $COMBINED_LIB"
echo "  headers:      $PLATFORM_INSTALL/include/opencv4"
