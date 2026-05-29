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
    private let trackingMaxDimension = 1280
    private var sourceCalibration: CameraCalibration?
    private var activeTrackingCalibration: CameraCalibration?

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
        sourceCalibration = CameraCalibration(width: width,
                                              height: height,
                                              fx: fx,
                                              fy: fy,
                                              cx: cx,
                                              cy: cy)
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

        guard let frame = makeTrackingLumaFrame(from: pixelBuffer) else {
            return
        }

        configureBridgeForTrackingFrame(width: frame.width, height: frame.height)

        frame.bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            bridge.pushFrame(atTimestamp: timestamp,
                             width: frame.width,
                             height: frame.height,
                             bytesPerRow: frame.width,
                             luma: baseAddress)
        }
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

    private func configureBridgeForTrackingFrame(width: Int, height: Int) {
        guard let sourceCalibration else { return }

        let sx = Double(width) / Double(sourceCalibration.width)
        let sy = Double(height) / Double(sourceCalibration.height)
        let trackingCalibration = CameraCalibration(width: width,
                                                    height: height,
                                                    fx: sourceCalibration.fx * sx,
                                                    fy: sourceCalibration.fy * sy,
                                                    cx: sourceCalibration.cx * sx,
                                                    cy: sourceCalibration.cy * sy)
        guard trackingCalibration != activeTrackingCalibration else { return }

        activeTrackingCalibration = trackingCalibration
        bridge.configureCamera(withWidth: trackingCalibration.width,
                               height: trackingCalibration.height,
                               fx: trackingCalibration.fx,
                               fy: trackingCalibration.fy,
                               cx: trackingCalibration.cx,
                               cy: trackingCalibration.cy)
    }

    private func makeTrackingLumaFrame(from pixelBuffer: CVPixelBuffer) -> TrackingLumaFrame? {
        let sourceWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) > 0 ? CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) : CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) > 0 ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) : CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let scale = min(1.0, Double(trackingMaxDimension) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var bytes = [UInt8](repeating: 0, count: width * height)

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) > 0 ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) ?? CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_OneComponent8:
            copy8BitLuma(baseAddress: baseAddress,
                         sourceWidth: sourceWidth,
                         sourceHeight: sourceHeight,
                         sourceBytesPerRow: sourceBytesPerRow,
                         destinationWidth: width,
                         destinationHeight: height,
                         destination: &bytes)

        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_OneComponent16:
            copy16BitLuma(baseAddress: baseAddress,
                          sourceWidth: sourceWidth,
                          sourceHeight: sourceHeight,
                          sourceBytesPerRow: sourceBytesPerRow,
                          destinationWidth: width,
                          destinationHeight: height,
                          destination: &bytes)

        default:
            copy8BitLuma(baseAddress: baseAddress,
                         sourceWidth: sourceWidth,
                         sourceHeight: sourceHeight,
                         sourceBytesPerRow: sourceBytesPerRow,
                         destinationWidth: width,
                         destinationHeight: height,
                         destination: &bytes)
        }

        return TrackingLumaFrame(width: width, height: height, bytes: bytes)
    }

    private func copy8BitLuma(baseAddress: UnsafeMutableRawPointer,
                              sourceWidth: Int,
                              sourceHeight: Int,
                              sourceBytesPerRow: Int,
                              destinationWidth: Int,
                              destinationHeight: Int,
                              destination: inout [UInt8]) {
        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<destinationHeight {
            let sourceY = min(sourceHeight - 1, y * sourceHeight / destinationHeight)
            let sourceRow = source.advanced(by: sourceY * sourceBytesPerRow)
            let destinationRow = y * destinationWidth
            for x in 0..<destinationWidth {
                let sourceX = min(sourceWidth - 1, x * sourceWidth / destinationWidth)
                destination[destinationRow + x] = sourceRow[sourceX]
            }
        }
    }

    private func copy16BitLuma(baseAddress: UnsafeMutableRawPointer,
                               sourceWidth: Int,
                               sourceHeight: Int,
                               sourceBytesPerRow: Int,
                               destinationWidth: Int,
                               destinationHeight: Int,
                               destination: inout [UInt8]) {
        let source = baseAddress.assumingMemoryBound(to: UInt16.self)
        let sourceStride = sourceBytesPerRow / MemoryLayout<UInt16>.stride
        for y in 0..<destinationHeight {
            let sourceY = min(sourceHeight - 1, y * sourceHeight / destinationHeight)
            let sourceRow = source.advanced(by: sourceY * sourceStride)
            let destinationRow = y * destinationWidth
            for x in 0..<destinationWidth {
                let sourceX = min(sourceWidth - 1, x * sourceWidth / destinationWidth)
                destination[destinationRow + x] = UInt8(clamping: Int(sourceRow[sourceX] >> 8))
            }
        }
    }
}

private struct CameraCalibration: Equatable {
    var width: Int
    var height: Int
    var fx: Double
    var fy: Double
    var cx: Double
    var cy: Double
}

private struct TrackingLumaFrame {
    var width: Int
    var height: Int
    var bytes: [UInt8]
}
