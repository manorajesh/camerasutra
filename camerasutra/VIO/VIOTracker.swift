import CoreVideo
import Combine
import Foundation
import simd

struct VIOPose {
    var timestamp: TimeInterval = 0
    var position: SIMD3<Float> = .zero
    var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    var cameraFrameCount: Int = 0
    var imuSampleCount: Int = 0
    var featureCount: Int = 0
    var initialized: Bool = false
    var status: String = "OpenVINS bridge idle"
}

@MainActor
final class VIOTracker: ObservableObject {
    @Published private(set) var pose = VIOPose()

    private let bridge = OpenVINSBridge()

    func start() {
        do {
            try configureIfNeeded()
            refreshPose()
        } catch {
            pose.status = "OpenVINS configure failed: \(error.localizedDescription)"
        }
    }

    func reset() {
        bridge.reset()
        refreshPose()
    }

    func configureCamera(width: Int,
                         height: Int,
                         fx: Double,
                         fy: Double,
                         cx: Double,
                         cy: Double) {
        bridge.configureCamera(withWidth: width,
                               height: height,
                               fx: fx,
                               fy: fy,
                               cx: cx,
                               cy: cy)
        refreshPose()
    }

    func pushIMU(timestamp: TimeInterval,
                 acceleration: SIMD3<Double>,
                 gyro: SIMD3<Double>) {
        bridge.pushIMU(atTimestamp: timestamp,
                       accelX: acceleration.x,
                       accelY: acceleration.y,
                       accelZ: acceleration.z,
                       gyroX: gyro.x,
                       gyroY: gyro.y,
                       gyroZ: gyro.z)
    }

    func pushLumaFrame(timestamp: TimeInterval, pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) ?? CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) > 0 ? CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) : CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) > 0 ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) : CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) > 0 ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)

        bridge.pushFrame(atTimestamp: timestamp,
                         width: width,
                         height: height,
                         bytesPerRow: bytesPerRow,
                         luma: baseAddress.assumingMemoryBound(to: UInt8.self))
    }

    func refreshPose() {
        let snapshot = bridge.latestPose()
        pose = VIOPose(
            timestamp: snapshot.timestamp,
            position: SIMD3<Float>(Float(snapshot.px), Float(snapshot.py), Float(snapshot.pz)),
            rotation: simd_normalize(simd_quatf(ix: Float(snapshot.qx),
                                                iy: Float(snapshot.qy),
                                                iz: Float(snapshot.qz),
                                                r: Float(snapshot.qw))),
            cameraFrameCount: snapshot.cameraFrameCount,
            imuSampleCount: snapshot.imuSampleCount,
            featureCount: snapshot.featureCount,
            initialized: snapshot.initialized,
            status: snapshot.status
        )
    }

    private func configureIfNeeded() throws {
        guard !bridge.configured else { return }
        try bridge.configure()
    }
}
