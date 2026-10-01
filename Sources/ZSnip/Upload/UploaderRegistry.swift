import Foundation

/// Knows every available uploader and which one is active.
final class UploaderRegistry {
    static let shared = UploaderRegistry()

    /// Uploaders written in Swift. Add yours here, e.g. `MyHostUploader(apiKey: ...)`.
    private let builtIn: [ImageUploader] = []

    private(set) var uploaders: [ImageUploader] = []
    private(set) var loadErrors: [String] = []

    static var configDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZSnip/Uploaders", isDirectory: true)
    }

    private init() { reload() }

    var active: ImageUploader? {
        guard let id = Settings.activeUploaderID else { return nil }
        return uploaders.first { $0.id == id }
    }

    /// Re-reads JSON uploader configs from disk.
    func reload() {
        var loaded = builtIn
        var errors: [String] = []
        let dir = Self.configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let config = try JSONDecoder().decode(HTTPUploaderConfig.self, from: Data(contentsOf: file))
                loaded.append(HTTPUploader(config: config, id: "json:\(file.lastPathComponent)"))
            } catch {
                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        uploaders = loaded
        loadErrors = errors
    }
}
