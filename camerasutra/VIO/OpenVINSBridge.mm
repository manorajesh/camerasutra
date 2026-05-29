#import "OpenVINSBridge.h"

#include <mutex>
#include <string>

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

} // namespace

@interface OpenVINSBridge ()
@property(nonatomic) OpenVINSTrackerStub *tracker;
@end

@implementation OpenVINSBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _tracker = new OpenVINSTrackerStub();
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
    (void)accelX;
    (void)accelY;
    (void)accelZ;
    (void)gyroX;
    (void)gyroY;
    (void)gyroZ;
    _tracker->pushIMU(timestamp);
}

- (void)pushFrameAtTimestamp:(double)timestamp
                       width:(NSInteger)width
                      height:(NSInteger)height
                 bytesPerRow:(NSInteger)bytesPerRow
                        luma:(const uint8_t *)luma {
    (void)width;
    (void)height;
    (void)bytesPerRow;
    (void)luma;
    _tracker->pushFrame(timestamp);
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
