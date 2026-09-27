import Foundation

struct Amiibo: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let imageName: String
    let exclusives: String
    let extras: String
    let qrAliases: [String]
    let model: ModelAsset?

    var qrPayload: String { "zelda-amiibo://figure/\(id)" }
}

struct ModelAsset: Codable, Hashable, Sendable {
    let filename: String
    let targetHeightMeters: Float
    let yawDegrees: Float
    let verticalOffsetMeters: Float
}

struct AmiiboCatalog: Sendable {
    let figures: [Amiibo]

    init(data: Data) throws {
        let decoded = try JSONDecoder().decode([Amiibo].self, from: data)
        guard !decoded.isEmpty,
              Set(decoded.map(\.id)).count == decoded.count,
              decoded.allSatisfy({ !$0.id.isEmpty }) else {
            throw CatalogError.invalidCatalog
        }
        let keys = decoded.flatMap { [$0.id] + $0.qrAliases }
        guard Set(keys).count == keys.count else { throw CatalogError.invalidCatalog }
        for figure in decoded {
            if let model = figure.model {
                guard !model.filename.isEmpty, !model.filename.contains("/"),
                      model.targetHeightMeters.isFinite, model.targetHeightMeters > 0,
                      model.yawDegrees.isFinite, model.verticalOffsetMeters.isFinite else {
                    throw CatalogError.invalidCatalog
                }
            }
        }
        figures = decoded
    }

    static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "amiibos", withExtension: "json") else {
            throw CatalogError.missingCatalog
        }
        return try Self(data: Data(contentsOf: url))
    }

    func figure(for payload: String) -> Amiibo? {
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let figure = figures.first(where: { $0.id == value || $0.qrAliases.contains(value) }) {
            return figure
        }
        // Only resolve our own QR namespace; never load arbitrary URLs or file paths.
        guard let url = URLComponents(string: value), url.scheme == "zelda-amiibo",
              url.host == "figure", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        return figures.first { url.path == "/\($0.id)" }
    }
}

enum CatalogError: LocalizedError {
    case missingCatalog, invalidCatalog
    var errorDescription: String? {
        switch self {
        case .missingCatalog: "The figure catalog is missing. Please reinstall the app."
        case .invalidCatalog: "The figure catalog could not be read."
        }
    }
}
