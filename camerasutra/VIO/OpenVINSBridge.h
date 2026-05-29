#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenVINSPoseSnapshot : NSObject

@property(nonatomic, readonly) double timestamp;
@property(nonatomic, readonly) double px;
@property(nonatomic, readonly) double py;
@property(nonatomic, readonly) double pz;
@property(nonatomic, readonly) double qx;
@property(nonatomic, readonly) double qy;
@property(nonatomic, readonly) double qz;
@property(nonatomic, readonly) double qw;
@property(nonatomic, readonly) NSInteger cameraFrameCount;
@property(nonatomic, readonly) NSInteger imuSampleCount;
@property(nonatomic, readonly) NSInteger featureCount;
@property(nonatomic, readonly) BOOL initialized;
@property(nonatomic, readonly) NSString *status;

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
                            status:(NSString *)status;

@end

@interface OpenVINSBridge : NSObject

@property(nonatomic, readonly) BOOL configured;

- (BOOL)configureWithError:(NSError *_Nullable *_Nullable)error;
- (void)reset;
- (void)pushIMUAtTimestamp:(double)timestamp
                    accelX:(double)accelX
                    accelY:(double)accelY
                    accelZ:(double)accelZ
                     gyroX:(double)gyroX
                     gyroY:(double)gyroY
                     gyroZ:(double)gyroZ;
- (void)pushFrameAtTimestamp:(double)timestamp
                       width:(NSInteger)width
                      height:(NSInteger)height
                 bytesPerRow:(NSInteger)bytesPerRow
                        luma:(const uint8_t *)luma;
- (OpenVINSPoseSnapshot *)latestPose;

@end

NS_ASSUME_NONNULL_END
