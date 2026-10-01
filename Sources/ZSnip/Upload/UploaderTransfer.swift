import AppKit
import UniformTypeIdentifiers

enum UploaderTransferError: LocalizedError {
    case iCloudDriveOff

    var errorDescription: String? {
        switch self {
        case .iCloudDriveOff:
            return "iCloud Drive is off on this Mac. Turn it on in System Settings → [your name] → iCloud → Drive, then try again."
        }
    }
}

/// Export all uploaders to one file and import them back, e.g. to move them to another Mac.
///
/// Export file format:
/// ```json
/// { "format": "zsnip-uploaders", "version": 1, "uploaders": { "Imgur.json": { …config… } } }
/// ```
/// Import also accepts a single uploader config file.
enum UploaderTransfer {
    private static let format = "zsnip-uploaders"

    static func exportAll() {
        let files = UploaderRegistry.jsonFiles(in: UploaderRegistry.configDirectory)
        guard !files.isEmpty else {
            Alerts.show(title: "No uploaders to export", message: "Add an uploader first, or import one.")
            return
        }
        // Raw JSON, so fields this version doesn't know about survive the round trip.
        var uploaders: [String: Any] = [:]
        for file in files {
            if let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) {
                uploaders[file.lastPathComponent] = object
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Export Uploaders"
        panel.message = "This file contains any API keys your uploaders use. Keep it somewhere private."
        panel.nameFieldStringValue = "ZSnip Uploaders.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bundle: [String: Any] = ["format": format, "version": 1, "uploaders": uploaders]
            let data = try JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            Alerts.show(title: "Couldn't export uploaders", message: error.localizedDescription)
        }
    }

    static func importFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Import Uploaders"
        panel.message = "Choose a ZSnip uploaders export, or one or more uploader files."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let result = importFiles(panel.urls, into: UploaderRegistry.configDirectory)
        UploaderRegistry.shared.reload()

        var lines: [String] = []
        if !result.added.isEmpty { lines.append("Added: " + result.added.joined(separator: ", ")) }
        if !result.unchanged.isEmpty { lines.append("Already up to date: " + result.unchanged.joined(separator: ", ")) }
        if !result.problems.isEmpty { lines.append("Skipped:\n" + result.problems.joined(separator: "\n")) }
        let count = result.added.count
        let title = count == 0 ? "No new uploaders imported" : "Imported \(count) uploader\(count == 1 ? "" : "s")"
        Alerts.show(title: title, message: lines.joined(separator: "\n\n"))
    }

    /// Imports export bundles and/or single uploader files into `dir`.
    static func importFiles(_ urls: [URL], into dir: URL) -> (added: [String], unchanged: [String], problems: [String]) {
        var added: [String] = [], unchanged: [String] = [], problems: [String] = []
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for url in urls {
            guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) else {
                problems.append("\(url.lastPathComponent): not a JSON file")
                continue
            }
            if let bundle = object as? [String: Any], bundle["format"] as? String == format,
               let uploaders = bundle["uploaders"] as? [String: Any] {
                for (name, config) in uploaders.sorted(by: { $0.key < $1.key }) {
                    add(config, named: name, into: dir, added: &added, unchanged: &unchanged, problems: &problems)
                }
            } else {
                add(object, named: url.lastPathComponent, into: dir, added: &added, unchanged: &unchanged, problems: &problems)
            }
        }

        return (added, unchanged, problems)
    }

    /// Validates one config and saves it. Never overwrites: an identical file is left alone,
    /// a different one with the same name is saved as "Name 2.json".
    private static func add(_ config: Any, named name: String, into dir: URL,
                            added: inout [String], unchanged: inout [String], problems: inout [String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) else {
            problems.append("\(name): not an uploader")
            return
        }
        let decoded: HTTPUploaderConfig
        do {
            decoded = try JSONDecoder().decode(HTTPUploaderConfig.self, from: data)
        } catch {
            problems.append("\(name): missing \"name\" or \"requestURL\"")
            return
        }

        let base = sanitizedBaseName(name)
        var candidate = dir.appendingPathComponent(base + ".json")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if let existing = try? Data(contentsOf: candidate),
               let existingObject = try? JSONSerialization.jsonObject(with: existing) as? NSDictionary,
               let newObject = config as? NSDictionary, existingObject == newObject {
                unchanged.append(decoded.name)
                return
            }
            candidate = dir.appendingPathComponent("\(base) \(counter).json")
            counter += 1
        }

        do {
            try data.write(to: candidate, options: .atomic)
            added.append(decoded.name)
        } catch {
            problems.append("\(name): \(error.localizedDescription)")
        }
    }

    private static func sanitizedBaseName(_ name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        base = base.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        base = base.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return base.isEmpty ? "Uploader" : base
    }
}
