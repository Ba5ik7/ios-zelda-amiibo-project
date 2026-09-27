import Vision
import CoreVideo
import ImageIO

// ARKit owns immutable camera pixels. Retain only one frame while Vision analyzes it.
nonisolated struct CameraImage: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let orientation: CGImagePropertyOrientation
}

actor QRScanner {
    func payloads(in image: CameraImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cvPixelBuffer: image.pixelBuffer,
                                           orientation: image.orientation, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
