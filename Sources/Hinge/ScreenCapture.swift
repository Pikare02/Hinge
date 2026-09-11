import ScreenCaptureKit
import CoreMedia
import CoreVideo

enum CaptureError: Error { case noDisplay, noPermission }

/// Streams the main display, minus our own windows, as IOSurface frames.
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "hinge.capture")
    /// Called on a background queue for every complete frame.
    var onFrame: ((IOSurfaceRef) -> Void)?

    func start() async throws {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        // Excluding the whole app covers the overlay and the settings window,
        // and keeps working no matter which of them happens to be on screen.
        let ourApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ourApp, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isComplete,
              let pixels = CMSampleBufferGetImageBuffer(buffer),
              let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue()
        else { return }
        onFrame?(surface)
    }
}

private extension CMSampleBuffer {
    /// ScreenCaptureKit repeats incomplete frames when nothing changed; skip those.
    var isComplete: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}
