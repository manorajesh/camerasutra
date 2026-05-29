#import "OpenVINSBridge.h"

#ifndef CAMERASUTRA_ENABLE_OPENVINS_RUNTIME
#define CAMERASUTRA_ENABLE_OPENVINS_RUNTIME 0
#endif

#include <mutex>
#include <string>

#if CAMERASUTRA_ENABLE_OPENVINS_RUNTIME
#include <memory>

// Objective-C and Xcode define macros that collide with OpenVINS identifiers.
// NO is defined by ObjC runtime; DEBUG is set to 1 by Xcode debug builds.
// OpenVINS uses both as enum member names, so we clear them before its headers.
#ifdef NO
#undef NO
#endif
#ifdef DEBUG
#undef DEBUG
#endif

#include <opencv2/core.hpp>

#include "cam/CamRadtan.h"
#include "core/VioManager.h"
#include "state/State.h"
#include "types/IMU.h"
#include "utils/sensor_data.h"
#endif

@implementation OpenVINSPoseSnapshot

- (instancetype)initWithTimestamp:(double)timestamp
                               px:(double)px
                               py:(double)py
                               pz:(double)pz
                               qx:(double)qx
                               qy:(double)qy
                               qz:(double)qz
                               qw:(double)qw
                 cameraFrameCount:(NSInteger)cameraFrameCount
                    imuSampleCount:(NSInteger)imuSampleCount
                      featureCount:(NSInteger)featureCount
                       initialized:(BOOL)initialized
                            status:(NSString *)status {
    self = [super init];
    if (self) {
        _timestamp = timestamp;
        _px = px;
        _py = py;
        _pz = pz;
        _qx = qx;
        _qy = qy;
        _qz = qz;
        _qw = qw;
        _cameraFrameCount = cameraFrameCount;
        _imuSampleCount = imuSampleCount;
        _featureCount = featureCount;
        _initialized = initialized;
        _status = [status copy];
    }
    return self;
}

@end

namespace {

struct StubPose {
    double timestamp = 0.0;
    double px = 0.0;
    double py = 0.0;
    double pz = 0.0;
    double qx = 0.0;
    double qy = 0.0;
    double qz = 0.0;
    double qw = 1.0;
    NSInteger cameraFrameCount = 0;
    NSInteger imuSampleCount = 0;
    NSInteger featureCount = 0;
    bool configured = false;
    bool cameraConfigured = false;
    bool initialized = false;
    std::string status = "OpenVINS bridge idle";
};

struct CameraCalibration {
    NSInteger width = 0;
    NSInteger height = 0;
    double fx = 0.0;
    double fy = 0.0;
    double cx = 0.0;
    double cy = 0.0;
};

class OpenVINSTrackerStub {
public:
    bool configure() {
        std::lock_guard<std::mutex> lock(mutex_);
        pose_.configured = true;
        pose_.status = "OpenVINS bridge ready";
        return true;
    }

    void configureCamera(NSInteger width,
                         NSInteger height,
                         double fx,
                         double fy,
                         double cx,
                         double cy) {
        std::lock_guard<std::mutex> lock(mutex_);
        camera_ = {width, height, fx, fy, cx, cy};
        pose_.cameraConfigured = width > 0 && height > 0 && fx > 0 && fy > 0;
        if (pose_.configured) {
            pose_.status = pose_.cameraConfigured
                ? "OpenVINS calibrated bridge ready"
                : "OpenVINS waiting for camera intrinsics";
        }
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        const bool wasConfigured = pose_.configured;
        const CameraCalibration camera = camera_;
        pose_ = StubPose();
        pose_.configured = wasConfigured;
        camera_ = camera;
        pose_.cameraConfigured = camera_.width > 0 && camera_.height > 0 && camera_.fx > 0 && camera_.fy > 0;
        if (wasConfigured) {
            pose_.status = pose_.cameraConfigured
                ? "OpenVINS calibrated bridge ready"
                : "OpenVINS waiting for camera intrinsics";
        } else {
            pose_.status = "OpenVINS bridge idle";
        }
    }

    void pushIMU(double timestamp) {
        std::lock_guard<std::mutex> lock(mutex_);
        pose_.timestamp = timestamp;
        pose_.imuSampleCount += 1;
        if (pose_.configured) {
            pose_.status = pose_.cameraConfigured
                ? "OpenVINS runtime link pending"
                : "OpenVINS waiting for camera intrinsics";
        }
    }

    void pushFrame(double timestamp) {
        std::lock_guard<std::mutex> lock(mutex_);
        pose_.timestamp = timestamp;
        pose_.cameraFrameCount += 1;
        if (pose_.configured) {
            pose_.status = pose_.cameraConfigured
                ? "OpenVINS runtime link pending"
                : "OpenVINS waiting for camera intrinsics";
        }
    }

    StubPose latest() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return pose_;
    }

private:
    mutable std::mutex mutex_;
    StubPose pose_;
    CameraCalibration camera_;
};

