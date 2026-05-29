# VIO Bridge

This folder is the app boundary for the OpenVINS port.

Swift talks only to `VIOTracker`. `VIOTracker` calls `OpenVINSBridge`, an Objective-C++ wrapper that will own the C++ OpenVINS manager once the static libraries are linked.

Current state:

- `OpenVINSBridge` is a compile-time stub.
- The app already feeds camera intrinsics, timestamped CoreMotion IMU samples, and AVCapture luma frames into the bridge API.
- The debug overlay reports bridge status and sample counts.

Next state:

- Link the iOS dependency XCFrameworks and enable `CAMERASUTRA_ENABLE_OPENVINS_RUNTIME`.
- Configure OpenVINS programmatically from camera intrinsics, IMU noise, and camera-to-IMU calibration.
- Publish the real OpenVINS pose through the existing `VIOPose` Swift model.
