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
PLATFORM=SIMULATORARM64 SDK=iphonesimulator ARCHS=arm64 scripts/build_openvins_ios.sh
scripts/package_openvins_xcframework.sh
```

The build script compiles `third_party/open_vins/ov_msckf` with ROS, ArUco, and desktop test executables disabled, then installs static library slices under `Vendor/OpenVINS`. The packaging script creates `Vendor/OpenVINS/OpenVINS.xcframework`.

The OpenVINS archive is only one piece of the runtime link. The app target still needs matching iOS and simulator slices for OpenCV, Boost, Ceres, SuiteSparse, glog, and gflags before `OpenVINSBridge.mm` can call `ov_msckf::VioManager` directly.

The real bridge path is guarded by `CAMERASUTRA_ENABLE_OPENVINS_RUNTIME`. Until the dependency XCFrameworks are linked into the app target, keep that flag off. To syntax-check the gated runtime code against locally installed headers:

```sh
scripts/check_openvins_bridge_runtime.sh
```

## License

Project code outside `third_party/open_vins` is licensed under the MIT License. OpenVINS is GPLv3 and remains under its own license in `third_party/open_vins/LICENSE`.
