//
//  CameraCapabilityInspector.swift
//
//  TARGET: iOS 17+. Run on a real iPhone Pro device (LiDAR + multicam need real hardware).
//

import SwiftUI
import AVFoundation
import UIKit
internal import Combine

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var inspector = CameraInspector()
    @State private var authStatus: AVAuthorizationStatus = .notDetermined
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            Group {
                switch authStatus {
                case .authorized:
                    inspectorList
                case .notDetermined:
                    permissionPrompt
                default:
                    permissionDenied
                }
            }
            .navigationTitle("Camera Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(inspector.report.isEmpty)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [inspector.report])
            }
        }
        .task {
            authStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if authStatus == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authStatus = granted ? .authorized : .denied
            }
            if authStatus == .authorized {
                inspector.scan()
            }
        }
    }
    
    private var permissionPrompt: some View {
        ContentUnavailableView(
            "Requesting camera access…",
            systemImage: "camera",
            description: Text("Camera access is required to enumerate device capabilities.")
        )
    }
    
    private var permissionDenied: some View {
        ContentUnavailableView(
            "Camera access denied",
            systemImage: "camera.fill",
            description: Text("Enable camera access in Settings to enumerate device capabilities.")
        )
    }
    
    private var inspectorList: some View {
        List {
            // The "answers" section — the questions we actually want resolved.
            Section("Verdict") {
                ForEach(inspector.verdicts, id: \.question) { v in
                    VerdictRow(verdict: v)
                }
            }
            
            // Multicam capability
            Section("Multicam") {
                LabeledRow(
                    label: "AVCaptureMultiCamSession.isMultiCamSupported",
                    value: inspector.multicamSupported ? "YES" : "NO"
                )
            }
            
            // Tested multicam combinations
            Section("Multicam combinations tested") {
                ForEach(inspector.combinationResults, id: \.label) { result in
                    CombinationRow(result: result)
                }
            }
            
            // Each discovered device
            ForEach(inspector.devices) { d in
                Section {
                    DeviceSummary(device: d)
                    NavigationLink("View all \(d.formats.count) formats") {
                        FormatsList(deviceInfo: d)
                    }
                } header: {
                    Text(d.shortName)
                } footer: {
                    Text(d.deviceType.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Verdict / question row

struct VerdictRow: View {
    let verdict: Verdict
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verdict.question)
                .font(.subheadline.weight(.semibold))
            HStack {
                Image(systemName: verdict.answer ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(verdict.answer ? .green : .red)
                Text(verdict.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Text(value).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}

struct CombinationRow: View {
    let result: CombinationResult
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: result.supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.supported ? .green : .red)
                Text(result.label).font(.subheadline)
            }
            if let detail = result.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Device summary

struct DeviceSummary: View {
    let device: DeviceInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Formats", "\(device.formats.count)")
            row("Max resolution", device.maxResolutionDesc)
            row("Has 10-bit format", device.has10Bit ? "YES" : "no")
            row("Has 4:2:2 format", device.has422 ? "YES" : "no")
            row("Apple Log color space", device.supportsAppleLog ? "YES" : "no")
            row("Any format supports depth", device.hasDepthCapableFormat ? "YES" : "no")
            row("Any format ProRes-grade", device.hasProResGradeFormat ? "YES" : "no")
            row("ProRes-grade + depth in one format", device.hasProResAndDepthInOneFormat ? "YES ✅" : "no")
            row("Any multicam-supported format", device.hasMulticamFormat ? "YES" : "no")
        }
        .font(.caption)
    }
    
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospaced()
        }
    }
}

// MARK: - Formats list

struct FormatsList: View {
    let deviceInfo: DeviceInfo
    
    var body: some View {
        List {
            ForEach(deviceInfo.formats) { f in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(Int(f.width))×\(Int(f.height))")
                            .font(.headline.monospaced())
                        Spacer()
                        Text(f.pixelFormatString)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15), in: Capsule())
                    }
                    HStack(spacing: 6) {
                        Badge(label: "\(f.bitDepth)-bit", color: f.bitDepth == 10 ? .green : .gray)
                        Badge(label: f.subsampling, color: f.subsampling == "4:2:2" ? .green : .gray)
                        if f.isBinned { Badge(label: "binned", color: .orange) }
                    }
                    Text("FPS: \(f.frameRateDesc)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if f.supportsDepth { Badge(label: "depth", color: .blue) }
                        if f.supportsMulticam { Badge(label: "multicam", color: .purple) }
                        if f.supportsAppleLog { Badge(label: "Apple Log", color: .green) }
                        if f.supportsHDR { Badge(label: "HDR", color: .pink) }
                    }
                    if !f.colorSpaces.isEmpty {
                        Text("Color spaces: \(f.colorSpaces.joined(separator: ", "))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(deviceInfo.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct Badge: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(.caption2.monospaced())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Data models

struct DeviceInfo: Identifiable {
    let id = UUID()
    let device: AVCaptureDevice
    let deviceType: AVCaptureDevice.DeviceType
    let shortName: String
    let formats: [FormatInfo]
    
    var maxResolutionDesc: String {
        guard let max = formats.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return "—" }
        return "\(Int(max.width))×\(Int(max.height))"
    }
    var has10Bit: Bool { formats.contains { $0.bitDepth == 10 } }
    var has422: Bool { formats.contains { $0.subsampling == "4:2:2" } }
    var supportsAppleLog: Bool { formats.contains { $0.supportsAppleLog } }
    var hasDepthCapableFormat: Bool { formats.contains { $0.supportsDepth } }
    var hasProResGradeFormat: Bool { formats.contains { $0.bitDepth >= 10 } }
    var hasProResAndDepthInOneFormat: Bool {
        formats.contains { $0.bitDepth >= 10 && $0.supportsDepth }
    }
    var hasMulticamFormat: Bool { formats.contains { $0.supportsMulticam } }
}

struct FormatInfo: Identifiable {
    let id = UUID()
    let width: Double
    let height: Double
    let pixelFormatString: String
    let bitDepth: Int
    let subsampling: String
    let frameRateDesc: String
    let isBinned: Bool
    let supportsDepth: Bool
    let supportsMulticam: Bool
    let supportsAppleLog: Bool
    let supportsHDR: Bool
    let colorSpaces: [String]
}

struct Verdict {
    let question: String
    let answer: Bool
    let detail: String
}

struct CombinationResult {
    let label: String
    let supported: Bool
    let detail: String?
}

// MARK: - Inspector

@MainActor
final class CameraInspector: ObservableObject {
    @Published var devices: [DeviceInfo] = []
    @Published var multicamSupported: Bool = false
    @Published var combinationResults: [CombinationResult] = []
    @Published var verdicts: [Verdict] = []
    @Published var report: String = ""
    
    func scan() {
        multicamSupported = AVCaptureMultiCamSession.isMultiCamSupported
        
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInLiDARDepthCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )
        
        var infos: [DeviceInfo] = []
        for device in discovery.devices {
            let formats = device.formats.map { FormatInfo(format: $0) }
            infos.append(DeviceInfo(
                device: device,
                deviceType: device.deviceType,
                shortName: prettyName(for: device.deviceType),
                formats: formats
            ))
        }
        devices = infos
        
        runCombinationTests()
        buildVerdicts()
        buildReport()
    }
    
    // MARK: - Multicam combination tests
    
    private func runCombinationTests() {
        guard multicamSupported else {
            combinationResults = [CombinationResult(
                label: "Multicam not supported on this device",
                supported: false,
                detail: nil
            )]
            return
        }
        
        let wide = device(for: .builtInWideAngleCamera)
        let ultra = device(for: .builtInUltraWideCamera)
        let tele = device(for: .builtInTelephotoCamera)
        let lidar = device(for: .builtInLiDARDepthCamera)
        
        var results: [CombinationResult] = []
        
        func test(_ label: String, _ ds: [AVCaptureDevice?]) {
            let devs = ds.compactMap { $0 }
            guard devs.count == ds.count else {
                results.append(CombinationResult(
                    label: label, supported: false,
                    detail: "One or more devices not present on this iPhone"
                ))
                return
            }
            let r = canCoexistInMulticam(devices: devs)
            results.append(CombinationResult(label: label, supported: r.ok, detail: r.detail))
        }
        
        // Baseline sanity checks
        test("Main wide + Ultra-wide", [wide, ultra])
        test("Main wide + Telephoto", [wide, tele])
        test("Ultra-wide + Telephoto", [ultra, tele])
        
        // The decision-critical ones for this project
        test("Main wide + LiDAR depth camera", [wide, lidar])
        test("Telephoto + LiDAR depth camera ⭐", [tele, lidar])
        test("Ultra-wide + LiDAR depth camera", [ultra, lidar])
        
        // Triple
        test("Main + Ultra + Telephoto", [wide, ultra, tele])
        
        combinationResults = results
    }
    
    private func canCoexistInMulticam(devices: [AVCaptureDevice]) -> (ok: Bool, detail: String?) {
        let session = AVCaptureMultiCamSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        for device in devices {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if !session.canAddInput(input) {
                    return (false, "canAddInput=false for \(prettyName(for: device.deviceType))")
                }
                session.addInput(input)
            } catch {
                return (false, "AVCaptureDeviceInput init failed: \(error.localizedDescription)")
            }
        }
        return (true, "All inputs accepted by AVCaptureMultiCamSession")
    }
    
    private func device(for type: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
        devices.first(where: { $0.deviceType == type })?.device
    }
    
    // MARK: - Verdicts (high-level answers)
    
    private func buildVerdicts() {
        var v: [Verdict] = []
        
        let wide = devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
        let tele = devices.first(where: { $0.deviceType == .builtInTelephotoCamera })
        let lidar = devices.first(where: { $0.deviceType == .builtInLiDARDepthCamera })
        
        // Q1: Does Main lens have a 10-bit + depth format simultaneously?
        if let wide {
            v.append(Verdict(
                question: "Does Main lens have ANY format that is 10-bit AND depth-capable?",
                answer: wide.hasProResAndDepthInOneFormat,
                detail: wide.hasProResAndDepthInOneFormat
                ? "YES — this would change everything; verify by inspecting that format"
                : "No — 10-bit formats and depth-capable formats are disjoint on this device"
            ))
        }
        
        // Q2: Telephoto + LiDAR depth multicam (the user's carve-up idea)
        let teleLidar = combinationResults.first { $0.label.hasPrefix("Telephoto + LiDAR") }
        if let teleLidar {
            v.append(Verdict(
                question: "Can Telephoto + LiDAR depth camera coexist in multicam?",
                answer: teleLidar.supported,
                detail: teleLidar.supported
                ? "YES — this is the carve-up path. Check Telephoto's multicam formats next."
                : "No — see combination detail below"
            ))
        }
        
        // Q3: Main wide + LiDAR depth multicam
        let wideLidar = combinationResults.first { $0.label.hasPrefix("Main wide + LiDAR") }
        if let wideLidar {
            v.append(Verdict(
                question: "Can Main wide + LiDAR depth camera coexist in multicam?",
                answer: wideLidar.supported,
                detail: wideLidar.supported
                ? "YES — but expect quality compromise from multicam hardware budget"
                : "No — confirms LiDAR depth virtual device is bound to Main lens"
            ))
        }
        
        // Q4: LiDAR depth camera bit depth
        if let lidar {
            v.append(Verdict(
                question: "Does the LiDAR depth camera virtual device offer ANY 10-bit format?",
                answer: lidar.has10Bit,
                detail: lidar.has10Bit
                ? "YES — this would loosen the 8-bit ceiling we discussed"
                : "No — confirms LiDAR depth path is 8-bit only"
            ))
        }
        
        // Q5: Telephoto supports multicam formats at all?
        if let tele {
            v.append(Verdict(
                question: "Does Telephoto have any multicam-supported format?",
                answer: tele.hasMulticamFormat,
                detail: tele.hasMulticamFormat
                ? "YES — Telephoto can participate in multicam"
                : "No — Telephoto cannot be used in multicam sessions"
            ))
        }
        
        verdicts = v
    }
    
    // MARK: - Plain-text report (for share / paste)
    
    private func buildReport() {
        var s = "=== Camera Capability Report ===\n"
        s += "Device: \(UIDevice.current.model) — iOS \(UIDevice.current.systemVersion)\n"
        s += "Multicam supported: \(multicamSupported)\n\n"
        
        s += "--- Verdicts ---\n"
        for v in verdicts {
            s += "[\(v.answer ? "YES" : "NO")] \(v.question)\n    → \(v.detail)\n"
        }
        s += "\n--- Multicam Combinations ---\n"
        for r in combinationResults {
            s += "[\(r.supported ? "OK" : "NO")] \(r.label)\n"
            if let d = r.detail { s += "    \(d)\n" }
        }
        
        for d in devices {
            s += "\n--- \(d.shortName) (\(d.deviceType.rawValue)) ---\n"
            s += "  formats: \(d.formats.count)\n"
            s += "  max res: \(d.maxResolutionDesc)\n"
            s += "  10-bit: \(d.has10Bit), 4:2:2: \(d.has422), AppleLog: \(d.supportsAppleLog)\n"
            s += "  depth-capable: \(d.hasDepthCapableFormat), multicam: \(d.hasMulticamFormat)\n"
            s += "  ProRes-grade + depth in one format: \(d.hasProResAndDepthInOneFormat)\n"
            for f in d.formats {
                s += "    \(Int(f.width))x\(Int(f.height)) \(f.pixelFormatString) \(f.bitDepth)b \(f.subsampling) fps=\(f.frameRateDesc)"
                var tags: [String] = []
                if f.supportsDepth { tags.append("depth") }
                if f.supportsMulticam { tags.append("mc") }
                if f.supportsAppleLog { tags.append("log") }
                if f.supportsHDR { tags.append("hdr") }
                if f.isBinned { tags.append("binned") }
                if !tags.isEmpty { s += " [\(tags.joined(separator: ","))]" }
                s += "\n"
            }
        }
        report = s
    }
}

// MARK: - FormatInfo construction & helpers

extension FormatInfo {
    init(format: AVCaptureDevice.Format) {
        let dims = format.formatDescription.dimensions
        self.width = Double(dims.width)
        self.height = Double(dims.height)
        
        let subtype = format.formatDescription.mediaSubType.rawValue
        let pix = describePixelFormat(subtype)
        self.pixelFormatString = pix.string
        self.bitDepth = pix.bitDepth
        self.subsampling = pix.subsampling
        
        self.frameRateDesc = format.videoSupportedFrameRateRanges
            .map { "\(Int($0.minFrameRate))-\(Int($0.maxFrameRate))" }
            .joined(separator: ", ")
        
        self.isBinned = format.isVideoBinned
        self.supportsDepth = !format.supportedDepthDataFormats.isEmpty
        self.supportsMulticam = format.isMultiCamSupported
        
        let colorSpaces = format.supportedColorSpaces
        self.supportsAppleLog = colorSpaces.contains(.appleLog)
        self.supportsHDR = format.isVideoHDRSupported
        self.colorSpaces = colorSpaces.map { describeColorSpace($0) }
    }
}

// MARK: - Format / type description helpers

func describePixelFormat(_ fourCC: OSType) -> (string: String, bitDepth: Int, subsampling: String) {
    let str = fourCCString(fourCC)
    switch fourCC {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        return (str, 8, "4:2:0")
    case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
    kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
        return (str, 10, "4:2:0")
    case kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
    kCVPixelFormatType_422YpCbCr10BiPlanarFullRange:
        return (str, 10, "4:2:2")
    case kCVPixelFormatType_422YpCbCr8, kCVPixelFormatType_422YpCbCr8_yuvs:
        return (str, 8, "4:2:2")
    case kCVPixelFormatType_422YpCbCr16:
        return (str, 16, "4:2:2")
    default:
        return (str, 0, "?")
    }
}

func fourCCString(_ code: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff),
    ]
    let s = String(bytes: bytes, encoding: .ascii) ?? "????"
    return s.trimmingCharacters(in: .whitespaces)
}

func describeColorSpace(_ cs: AVCaptureColorSpace) -> String {
    switch cs {
    case .sRGB: return "sRGB"
    case .P3_D65: return "P3"
    case .HLG_BT2020: return "HLG2020"
    case .appleLog: return "AppleLog"
    case .appleLog2: return "AppleLog2"
    @unknown default: return "unknown(\(cs.rawValue))"
    }
}

func prettyName(for type: AVCaptureDevice.DeviceType) -> String {
    switch type {
    case .builtInWideAngleCamera: return "Main (Wide)"
    case .builtInUltraWideCamera: return "Ultra-Wide"
    case .builtInTelephotoCamera: return "Telephoto"
    case .builtInDualCamera: return "Dual (Main+Tele)"
    case .builtInDualWideCamera: return "Dual Wide (Main+Ultra)"
    case .builtInTripleCamera: return "Triple"
    case .builtInLiDARDepthCamera: return "LiDAR Depth Camera"
    default: return type.rawValue
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
