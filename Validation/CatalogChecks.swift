import Foundation
import CoreImage
import Vision
import AppKit

@main
struct CatalogChecks {
    static func main() throws {
        let project = URL(fileURLWithPath: CommandLine.arguments[1])
        let resources = project.appendingPathComponent("Zelda Amiibo AR/Resources")
        let data = try Data(contentsOf: resources.appendingPathComponent("amiibos.json"))
        let catalog = try AmiiboCatalog(data: data)
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }
        check(catalog.figures.count == 26, "All legacy figures must survive the split")
        check(catalog.figures.filter { $0.model != nil }.count == 2, "Only available scans are marked ready")
        for figure in catalog.figures {
            check(catalog.figure(for: figure.qrPayload)?.id == figure.id, "Canonical QR round trip")
            check(catalog.figure(for: figure.id)?.id == figure.id, "Stable ID lookup")
            for alias in figure.qrAliases {
                check(catalog.figure(for: alias)?.id == figure.id, "Legacy QR alias")
            }
            let asset = project.appendingPathComponent("Zelda Amiibo AR/Assets.xcassets/\(figure.imageName).imageset/Contents.json")
            check(FileManager.default.fileExists(atPath: asset.path), "Missing catalog image")
            if let model = figure.model {
                check(FileManager.default.fileExists(atPath: resources.appendingPathComponent(model.filename + ".usdz").path), "Missing bundled scan")
            }
        }
        for invalid in ["", "unknown", "https://example.com/SSB_Young_Link", "file:///SSB_Young_Link.usdz",
                        "zelda-amiibo://figure/not-in-catalog", "zelda-amiibo://other/smash-brothers-young-link",
                        "zelda-amiibo://figure/smash-brothers-young-link?file=bad", "zelda-amiibo://figure/smash-brothers-young-link#extra",
                        "zelda-amiibo://user@figure/smash-brothers-young-link"] {
            check(catalog.figure(for: invalid) == nil, "Unknown or malformed QR accepted: \(invalid)")
        }
        check(catalog.figure(for: "  SSB_Young_Link\n")?.id == "smash-brothers-young-link", "Scanner whitespace")
        let originals = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        var duplicate = originals
        duplicate.append(originals[0])
        do {
            _ = try AmiiboCatalog(data: JSONSerialization.data(withJSONObject: duplicate))
            preconditionFailure("Duplicate IDs accepted")
        } catch { checks += 1 }
        var invalidScale = originals
        var model = invalidScale[0]["model"] as! [String: Any]
        model["targetHeightMeters"] = 0
        invalidScale[0]["model"] = model
        do {
            _ = try AmiiboCatalog(data: JSONSerialization.data(withJSONObject: invalidScale))
            preconditionFailure("Zero height accepted")
        } catch { checks += 1 }

        let context = CIContext()
        for figure in catalog.figures where figure.model != nil {
            let filter = CIFilter(name: "CIQRCodeGenerator")!
            filter.setValue(Data(figure.qrPayload.utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            let code = filter.outputImage!
            let padded = code.composited(over: CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -4, dy: -4)))
            let scaled = padded.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            let image = context.createCGImage(scaled, from: scaled.extent)!
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: image).perform([request])
            check(request.results?.first?.payloadStringValue == figure.qrPayload, "Generated QR must decode")
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = bitmap.representation(using: .png, properties: [:])!
            try png.write(to: project.appendingPathComponent("QR Cards/\(figure.id).png"))
        }
        print("Passed \(checks) catalog, asset, QR routing, and QR image checks.")
    }
}
