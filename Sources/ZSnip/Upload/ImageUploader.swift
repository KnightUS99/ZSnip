import Foundation

/// What an uploader receives.
struct UploadPayload {
    let pngData: Data
    let filename: String      // e.g. "ZSnip-2026-09-30-154210.png"
    let mimeType = "image/png"
}

/// What an uploader returns. Only `url` is required; the rest are used if a provider supplies them.
struct UploadResult {
    let url: URL
    var deletionURL: URL?
    var thumbnailURL: URL?
}

enum UploadError: LocalizedError {
    case http(status: Int, body: String)
    case unexpectedResponse(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "Server returned HTTP \(status).\n\n\(body.prefix(500))"
        case .unexpectedResponse(let detail): return "Couldn't read the upload response: \(detail)"
        case .invalidConfiguration(let detail): return "Uploader is misconfigured: \(detail)"
        }
    }
}

/// An image host. Implement this in Swift for hosts that need custom logic (OAuth,
/// multi-step uploads, signed requests, …). Simple "POST a file, read a URL back" hosts
/// don't need code — describe them with a JSON file instead (see `HTTPUploader`).
protocol ImageUploader {
    /// Stable identifier, persisted as the user's chosen destination.
    var id: String { get }
    /// Shown in the menu bar's "Upload Destination" menu.
    var displayName: String { get }

    func upload(_ payload: UploadPayload) async throws -> UploadResult
}
