import AVFoundation
import CoreMedia
import CoreMotion
import Foundation
import simd

struct MotionSample: Sendable {
    let timestamp: TimeInterval
    let attitude: simd_quatf
}

final class MotionSampleStore: @unchecked Sendable {
    private let lock = NSLock()
    private var latestSample: MotionSample?
    private var originLocalToWorld: simd_quatf?

    func update(from motion: CMDeviceMotion) {
        let q = motion.attitude.quaternion
        let attitude = simd_normalize(simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)))
        let localToWorld = simd_normalize(attitude.inverse)
        if originLocalToWorld == nil {
            originLocalToWorld = localToWorld
        }
        let sample = MotionSample(
            timestamp: motion.timestamp,
            attitude: attitude
        )
        lock.lock()
        latestSample = sample
        lock.unlock()
    }

    func latest() -> MotionSample? {
        lock.lock()
        defer { lock.unlock() }
        return latestSample
    }

    func relativeRotation() -> simd_quatf {
        lock.lock()
        defer { lock.unlock() }
        guard let latestSample, let originLocalToWorld else {
            return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
        let currentLocalToWorld = simd_normalize(latestSample.attitude.inverse)
        let relative = simd_normalize(currentLocalToWorld * originLocalToWorld.inverse)
        return applySceneKitDisplayBasis(relative)
    }

    func recenter() {
        lock.lock()
        originLocalToWorld = latestSample.map { simd_normalize($0.attitude.inverse) }
        lock.unlock()
    }

    private func applySceneKitDisplayBasis(_ q: simd_quatf) -> simd_quatf {
        // CoreMotion's portrait device frame and the SceneKit debug phone share
        // roll direction, but pitch/yaw need the opposite handedness for an
        // intuitive "physical phone follows slab" display.
        let flipPitchYaw = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        let display = simd_normalize(flipPitchYaw * q * flipPitchYaw.inverse)
        return simd_normalize(simd_quatf(
            ix: -display.imag.x,
            iy: display.imag.y,
            iz: display.imag.z,
            r: display.real
        ))
    }
}

struct TrackingSnapshot: Sendable {
    var position: SIMD3<Float> = .zero
    var predictedPosition: SIMD3<Float> = .zero
    var velocity: SIMD3<Float> = .zero
    var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    var worldPoints: [SIMD3<Float>] = []
    var residualMeters: Float = 0
    var inlierCount: Int = 0
    var mapPointCount: Int = 0
    var conditionNumber: Float = 0
    var confidence: Float = 0
    var status: String = "Waiting for depth"
    var trail: [SIMD3<Float>] = []
}

struct TrackingIntrinsics: Sendable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let referenceWidth: Float
    let referenceHeight: Float

    func scaled(to width: Int, height: Int) -> TrackingIntrinsics {
        let sx = Float(width) / max(referenceWidth, 1)
        let sy = Float(height) / max(referenceHeight, 1)
        return TrackingIntrinsics(
            fx: fx * sx,
            fy: fy * sy,
            cx: cx * sx,
            cy: cy * sy,
            referenceWidth: Float(width),
            referenceHeight: Float(height)
        )
    }
}

final class DepthPointCloudProjector: @unchecked Sendable {
    private let maxPoints: Int
    private let minDepth: Float
    private let maxDepth: Float

    init(maxPoints: Int = 1200, minDepth: Float = 0.18, maxDepth: Float = 7.5) {
        self.maxPoints = maxPoints
        self.minDepth = minDepth
        self.maxDepth = maxDepth
    }

    func makeWorldPoints(depthMap: CVPixelBuffer,
                         intrinsics originalIntrinsics: TrackingIntrinsics,
                         rotation: simd_quatf) -> [SIMD3<Float>] {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return [] }

