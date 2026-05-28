//
//  CameraTrackingPOC.swift
//
//  Proof-of-concept: demonstrates that a single AVCaptureSession on the
//  builtInLiDARDepthCamera virtual device can deliver:
//    - Pro-quality video (10-bit ProRes 4:2:2, Apple Log, or HDR)
//    - Synchronized LiDAR-fused depth at up to 4K
//    - Per-frame camera intrinsics
//    - CoreMotion IMU rotation alongside
//
//  Format can be switched live among available presets so you can verify each
//  combination actually streams. Translation tracking is NOT implemented here
//  (it's a separate algorithm beyond POC scope) — but the depth data needed
//  for it is displayed as a live colorized depth map plus a per-frame stats
//  readout, proving the input to that future solver is available.
//
//  REQUIRED Info.plist:
//    NSCameraUsageDescription   = "Camera tracking demo"
//    NSMicrophoneUsageDescription (optional — for audio if you extend later)
//    NSMotionUsageDescription   = "Device rotation for tracking"
//
//  TARGET: iOS 17+ on an iPhone Pro with LiDAR.
//

import SwiftUI
import AVFoundation
import CoreMotion
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import simd
import Combine

// @main
// struct CameraTrackingPOCApp: App {
//     var body: some Scene { WindowGroup { ContentView() } }
// }

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var session = CaptureSession()
    @StateObject private var motion = MotionTracker()
    @State private var authStatus: AVAuthorizationStatus = .notDetermined
    @State private var showFormatSheet = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if authStatus == .authorized {
                VStack(spacing: 0) {
                    // Top: dual previews (RGB + depth)
                    HStack(spacing: 4) {
                        videoPane
                        depthPane
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    
                    // Middle: status panels
                    ScrollView {
                        VStack(spacing: 10) {
                            formatPanel
                            rotationPanel
                            depthStatsPanel
                            intrinsicsPanel
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
            } else {
                ContentUnavailableView("Camera access required", systemImage: "camera")
                    .foregroundStyle(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            authStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if authStatus == .notDetermined {
                let g = await AVCaptureDevice.requestAccess(for: .video)
                authStatus = g ? .authorized : .denied
            }
            if authStatus == .authorized {
                session.start()
                motion.start()
            }
        }
        .onDisappear {
            session.stop()
            motion.stop()
        }
        .sheet(isPresented: $showFormatSheet) {
            FormatPickerSheet(session: session)
        }
    }
    
    // MARK: Panes
    
    private var videoPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Rectangle().fill(Color.black)
                    .aspectRatio(4.0/3.0, contentMode: .fit)
                if let img = session.videoPreview {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).clipped()
                } else {
                    Text("waiting…").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
                VStack {
                    HStack {
                        Text("VIDEO")
                            .font(.caption2.weight(.bold).monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.0f fps", session.videoFPS))
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private var depthPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Rectangle().fill(Color.black)
                    .aspectRatio(4.0/3.0, contentMode: .fit)
                if let img = session.depthPreview {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).clipped()
                } else {
                    Text("no depth yet").font(.caption).foregroundStyle(.white.opacity(0.4))
                }
                VStack {
                    HStack {
                        Text("DEPTH")
                            .font(.caption2.weight(.bold).monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.0f fps", session.depthFPS))
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    // MARK: Panels
    
    private var formatPanel: some View {
        Panel(title: "FORMAT") {
            VStack(alignment: .leading, spacing: 6) {
                if let f = session.activeFormat {
                    KV("Resolution", "\(f.width)×\(f.height)")
                    KV("Pixel format", f.pixelString)
                    KV("Bit depth", "\(f.bitDepth)-bit \(f.subsampling)")
                    KV("Color space", f.colorSpace)
                    KV("Frame rate", "\(f.fps) fps")
                    KV("Depth", f.hasDepth ? "ON (\(f.depthWidth)×\(f.depthHeight))" : "OFF")
                    KV("HDR", f.hdr ? "ON" : "OFF")
                    KV("ProRes encode", session.proResEnabled ? "ON" : "OFF")
                } else {
                    Text("Configuring…").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    showFormatSheet = true
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Change format")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.top, 4)
            }
        }
    }
    
    private var rotationPanel: some View {
        Panel(title: "IMU ROTATION (CoreMotion)") {
            VStack(alignment: .leading, spacing: 6) {
                KV("Pitch", String(format: "%+.2f°", motion.pitchDeg))
                KV("Roll",  String(format: "%+.2f°", motion.rollDeg))
                KV("Yaw",   String(format: "%+.2f°", motion.yawDeg))
                KV("Quaternion", motion.quatString)
                KV("Sample rate", String(format: "%.0f Hz", motion.sampleRate))
                Text("Gyro-fused device attitude. This is the rotation prior the translation solver would use.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    private var depthStatsPanel: some View {
        Panel(title: "LIDAR DEPTH (for translation solver)") {
            VStack(alignment: .leading, spacing: 6) {
                KV("Map resolution", session.depthMapResolution)
                KV("Nearest point",  String(format: "%.2f m", session.depthMin))
                KV("Farthest point", String(format: "%.2f m", session.depthMax))
                KV("Mean depth",     String(format: "%.2f m", session.depthMean))
                KV("Valid points",   "\(session.validDepthPoints) / \(session.totalDepthPoints)")
                Text("Point cloud is derived per-frame by unprojecting depth pixels through camera intrinsics. Translation solver (RGB-D + locked IMU rotation) is out of POC scope, but the inputs are flowing — see the live values above.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    private var intrinsicsPanel: some View {
        Panel(title: "PER-FRAME CAMERA INTRINSICS") {
            VStack(alignment: .leading, spacing: 6) {
                KV("fx", String(format: "%.2f px", session.intrinsicsFx))
                KV("fy", String(format: "%.2f px", session.intrinsicsFy))
                KV("cx", String(format: "%.2f px", session.intrinsicsCx))
                KV("cy", String(format: "%.2f px", session.intrinsicsCy))
                Text("Delivered per frame on the capture connection. Required for unprojecting depth to a metric point cloud and for DCC export.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Reusable widgets

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(.white.opacity(0.65))
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct KV: View {
    let key: String
    let value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View {
        HStack {
            Text(key).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).font(.caption.monospaced()).foregroundStyle(.white)
        }
    }
}

// MARK: - Format picker sheet

struct FormatPickerSheet: View {
    @ObservedObject var session: CaptureSession
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("ProRes encode") {
                    Toggle("Encode video as ProRes 422 HQ", isOn: Binding(
                        get: { session.proResEnabled },
                        set: { session.proResEnabled = $0 }
                    ))
                }
                Section {
                    Text("Each preset selects a depth-capable format on the LiDAR Depth Camera. All also stream synchronized depth.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Available formats") {
                    ForEach(session.availableFormats) { preset in
                        Button {
                            session.applyPreset(preset)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title).font(.subheadline)
                                    Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if session.activePresetId == preset.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Motion tracker

@MainActor
final class MotionTracker: ObservableObject {
    private let manager = CMMotionManager()
    @Published var pitchDeg: Double = 0
    @Published var rollDeg: Double = 0
    @Published var yawDeg: Double = 0
    @Published var quatString: String = "—"
    @Published var sampleRate: Double = 0
    
    private var lastSampleTime: Date?
    private var rateAvg: Double = 0
    
    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.attitude
            self.pitchDeg = a.pitch * 180 / .pi
            self.rollDeg = a.roll * 180 / .pi
            self.yawDeg = a.yaw * 180 / .pi
            let q = a.quaternion
            self.quatString = String(format: "(%+.3f, %+.3f, %+.3f, %+.3f)", q.x, q.y, q.z, q.w)
            let now = Date()
            if let last = self.lastSampleTime {
                let dt = now.timeIntervalSince(last)
                if dt > 0 {
                    let inst = 1.0 / dt
                    self.rateAvg = self.rateAvg * 0.9 + inst * 0.1
                    self.sampleRate = self.rateAvg
                }
            }
            self.lastSampleTime = now
        }
    }
    
    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

// MARK: - Format preset

struct FormatPreset: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    let title: String
    let subtitle: String
    let format: AVCaptureDevice.Format
    let frameRate: Double
    let colorSpace: AVCaptureColorSpace
    
    static func == (lhs: FormatPreset, rhs: FormatPreset) -> Bool { lhs.id == rhs.id }
}

struct ActiveFormatInfo {
    let width: Int
    let height: Int
    let pixelString: String
    let bitDepth: Int
    let subsampling: String
    let colorSpace: String
    let fps: Int
    let hasDepth: Bool
    let depthWidth: Int
    let depthHeight: Int
    let hdr: Bool
}

// MARK: - Capture session

final class CaptureSession: NSObject, ObservableObject, @unchecked Sendable {
    
    // Published UI state
    @Published var videoPreview: UIImage?
    @Published var depthPreview: UIImage?
    @Published var videoFPS: Double = 0
    @Published var depthFPS: Double = 0
    @Published var availableFormats: [FormatPreset] = []
    @Published var activePresetId: String?
    @Published var activeFormat: ActiveFormatInfo?
    @Published var proResEnabled: Bool = true
    
    @Published var depthMapResolution: String = "—"
    @Published var depthMin: Double = 0
    @Published var depthMax: Double = 0
    @Published var depthMean: Double = 0
    @Published var validDepthPoints: Int = 0
    @Published var totalDepthPoints: Int = 0
    
    @Published var intrinsicsFx: Double = 0
    @Published var intrinsicsFy: Double = 0
    @Published var intrinsicsCx: Double = 0
    @Published var intrinsicsCy: Double = 0
    
    // AVFoundation
    private let session = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let sampleQueue = DispatchQueue(label: "poc.sample")
    private let sessionQueue = DispatchQueue(label: "poc.session")
    private var device: AVCaptureDevice?
    
    // Frame timing
    private var lastVideoTime: Date?
    private var lastDepthTime: Date?
    private var videoRateAvg: Double = 0
    private var depthRateAvg: Double = 0
    
    // Preview rendering
    private let ci = CIContext(options: [.useSoftwareRenderer: false])
    private var lastVideoPreviewUpdate: Date = .distantPast
    private var lastDepthPreviewUpdate: Date = .distantPast
    private let previewThrottle: TimeInterval = 1.0 / 15.0
    
    func start() {
        sessionQueue.async {
            self.configure()
            self.session.startRunning()
        }
    }
    
    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
        }
    }
    
    // MARK: Configure
    
    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            print("LiDAR depth camera unavailable on this device")
            return
        }
        self.device = device
        
        // Enumerate depth-capable formats
        let presets = enumeratePresets(device: device)
        DispatchQueue.main.async {
            self.availableFormats = presets
        }
        
        // Pick the highest-quality 10-bit Log preset available by default
        let defaultPreset = presets.first(where: {
            $0.format.formatDescription.dimensions.width >= 1920 &&
            $0.colorSpace == .appleLog
        }) ?? presets.first(where: {
            $0.format.formatDescription.dimensions.width >= 1920
        }) ?? presets.first
        
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                self.videoInput = input
            }
        } catch {
            print("Input error: \(error)")
            session.commitConfiguration()
            return
        }
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = false
        }
        
        // Enable per-frame intrinsics
        if let conn = videoOutput.connection(with: .video) {
            if conn.isCameraIntrinsicMatrixDeliverySupported {
                conn.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
        
        session.commitConfiguration()
        
        // Apply the default preset
        if let preset = defaultPreset {
            applyPresetInternal(preset)
        }
        
        // Wire synchronizer AFTER outputs are configured
        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        synchronizer?.setDelegate(self, queue: sampleQueue)
    }
    
    private func enumeratePresets(device: AVCaptureDevice) -> [FormatPreset] {
        var presets: [FormatPreset] = []
        for format in device.formats where !format.supportedDepthDataFormats.isEmpty {
            let dims = format.formatDescription.dimensions
            let subtype = format.formatDescription.mediaSubType.rawValue
            let pix = describePixelFormat(subtype)
            let supportsLog = format.supportedColorSpaces.contains(.appleLog)
            let supportsHDR = format.isVideoHDRSupported
            
            for rateRange in format.videoSupportedFrameRateRanges {
                let candidateRates: [Double] = [30, 60].filter { $0 <= rateRange.maxFrameRate && $0 >= rateRange.minFrameRate }
                for rate in candidateRates {
                    var colorSpaceCandidates: [AVCaptureColorSpace] = [.sRGB]
                    if supportsLog { colorSpaceCandidates.append(.appleLog) }
                    if format.supportedColorSpaces.contains(.HLG_BT2020) {
                        colorSpaceCandidates.append(.HLG_BT2020)
                    }
                    for cs in colorSpaceCandidates {
                        let csLabel = describeColorSpace(cs)
                        let id = "\(dims.width)x\(dims.height)_\(pix.string)_\(Int(rate))_\(csLabel)"
                        let title = "\(dims.width)×\(dims.height) @ \(Int(rate))fps · \(csLabel)"
                        let subtitle = "\(pix.bitDepth)-bit \(pix.subsampling) · \(pix.string)\(supportsHDR ? " · HDR-capable" : "")"
                        presets.append(FormatPreset(
                            id: id, title: title, subtitle: subtitle,
                            format: format, frameRate: rate, colorSpace: cs
                        ))
                    }
                }
            }
        }
        // Sort: 10-bit + Log first, then by resolution descending, then by fps
        presets.sort { a, b in
            let aRich = (pixBitDepth(a) == 10 ? 2 : 0) + (a.colorSpace == .appleLog ? 1 : 0)
            let bRich = (pixBitDepth(b) == 10 ? 2 : 0) + (b.colorSpace == .appleLog ? 1 : 0)
            if aRich != bRich { return aRich > bRich }
            let aDims = a.format.formatDescription.dimensions
            let bDims = b.format.formatDescription.dimensions
            if aDims.width != bDims.width { return aDims.width > bDims.width }
            return a.frameRate > b.frameRate
        }
        return presets
    }
    
    private func pixBitDepth(_ p: FormatPreset) -> Int {
        describePixelFormat(p.format.formatDescription.mediaSubType.rawValue).bitDepth
    }
    
    func applyPreset(_ preset: FormatPreset) {
        sessionQueue.async {
            self.applyPresetInternal(preset)
        }
    }
    
    private func applyPresetInternal(_ preset: FormatPreset) {
        guard let device = self.device else { return }
        do {
            try device.lockForConfiguration()
            session.beginConfiguration()
            
            device.activeFormat = preset.format
            
            // Choose a matching depth format
            if let depthFormat = preset.format.supportedDepthDataFormats.last {
                device.activeDepthDataFormat = depthFormat
            }
            
            let dur = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))
            device.activeVideoMinFrameDuration = dur
            device.activeVideoMaxFrameDuration = dur
            
            if preset.format.supportedColorSpaces.contains(preset.colorSpace) {
                device.activeColorSpace = preset.colorSpace
            }
            
            session.commitConfiguration()
            device.unlockForConfiguration()
            
            let dims = preset.format.formatDescription.dimensions
            let pix = describePixelFormat(preset.format.formatDescription.mediaSubType.rawValue)
            let depthDims: CMVideoDimensions
            if let df = device.activeDepthDataFormat {
                depthDims = df.formatDescription.dimensions
            } else {
                depthDims = CMVideoDimensions(width: 0, height: 0)
            }
            let info = ActiveFormatInfo(
                width: Int(dims.width), height: Int(dims.height),
                pixelString: pix.string, bitDepth: pix.bitDepth, subsampling: pix.subsampling,
                colorSpace: describeColorSpace(preset.colorSpace),
                fps: Int(preset.frameRate),
                hasDepth: device.activeDepthDataFormat != nil,
                depthWidth: Int(depthDims.width), depthHeight: Int(depthDims.height),
                hdr: preset.format.isVideoHDRSupported
            )
            DispatchQueue.main.async {
                self.activePresetId = preset.id
                self.activeFormat = info
                self.depthMapResolution = "\(depthDims.width)×\(depthDims.height)"
            }
        } catch {
            print("Format apply failed: \(error)")
            session.commitConfiguration()
        }
    }
}

// MARK: - Synchronizer delegate

extension CaptureSession: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        let now = Date()
        
        if let videoData = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
           !videoData.sampleBufferWasDropped {
            handleVideoSampleBuffer(videoData.sampleBuffer, time: now)
        }
        if let depthData = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
           !depthData.depthDataWasDropped {
            handleDepthData(depthData.depthData, time: now)
        }
    }
    
    private func handleVideoSampleBuffer(_ sample: CMSampleBuffer, time: Date) {
        // FPS
        if let last = lastVideoTime {
            let dt = time.timeIntervalSince(last)
            if dt > 0 {
                let inst = 1.0 / dt
                videoRateAvg = videoRateAvg * 0.9 + inst * 0.1
                DispatchQueue.main.async { self.videoFPS = self.videoRateAvg }
            }
        }
        lastVideoTime = time
        
        // Intrinsics
        if let attachment = CMGetAttachment(sample, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data {
            attachment.withUnsafeBytes { raw in
                let buf = raw.bindMemory(to: matrix_float3x3.self)
                if let m = buf.first {
                    DispatchQueue.main.async {
                        self.intrinsicsFx = Double(m[0, 0])
                        self.intrinsicsFy = Double(m[1, 1])
                        self.intrinsicsCx = Double(m[2, 0])
                        self.intrinsicsCy = Double(m[2, 1])
                    }
                }
            }
        }
        
        // Preview (throttled)
        if time.timeIntervalSince(lastVideoPreviewUpdate) >= previewThrottle,
           let pb = CMSampleBufferGetImageBuffer(sample) {
            lastVideoPreviewUpdate = time
            let img = renderImage(from: pb)
            DispatchQueue.main.async { self.videoPreview = img }
        }
    }
    
    private func handleDepthData(_ depth: AVDepthData, time: Date) {
        // FPS
        if let last = lastDepthTime {
            let dt = time.timeIntervalSince(last)
            if dt > 0 {
                let inst = 1.0 / dt
                depthRateAvg = depthRateAvg * 0.9 + inst * 0.1
                DispatchQueue.main.async { self.depthFPS = self.depthRateAvg }
            }
        }
        lastDepthTime = time
        
        // Convert to Float32 if needed
        let depth32 = depth.depthDataType == kCVPixelFormatType_DepthFloat32
        ? depth
        : depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        
        // Compute stats and a colorized preview
        let stats = computeDepthStats(depth32.depthDataMap)
        DispatchQueue.main.async {
            self.depthMin = stats.min
            self.depthMax = stats.max
            self.depthMean = stats.mean
            self.validDepthPoints = stats.valid
            self.totalDepthPoints = stats.total
        }
        
        if time.timeIntervalSince(lastDepthPreviewUpdate) >= previewThrottle {
            lastDepthPreviewUpdate = time
            let img = renderDepthImage(from: depth32.depthDataMap, min: Float(stats.min), max: Float(stats.max))
            DispatchQueue.main.async { self.depthPreview = img }
        }
    }
    
    // MARK: Image rendering
    
    private func renderImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        var img = CIImage(cvPixelBuffer: pixelBuffer)
        let targetWidth: CGFloat = 480
        let scale = targetWidth / img.extent.width
        img = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        img = img.oriented(.right)
        guard let cg = ci.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
    
    private func renderDepthImage(from depthMap: CVPixelBuffer, min depthMin: Float, max depthMax: Float) -> UIImage? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        let range = max(depthMax - depthMin, 0.01)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            let rowPtr = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let d = rowPtr[x]
                let i = (y * width + x) * 4
                if !d.isFinite || d <= 0 {
                    pixels[i] = 0; pixels[i+1] = 0; pixels[i+2] = 0; pixels[i+3] = 255
                    continue
                }
                let norm = max(0, min(1, (d - depthMin) / range))
                // Inferno-ish colormap
                let r = UInt8(min(255, max(0, 255 * (1.5 - 2 * abs(norm - 0.75)))))
                let g = UInt8(min(255, max(0, 255 * (1.5 - 2 * abs(norm - 0.5)))))
                let b = UInt8(min(255, max(0, 255 * (1.5 - 2 * abs(norm - 0.25)))))
                pixels[i] = r; pixels[i+1] = g; pixels[i+2] = b; pixels[i+3] = 255
            }
        }
        
        let provider = CGDataProvider(data: NSData(bytes: pixels, length: pixels.count))!
        let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent
        )!
        var ci = CIImage(cgImage: cg)
        ci = ci.oriented(.right)
        guard let final = self.ci.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: final)
    }
    
    private func computeDepthStats(_ depthMap: CVPixelBuffer)
    -> (min: Double, max: Double, mean: Double, valid: Int, total: Int) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else {
            return (0, 0, 0, 0, 0)
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        var lo: Float = .greatestFiniteMagnitude
        var hi: Float = 0
        var sum: Double = 0
        var valid = 0
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let d = row[x]
                if d.isFinite && d > 0 {
                    if d < lo { lo = d }
                    if d > hi { hi = d }
                    sum += Double(d)
                    valid += 1
                }
            }
        }
        let total = width * height
        let mean = valid > 0 ? sum / Double(valid) : 0
        return (Double(lo == .greatestFiniteMagnitude ? 0 : lo), Double(hi), mean, valid, total)
    }
}

// MARK: - Helpers

func describePixelFormat(_ fourCC: OSType) -> (string: String, bitDepth: Int, subsampling: String) {
    let str = fourCCString(fourCC)
    switch fourCC {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: return (str, 8, "4:2:0")
    case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: return (str, 10, "4:2:0")
    case kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_422YpCbCr10BiPlanarFullRange: return (str, 10, "4:2:2")
    case kCVPixelFormatType_422YpCbCr8, kCVPixelFormatType_422YpCbCr8_yuvs: return (str, 8, "4:2:2")
    default: return (str, 0, "?")
    }
}

func fourCCString(_ code: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),  UInt8(code & 0xff),
    ]
    return (String(bytes: bytes, encoding: .ascii) ?? "????").trimmingCharacters(in: .whitespaces)
}

func describeColorSpace(_ cs: AVCaptureColorSpace) -> String {
    switch cs {
    case .sRGB: return "sRGB"
    case .P3_D65: return "P3"
    case .HLG_BT2020: return "HLG/HDR"
    case .appleLog: return "Apple Log"
    case .appleLog2: return "Apple Log2"
    @unknown default: return "?"
    }
}

#Preview { ContentView() }
