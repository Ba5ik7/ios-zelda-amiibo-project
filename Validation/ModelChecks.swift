import Foundation
import RealityKit

@main
struct ModelChecks {
    @MainActor static func main() async throws {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let catalog = try AmiiboCatalog.bundled(in: bundle)
        let library = ModelLibrary(bundle: bundle)
        for figure in catalog.figures {
            guard let asset = figure.model else { continue }
            let model = try await library.entity(for: asset)
            let bounds = model.visualBounds(relativeTo: model)
            precondition(abs(bounds.extents.y - asset.targetHeightMeters) < 0.001, "Unexpected height")
            precondition(abs(bounds.min.y - asset.verticalOffsetMeters) < 0.001, "Model is not grounded")
            precondition(abs(bounds.center.x) < 0.001 && abs(bounds.center.z) < 0.001, "Model is not centered")
            model.scale *= 2
            let cachedClone = try await library.entity(for: asset)
            precondition(cachedClone !== model && cachedClone.scale == SIMD3<Float>(repeating: 1), "Cached models must be independent")
            print("Validated \(asset.filename): async load, height, base, center, and cache independence.")
        }
        do {
            _ = try await library.entity(for: ModelAsset(filename: "missing-model", targetHeightMeters: 0.12,
                                                         yawDegrees: 0, verticalOffsetMeters: 0))
            preconditionFailure("Missing model did not throw")
        } catch { print("Validated missing-model recovery.") }
    }
}