        let intrinsics = originalIntrinsics.scaled(to: width, height: height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let step = max(2, Int(sqrt(Double(width * height) / Double(maxPoints))))
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(maxPoints)

        for y in stride(from: step, to: height - step, by: step) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in stride(from: step, to: width - step, by: step) {
                let z = row[x]
                guard z.isFinite, z >= minDepth, z <= maxDepth else { continue }

                let cameraPoint = unproject(x: Float(x), y: Float(y), z: z, intrinsics: intrinsics)
                points.append(rotation.act(cameraPoint))
                if points.count >= maxPoints { return points }
            }
        }

        return points
    }

    private func unproject(x: Float, y: Float, z: Float, intrinsics: TrackingIntrinsics) -> SIMD3<Float> {
        SIMD3<Float>(
            (x - intrinsics.cx) * z / max(intrinsics.fx, 1),
            (y - intrinsics.cy) * z / max(intrinsics.fy, 1),
            -z
        )
    }
}

private struct DepthPoint {
    let p: SIMD3<Float>
    let n: SIMD3<Float>
}

private struct MapPoint {
    let p: SIMD3<Float>
    let n: SIMD3<Float>
    let weight: Float
}

final class RotationLockedDepthTracker: @unchecked Sendable {
    private var map: [MapPoint] = []
    private var position = SIMD3<Float>.zero
    private var velocity = SIMD3<Float>.zero
    private var lastTimestamp: TimeInterval?
    private var trail: [SIMD3<Float>] = [.zero]

    private let maxMapPoints = 1800
    private let maxFramePoints = 420
    private let minDepth: Float = 0.18
    private let maxDepth: Float = 7.5
    private let maxCorrespondenceDistance: Float = 0.28

    func reset() {
        map.removeAll(keepingCapacity: true)
        position = .zero
        velocity = .zero
        lastTimestamp = nil
        trail = [.zero]
    }

    func process(depthMap: CVPixelBuffer,
                 intrinsics: TrackingIntrinsics,
                 motion: MotionSample?,
                 timestamp: TimeInterval) -> TrackingSnapshot {
        let rotation = cameraRotation(from: motion)
        let points = makeDepthPoints(depthMap: depthMap, intrinsics: intrinsics)

        guard points.count >= 24 else {
            return snapshot(rotation: rotation, predicted: position, residual: 0, inliers: 0, condition: 0, confidence: 0, status: "Insufficient depth")
        }

        let dt = Float(lastTimestamp.map { max(0.001, timestamp - $0) } ?? 0.0)
        var predicted = position + velocity * dt

        if map.count < 80 {
            fuse(points: points, rotation: rotation, translation: position)
            lastTimestamp = timestamp
            return snapshot(rotation: rotation, predicted: predicted, residual: 0, inliers: 0, condition: 0, confidence: 0.25, status: "Initializing map")
        }

        var solved = predicted
        var residual: Float = 0
        var inliers = 0
        var condition: Float = 0

        for _ in 0..<5 {
            let result = solveTranslation(points: points, rotation: rotation, initial: solved)
            guard result.inliers >= 18 else { break }
            solved = simd_mix(solved, result.translation, SIMD3<Float>(repeating: 0.85))
            residual = result.residual
            inliers = result.inliers
            condition = result.condition
            predicted = solved
        }

        if inliers >= 18 && residual.isFinite {
            if dt > 0 {
                velocity = (solved - position) / dt
                let maxSpeed: Float = 8
                let speed = simd_length(velocity)
                if speed > maxSpeed {
                    velocity *= maxSpeed / speed
                }
            }
            position = solved
            fuse(points: points, rotation: rotation, translation: position)
            appendTrail(position)
        }

        lastTimestamp = timestamp
        let confidence = quality(inliers: inliers, residual: residual, condition: condition)
        let status = confidence > 0.65 ? "Tracking" : (inliers >= 18 ? "Weak geometry" : "Prediction only")
        return snapshot(rotation: rotation, predicted: predicted, residual: residual, inliers: inliers, condition: condition, confidence: confidence, status: status)
    }