#if CAMERASUTRA_ENABLE_OPENVINS_RUNTIME

class OpenVINSTrackerRuntime {
public:
    bool configure() {
        std::lock_guard<std::mutex> lock(mutex_);
        pose_.configured = true;
        pose_.status = cameraReady() ? "OpenVINS ready to initialize" : "OpenVINS waiting for camera intrinsics";
        rebuildIfReady();
        return true;
    }

    void configureCamera(NSInteger width,
                         NSInteger height,
                         double fx,
                         double fy,
                         double cx,
                         double cy) {
        std::lock_guard<std::mutex> lock(mutex_);
        camera_ = {width, height, fx, fy, cx, cy};
        pose_.cameraConfigured = cameraReady();
        pose_.status = pose_.cameraConfigured ? "OpenVINS camera calibrated" : "OpenVINS waiting for camera intrinsics";
        rebuildIfReady();
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        manager_.reset();
        pose_ = StubPose();
        pose_.configured = true;
        pose_.cameraConfigured = cameraReady();
        pose_.status = pose_.cameraConfigured ? "OpenVINS reset" : "OpenVINS waiting for camera intrinsics";
        rebuildIfReady();
    }

    void pushIMU(double timestamp,
                 double accelX,
                 double accelY,
                 double accelZ,
                 double gyroX,
                 double gyroY,
                 double gyroZ) {
        std::lock_guard<std::mutex> lock(mutex_);
        pose_.timestamp = timestamp;
        pose_.imuSampleCount += 1;
        if (!manager_) {
            pose_.status = cameraReady() ? "OpenVINS manager pending" : "OpenVINS waiting for camera intrinsics";
            return;
        }

        ov_core::ImuData message;
        message.timestamp = timestamp;
        message.am << accelX, accelY, accelZ;
        message.wm << gyroX, gyroY, gyroZ;
        manager_->feed_measurement_imu(message);
        updatePoseFromManager(timestamp);
    }

    void pushFrame(double timestamp,
                   NSInteger width,
                   NSInteger height,
                   NSInteger bytesPerRow,
                   const uint8_t *luma) {
        std::lock_guard<std::mutex> lock(mutex_);
        pose_.timestamp = timestamp;
        pose_.cameraFrameCount += 1;
        if (!manager_) {
            pose_.status = cameraReady() ? "OpenVINS manager pending" : "OpenVINS waiting for camera intrinsics";
            return;
        }

        cv::Mat image((int)height, (int)width, CV_8UC1, const_cast<uint8_t *>(luma), (size_t)bytesPerRow);
        ov_core::CameraData message;
        message.timestamp = timestamp;
        message.sensor_ids.push_back(0);
        message.images.push_back(image.clone());
        message.masks.push_back(cv::Mat());
        manager_->feed_measurement_camera(message);
        updatePoseFromManager(timestamp);
    }

    StubPose latest() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return pose_;
    }

private:
    bool cameraReady() const {
        return camera_.width > 0 && camera_.height > 0 && camera_.fx > 0 && camera_.fy > 0;
    }

    void rebuildIfReady() {
        if (!pose_.configured || !cameraReady() || manager_) {
            return;
        }

        ov_msckf::VioManagerOptions params;
        params.state_options.num_cameras = 1;
        params.state_options.max_clone_size = 11;
        params.state_options.max_slam_features = 0;
        params.state_options.max_aruco_features = 0;
        params.state_options.do_calib_camera_pose = false;
        params.state_options.do_calib_camera_intrinsics = false;
        params.state_options.do_calib_camera_timeoffset = false;
        params.state_options.do_calib_imu_intrinsics = false;
        params.state_options.do_calib_imu_g_sensitivity = false;
        params.use_stereo = false;
        params.use_aruco = false;
        params.use_klt = true;
        params.downsample_cameras = false;
        params.num_opencv_threads = 2;
        params.num_pts = 180;
        params.fast_threshold = 20;
        params.grid_x = 6;
        params.grid_y = 4;
        params.min_px_dist = 12;
        params.track_frequency = 30.0;
        params.try_zupt = true;
        params.zupt_only_at_beginning = true;
        params.init_options.init_max_features = 80;
        params.init_options.init_window_time = 1.0;

        Eigen::VectorXd intrinsics = Eigen::VectorXd::Zero(8);
        intrinsics << camera_.fx, camera_.fy, camera_.cx, camera_.cy, 0.0, 0.0, 0.0, 0.0;
        auto camera = std::make_shared<ov_core::CamRadtan>((int)camera_.width, (int)camera_.height);
        camera->set_value(intrinsics);
        params.camera_intrinsics.clear();
        params.camera_intrinsics.insert({0, camera});

        Eigen::Matrix<double, 7, 1> extrinsics;
        extrinsics << 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0;
        params.camera_extrinsics.clear();
        params.camera_extrinsics.insert({0, extrinsics});

        // InertialInitializerOptions has its own camera calibration maps that are
        // validated separately from VioManagerOptions's maps. Mirror the same data.
        params.init_options.num_cameras = 1;
        params.init_options.camera_intrinsics.clear();
        params.init_options.camera_intrinsics.insert({0, camera});
        params.init_options.camera_extrinsics.clear();
        params.init_options.camera_extrinsics.insert({0, extrinsics});

        params.vec_dw << 1.0, 0.0, 0.0, 1.0, 0.0, 1.0;
        params.vec_da << 1.0, 0.0, 0.0, 1.0, 0.0, 1.0;
        params.vec_tg.setZero();
        params.q_ACCtoIMU << 0.0, 0.0, 0.0, 1.0;
        params.q_GYROtoIMU << 0.0, 0.0, 0.0, 1.0;
        params.calib_camimu_dt = 0.0;

        manager_ = std::make_unique<ov_msckf::VioManager>(params);
        pose_.status = "OpenVINS manager running";
    }

    void updatePoseFromManager(double timestamp) {
        if (!manager_) {
            return;
        }
        pose_.initialized = manager_->initialized();
        pose_.featureCount = (NSInteger)manager_->get_good_features_MSCKF().size();
        if (!pose_.initialized) {
            pose_.status = "OpenVINS initializing";
            return;
        }

        auto state = manager_->get_state();
        if (!state || !state->_imu) {
            pose_.status = "OpenVINS waiting for state";
            return;
        }

        const Eigen::Vector4d q = state->_imu->quat();
        const Eigen::Vector3d p = state->_imu->pos();
        pose_.timestamp = timestamp;
        pose_.qx = q(0);
        pose_.qy = q(1);
        pose_.qz = q(2);
        pose_.qw = q(3);
        pose_.px = p(0);
        pose_.py = p(1);
        pose_.pz = p(2);
        pose_.status = "OpenVINS tracking";
    }

    mutable std::mutex mutex_;
    StubPose pose_;
    CameraCalibration camera_;
    std::unique_ptr<ov_msckf::VioManager> manager_;
};

