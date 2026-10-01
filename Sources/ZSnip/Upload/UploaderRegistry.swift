import Foundation

/// Knows every available uploader and which one is active.
final class UploaderRegistry {
    static let shared = UploaderRegistry()

    /// Uploaders written in Swift. Add yours here, e.g. `MyHostUploader(apiKey: ...)`.
    private let builtIn: [ImageUploader] = []

    private(set) var uploaders: [ImageUploader] = []
    private(set) var loadErrors: [String] = []
    /// Files iCloud Drive hasn't downloaded to this Mac yet.
    private(set) var pendingDownloads: [String] = []

    /// On this Mac only.
    static var localDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZSnip/Uploaders", isDirectory: true)
    }

    /// The user's iCloud Drive, or nil if iCloud Drive is off on this Mac.
    static var iCloudDriveRoot: URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    /// iCloud Drive › ZSnip › Uploaders, synced to the user's other Macs by iCloud Drive itself.
    static var iCloudDirectory: URL? {
        iCloudDriveRoot?.appendingPathComponent("ZSnip/Uploaders", isDirectory: true)
    }

    /// Where uploaders are read from and imported into right now.
    static var configDirectory: URL {
        if Settings.syncUploadersWithICloud, let cloud = iCloudDirectory { return cloud }
        return localDirectory
    }

    /// Turns iCloud Drive sync on or off. Copies uploaders into the new location without
    /// overwriting or deleting anything, so neither side ever loses a file.
    func setICloudSync(_ enabled: Bool) throws {
        guard let cloud = Self.iCloudDirectory else { throw UploaderTransferError.iCloudDriveOff }
        let (from, to) = enabled ? (Self.localDirectory, cloud) : (cloud, Self.localDirectory)
        try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
        for file in Self.jsonFiles(in: from) where !FileManager.default.fileExists(atPath: to.appendingPathComponent(file.lastPathComponent).path) {
            try FileManager.default.copyItem(at: file, to: to.appendingPathComponent(file.lastPathComponent))
        }
        Settings.syncUploadersWithICloud = enabled
        reload()
    }

    static func jsonFiles(in dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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

        // iCloud Drive may keep only a placeholder (".Name.json.icloud") until the file is needed.
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        pendingDownloads = all.filter { $0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent.hasSuffix(".json.icloud") }.map { placeholder in
            try? FileManager.default.startDownloadingUbiquitousItem(at: placeholder)
            return String(placeholder.lastPathComponent.dropFirst().dropLast(".icloud".count))
        }

        for file in Self.jsonFiles(in: dir) {
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
