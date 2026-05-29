# camerasutra

[![iOS Build](https://github.com/manorajesh/camerasutra/actions/workflows/ios-build.yml/badge.svg)](https://github.com/manorajesh/camerasutra/actions/workflows/ios-build.yml)

An iOS camera-tracking prototype for capturing high-quality Log video while developing a real-time visual-inertial tracking pipeline for virtual production and DCC camera export.

## OpenVINS

OpenVINS is included as a git submodule at `third_party/open_vins`:

```sh
git submodule update --init --recursive
```

The submodule tracks the project fork at `https://github.com/manorajesh/open_vins.git`, with the official upstream available at `https://github.com/rpng/open_vins.git`.

## Build

Open `camerasutra.xcodeproj` in Xcode and build the `camerasutra` scheme for an iOS device or simulator.

Command-line build:

```sh
xcodebuild -project camerasutra.xcodeproj -scheme camerasutra -sdk iphonesimulator -configuration Debug build
```

Hardware camera, LiDAR, ProRes, and motion behavior must be validated on a supported iPhone Pro device.

## OpenVINS iOS Build

The OpenVINS iOS build is scaffolded as a separate CMake step:

```sh
scripts/build_openvins_ios.sh
```

The script builds from `third_party/open_vins/ov_msckf` with ROS and ArUco disabled. It expects iOS-compatible dependency prefixes for Eigen, OpenCV, Boost, and Ceres to be available through `CMAKE_PREFIX_PATH`.

## License

Project code outside `third_party/open_vins` is licensed under the MIT License. OpenVINS is GPLv3 and remains under its own license in `third_party/open_vins/LICENSE`.