    private func cameraRotation(from motion: MotionSample?) -> simd_quatf {
        guard let motion else {
            return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }

        // First-pass camera/device alignment. This intentionally keeps the
        // extrinsic explicit so device-specific calibration can replace it.
        let deviceToCamera = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        return simd_normalize(deviceToCamera * motion.attitude)
    }

    private func makeDepthPoints(depthMap: CVPixelBuffer, intrinsics originalIntrinsics: TrackingIntrinsics) -> [DepthPoint] {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return [] }

        let intrinsics = originalIntrinsics.scaled(to: width, height: height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let step = max(2, Int(sqrt(Double(width * height) / Double(maxFramePoints))))
        var points: [DepthPoint] = []
        points.reserveCapacity(maxFramePoints)

        for y in stride(from: step, to: height - step, by: step) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            let rowLeft = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            let rowUp = base.advanced(by: (y - step) * bytesPerRow).assumingMemoryBound(to: Float32.self)
            let rowDown = base.advanced(by: (y + step) * bytesPerRow).assumingMemoryBound(to: Float32.self)

            for x in stride(from: step, to: width - step, by: step) {
                let z = row[x]
                let zx1 = rowLeft[max(step, x - step)]
                let zx2 = rowLeft[min(width - step - 1, x + step)]
                let zy1 = rowUp[x]
                let zy2 = rowDown[x]

                guard z.isFinite, z >= minDepth, z <= maxDepth,
                      zx1.isFinite, zx2.isFinite, zy1.isFinite, zy2.isFinite else { continue }

                let center = unproject(x: Float(x), y: Float(y), z: z, intrinsics: intrinsics)
                let px1 = unproject(x: Float(x - step), y: Float(y), z: zx1, intrinsics: intrinsics)
                let px2 = unproject(x: Float(x + step), y: Float(y), z: zx2, intrinsics: intrinsics)
                let py1 = unproject(x: Float(x), y: Float(y - step), z: zy1, intrinsics: intrinsics)
                let py2 = unproject(x: Float(x), y: Float(y + step), z: zy2, intrinsics: intrinsics)

                let dx = px2 - px1
                let dy = py2 - py1
                let n = simd_normalize(simd_cross(dx, dy))
                guard n.x.isFinite, n.y.isFinite, n.z.isFinite, simd_length_squared(n) > 0.5 else { continue }
                points.append(DepthPoint(p: center, n: n))
                if points.count >= maxFramePoints { return points }
            }
        }

