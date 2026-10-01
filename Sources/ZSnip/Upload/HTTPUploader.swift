import Foundation

/// A config-driven uploader, similar in spirit to ShareX's custom uploaders.
/// Drop a JSON file in ~/Library/Application Support/ZSnip/Uploaders/ and it shows up in the menu.
///
/// Example (Imgur-style API):
/// ```json
/// {
///   "name": "Imgur",
///   "requestURL": "https://api.imgur.com/3/image",
///   "body": "multipart",
///   "fileFormName": "image",
///   "headers": { "Authorization": "Client-ID YOUR_CLIENT_ID" },
///   "urlJSONPath": "data.link"
/// }
/// ```
struct HTTPUploaderConfig: Codable {
    enum Body: String, Codable {
        /// multipart/form-data with the image under `fileFormName` plus any `formFields`.
        case multipart
        /// The raw PNG bytes as the request body.
        case binary
    }

    var name: String
    var requestURL: String
    var method: String?
    var body: Body?
    var fileFormName: String?
    var headers: [String: String]?
    var formFields: [String: String]?
    /// Dot path into the JSON response, e.g. "data.link" or "files.0.url".
    /// Omit it if the response body is the URL as plain text.
    var urlJSONPath: String?
    var deletionURLJSONPath: String?
    var thumbnailURLJSONPath: String?
}

struct HTTPUploader: ImageUploader {
    let config: HTTPUploaderConfig
    let id: String

    var displayName: String { config.name }

    init(config: HTTPUploaderConfig, id: String) {
        self.config = config
        self.id = id
    }

    func upload(_ payload: UploadPayload) async throws -> UploadResult {
        guard let endpoint = URL(string: config.requestURL) else {
            throw UploadError.invalidConfiguration("requestURL isn't a valid URL")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = config.method ?? "POST"
        for (field, value) in config.headers ?? [:] { request.setValue(value, forHTTPHeaderField: field) }

        switch config.body ?? .multipart {
        case .multipart:
            let boundary = "ZSnip-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipartBody(payload: payload, boundary: boundary)
        case .binary:
            request.setValue(payload.mimeType, forHTTPHeaderField: "Content-Type")
            request.httpBody = payload.pngData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(status) else { throw UploadError.http(status: status, body: text) }

        guard let urlPath = config.urlJSONPath else {
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil else {
                throw UploadError.unexpectedResponse("expected a URL, got: \(text.prefix(200))")
            }
            return UploadResult(url: url)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw UploadError.unexpectedResponse("response isn't JSON: \(text.prefix(200))")
        }
        guard let url = Self.lookup(urlPath, in: json).flatMap(URL.init(string:)) else {
            throw UploadError.unexpectedResponse("no URL at \"\(urlPath)\" in \(text.prefix(300))")
        }
        return UploadResult(
            url: url,
            deletionURL: config.deletionURLJSONPath.flatMap { Self.lookup($0, in: json) }.flatMap(URL.init(string:)),
            thumbnailURL: config.thumbnailURLJSONPath.flatMap { Self.lookup($0, in: json) }.flatMap(URL.init(string:))
        )
    }

    private func multipartBody(payload: UploadPayload, boundary: String) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in config.formFields ?? [:] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(config.fileFormName ?? "file")\"; filename=\"\(payload.filename)\"\r\n")
        append("Content-Type: \(payload.mimeType)\r\n\r\n")
        body.append(payload.pngData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Resolves "a.b.0.c" against decoded JSON; numeric components index arrays.
    static func lookup(_ path: String, in json: Any) -> String? {
        var node: Any? = json
        for key in path.split(separator: ".").map(String.init) {
            if let dict = node as? [String: Any] {
                node = dict[key]
            } else if let array = node as? [Any], let index = Int(key), array.indices.contains(index) {
                node = array[index]
            } else {
                return nil
            }
        }
        switch node {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}