using OpenVINSTracker = OpenVINSTrackerRuntime;

#else

using OpenVINSTracker = OpenVINSTrackerStub;

#endif

} // namespace

@interface OpenVINSBridge ()
@property(nonatomic) OpenVINSTracker *tracker;
@end

@implementation OpenVINSBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _tracker = new OpenVINSTracker();
    }
    return self;
}

- (void)dealloc {
    delete _tracker;
}

- (BOOL)configured {
    return _tracker->latest().configured;
}

- (BOOL)configureWithError:(NSError **)error {
    (void)error;
    return _tracker->configure();
}

- (void)configureCameraWithWidth:(NSInteger)width
                          height:(NSInteger)height
                              fx:(double)fx
                              fy:(double)fy
                              cx:(double)cx
                              cy:(double)cy {
    _tracker->configureCamera(width, height, fx, fy, cx, cy);
}

- (void)reset {
    _tracker->reset();
}

- (void)pushIMUAtTimestamp:(double)timestamp
                    accelX:(double)accelX
                    accelY:(double)accelY
                    accelZ:(double)accelZ
                     gyroX:(double)gyroX
                     gyroY:(double)gyroY
                     gyroZ:(double)gyroZ {
#if CAMERASUTRA_ENABLE_OPENVINS_RUNTIME
    _tracker->pushIMU(timestamp, accelX, accelY, accelZ, gyroX, gyroY, gyroZ);
#else
    (void)accelX;
    (void)accelY;
    (void)accelZ;
    (void)gyroX;
    (void)gyroY;
    (void)gyroZ;
    _tracker->pushIMU(timestamp);
#endif
}

- (void)pushFrameAtTimestamp:(double)timestamp
                       width:(NSInteger)width
                      height:(NSInteger)height
                 bytesPerRow:(NSInteger)bytesPerRow
                        luma:(const uint8_t *)luma {
#if CAMERASUTRA_ENABLE_OPENVINS_RUNTIME
    _tracker->pushFrame(timestamp, width, height, bytesPerRow, luma);
#else
    (void)width;
    (void)height;
    (void)bytesPerRow;
    (void)luma;
    _tracker->pushFrame(timestamp);
#endif
}

- (OpenVINSPoseSnapshot *)latestPose {
    StubPose pose = _tracker->latest();
    NSString *status = [NSString stringWithUTF8String:pose.status.c_str()];
    return [[OpenVINSPoseSnapshot alloc] initWithTimestamp:pose.timestamp
                                                        px:pose.px
                                                        py:pose.py
                                                        pz:pose.pz
                                                        qx:pose.qx
                                                        qy:pose.qy
                                                        qz:pose.qz
                                                        qw:pose.qw
                                          cameraFrameCount:pose.cameraFrameCount
                                            imuSampleCount:pose.imuSampleCount
                                              featureCount:pose.featureCount
                                               initialized:pose.initialized
                                                    status:status];
}

@end
