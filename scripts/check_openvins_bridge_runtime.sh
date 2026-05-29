#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${SDK:-iphonesimulator}"
SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"

cd "$ROOT_DIR"

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
  -I/opt/homebrew/opt/eigen/include/eigen3 \
  -I/opt/homebrew/opt/opencv/include/opencv4 \
  -I/opt/homebrew/opt/boost/include \
  -I/opt/homebrew/opt/ceres-solver/include \
  -I/opt/homebrew/opt/glog/include \
  -I/opt/homebrew/opt/gflags/include \
  -I/opt/homebrew/opt/suite-sparse/include/suitesparse \
  -isysroot "$SDK_PATH" \
  camerasutra/VIO/OpenVINSBridge.mm