        return points
    }

    private func unproject(x: Float, y: Float, z: Float, intrinsics: TrackingIntrinsics) -> SIMD3<Float> {
        SIMD3<Float>(
            (x - intrinsics.cx) * z / max(intrinsics.fx, 1),
            (y - intrinsics.cy) * z / max(intrinsics.fy, 1),
            -z
        )
    }

    private func solveTranslation(points: [DepthPoint], rotation: simd_quatf, initial: SIMD3<Float>)
    -> (translation: SIMD3<Float>, residual: Float, inliers: Int, condition: Float) {
        var ata = simd_float3x3(columns: (.zero, .zero, .zero))
        var atb = SIMD3<Float>.zero
        var totalResidual: Float = 0
        var inliers = 0

        for point in points {
            let worldEstimate = rotation.act(point.p) + initial
            guard let match = nearestMapPoint(to: worldEstimate) else { continue }
            let diff = worldEstimate - match.p
            let distance = simd_length(diff)
            guard distance <= maxCorrespondenceDistance else { continue }

            let normalAgreement = abs(simd_dot(rotation.act(point.n), match.n))
            guard normalAgreement > 0.35 else { continue }

            let robust = huberWeight(distance, delta: 0.08)
            let w = robust * normalAgreement * match.weight
            let n = match.n
            let rhs = simd_dot(n, match.p - rotation.act(point.p))

            ata += outer(n, n) * w
            atb += n * rhs * w
            totalResidual += abs(simd_dot(n, diff))
            inliers += 1
        }

        guard inliers >= 3 else {
            return (initial, totalResidual, inliers, .infinity)
        }

        ata += matrix_identity_float3x3 * 0.0001
        let det = simd_determinant(ata)
        guard abs(det) > 1e-8, det.isFinite else {
            return (initial, totalResidual / Float(max(inliers, 1)), inliers, .infinity)
        }

        let solved = simd_inverse(ata) * atb
        let condition = estimateCondition(ata)
        return (solved, totalResidual / Float(inliers), inliers, condition)
    }

    private func nearestMapPoint(to point: SIMD3<Float>) -> MapPoint? {
        var best: MapPoint?
        var bestDistance = Float.greatestFiniteMagnitude
        for candidate in map {
            let d2 = simd_distance_squared(point, candidate.p)
            if d2 < bestDistance {
                bestDistance = d2
                best = candidate
            }
        }
        return best
    }

    private func fuse(points: [DepthPoint], rotation: simd_quatf, translation: SIMD3<Float>) {
        let decimation = max(1, points.count / 180)
        var additions: [MapPoint] = []
        additions.reserveCapacity(points.count / decimation)

        for index in stride(from: 0, to: points.count, by: decimation) {
            let point = points[index]
            additions.append(MapPoint(
                p: rotation.act(point.p) + translation,
                n: simd_normalize(rotation.act(point.n)),
                weight: 1
            ))
        }

        map.append(contentsOf: additions)
        if map.count > maxMapPoints {
            map.removeFirst(map.count - maxMapPoints)
        }
    }

    private func appendTrail(_ p: SIMD3<Float>) {
        if trail.last.map({ simd_distance($0, p) > 0.015 }) ?? true {
            trail.append(p)
            if trail.count > 220 {
                trail.removeFirst(trail.count - 220)
            }
        }
    }

    private func snapshot(rotation: simd_quatf,
                          predicted: SIMD3<Float>,
                          residual: Float,
                          inliers: Int,
                          condition: Float,
                          confidence: Float,
                          status: String) -> TrackingSnapshot {
        TrackingSnapshot(
            position: position,
            predictedPosition: predicted,
            velocity: velocity,
            rotation: rotation,
            worldPoints: [],
            residualMeters: residual.isFinite ? residual : 0,
            inlierCount: inliers,
            mapPointCount: map.count,
            conditionNumber: condition.isFinite ? condition : 0,
            confidence: confidence,
            status: status,
            trail: trail
        )
    }

    private func quality(inliers: Int, residual: Float, condition: Float) -> Float {
        guard inliers > 0, residual.isFinite else { return 0 }
        let inlierScore = min(1, Float(inliers) / 120)
        let residualScore = max(0, 1 - residual / 0.08)
        let conditionScore = condition.isFinite ? max(0, min(1, 1 - log10(max(condition, 1)) / 5)) : 0
        return max(0, min(1, inlierScore * 0.45 + residualScore * 0.4 + conditionScore * 0.15))
    }

    private func huberWeight(_ value: Float, delta: Float) -> Float {
        value <= delta ? 1 : delta / max(value, 0.0001)
    }

    private func outer(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3<Float>(a.x * b.x, a.y * b.x, a.z * b.x),
            SIMD3<Float>(a.x * b.y, a.y * b.y, a.z * b.y),
            SIMD3<Float>(a.x * b.z, a.y * b.z, a.z * b.z)
        ))
    }

    private func estimateCondition(_ m: simd_float3x3) -> Float {
        let diagonal = SIMD3<Float>(abs(m[0, 0]), abs(m[1, 1]), abs(m[2, 2]))
        let hi = max(diagonal.x, max(diagonal.y, diagonal.z))
        let lo = max(0.000001, min(diagonal.x, min(diagonal.y, diagonal.z)))
        return hi / lo
    }
}
