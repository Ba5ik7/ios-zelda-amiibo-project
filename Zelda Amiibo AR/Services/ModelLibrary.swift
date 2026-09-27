import RealityKit
import Foundation

@MainActor
final class ModelLibrary {
    private var cache: [String: Entity] = [:]
    private let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    func entity(for asset: ModelAsset) async throws -> Entity {
        if let cached = cache[asset.filename] { return cached.clone(recursive: true) }
        guard let url = bundle.url(forResource: asset.filename, withExtension: "usdz") else {
            throw ModelError.missingFile
        }
        let loaded = try await Entity(contentsOf: url)
        try Task.checkCancellation()
        let root = Entity()
        root.addChild(loaded)
        loaded.orientation = simd_quatf(angle: asset.yawDegrees * .pi / 180, axis: [0, 1, 0]) * loaded.orientation
        let originalBounds = root.visualBounds(relativeTo: root)
        guard originalBounds.extents.y.isFinite, originalBounds.extents.y > 0.000001 else {
            throw ModelError.invalidBounds
        }
        loaded.scale *= SIMD3<Float>(repeating: asset.targetHeightMeters / originalBounds.extents.y)
        let bounds = root.visualBounds(relativeTo: root)
        // Center the scan horizontally and put its lowest visible point on the surface.
        loaded.position += [-bounds.center.x, -bounds.min.y + asset.verticalOffsetMeters, -bounds.center.z]
        cache[asset.filename] = root
        return root.clone(recursive: true)
    }
}

private enum ModelError: LocalizedError {
    case missingFile, invalidBounds
    var errorDescription: String? {
        switch self {
        case .missingFile: "This figure’s 3D model is missing from the app."
        case .invalidBounds: "This 3D model has no usable dimensions."
        }
    }
}
