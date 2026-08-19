import CryptoKit
import CoreImage
import ReplayKit
import UIKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let endpoint = URL(string: "https://calendar.45.32.43.224.sslip.io/nav/api/screen-context")!
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastSentAt = Date.distantPast
    private var lastFingerprint: [UInt8]?
    private var uploadInFlight = false

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {}
    override func broadcastPaused() {}
    override func broadcastResumed() {}
    override func broadcastFinished() {}

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video,
              !uploadInFlight,
              Date().timeIntervalSince(lastSentAt) >= 30,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        let fingerprint = visualFingerprint(cgImage)
        if let previous = lastFingerprint,
           zip(previous, fingerprint).map({ abs(Int($0.0) - Int($0.1)) }).reduce(0, +)
                / max(1, fingerprint.count) < 14 {
            return
        }
        lastSentAt = Date()
        lastFingerprint = fingerprint
        let uiImage = UIImage(cgImage: cgImage)
        guard let data = uiImage.jpegData(compressionQuality: 0.34), data.count < 4 * 1024 * 1024 else { return }
        uploadInFlight = true
        upload(data)
    }

    /// Tiny grayscale signature used only to avoid sending nearly identical
    /// frames. The image itself is never retained by the extension.
    private func visualFingerprint(_ image: CGImage) -> [UInt8] {
        let width = 12, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return pixels
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func upload(_ image: Data) {
        let ts = String(Int(Date().timeIntervalSince1970))
        let key = SymmetricKey(data: Data(Secrets.minimaxApiKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(ts.utf8), using: key)
        let sig = mac.map { String(format: "%02x", $0) }.joined()
        let body: [String: Any] = [
            "ts": ts, "sig": sig, "mime": "image/jpeg",
            "image": image.base64EncodedString()
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else {
            uploadInFlight = false; return
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = encoded
        URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            self?.uploadInFlight = false
        }.resume()
    }
}
