import Foundation

struct GoogleDriveFileSnapshot: Equatable, Sendable {
    var id: String
    var name: String
    var mimeType: String
    var modifiedTime: Date?
    var webViewLink: String?
    var size: Int?
}

/// Reads opted-in Google Drive files for agent context.
enum GoogleDriveContextReader {
    private static let filesEndpoint = URL(string: "https://www.googleapis.com/drive/v3/files")!

    /// Search the user's Drive. Defaults to the 5 most recently modified files matching the query.
    static func searchFiles(
        for accountID: UUID,
        query: String? = nil,
        maxResults: Int = 5
    ) async -> [GoogleDriveFileSnapshot] {
        var components = URLComponents(url: filesEndpoint, resolvingAgainstBaseURL: true)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "pageSize", value: String(maxResults)),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime,webViewLink,size)"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "spaces", value: "drive"),
        ]
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return [] }

        do {
            let response: FilesListResponse = try await GoogleAPIClient.get(url, for: accountID)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            return response.files.map { file in
                GoogleDriveFileSnapshot(
                    id: file.id,
                    name: file.name,
                    mimeType: file.mimeType,
                    modifiedTime: file.modifiedTime.flatMap { formatter.date(from: $0) },
                    webViewLink: file.webViewLink,
                    size: file.size
                )
            }
        } catch {
            return []
        }
    }

    /// Fetch plain-text or HTML export of a Drive file (Docs, Sheets, Slides, or raw text files).
    static func fetchTextContent(
        for accountID: UUID,
        fileID: String,
        mimeType: String
    ) async -> String? {
        let exportMimeType: String
        switch mimeType {
        case "application/vnd.google-apps.document":
            exportMimeType = "text/plain"
        case "application/vnd.google-apps.spreadsheet":
            exportMimeType = "text/csv"
        case "application/vnd.google-apps.presentation":
            exportMimeType = "text/plain"
        case "text/plain", "text/html", "text/markdown":
            exportMimeType = mimeType
        default:
            return nil
        }

        let endpoint: URL
        if mimeType.hasPrefix("application/vnd.google-apps.") {
            endpoint = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)/export")!
        } else {
            endpoint = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
        if mimeType.hasPrefix("application/vnd.google-apps.") {
            components.queryItems = [URLQueryItem(name: "mimeType", value: exportMimeType)]
        } else {
            components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        }

        guard let url = components.url else { return nil }

        do {
            let data = try await GoogleAPIClient.getData(url, for: accountID)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func contextSection(
        for accountID: UUID,
        maxResults: Int = 5
    ) async -> String? {
        let files = await searchFiles(for: accountID, maxResults: maxResults)
        return contextSection(files: files)
    }

    static func contextSection(files: [GoogleDriveFileSnapshot]) -> String? {
        guard !files.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none

        let lines = files.map { file -> String in
            let date = file.modifiedTime.map { " (modified \(dateFormatter.string(from: $0)))" } ?? ""
            return "- \(file.name)\(date) [id: \(file.id), type: \(file.mimeType)]"
        }

        return """
        ## Google Drive (recent files)
        \(lines.joined(separator: "\n"))

        Google Drive is read only. To read a file's contents, the user can ask about it by name or ID.
        """
    }

    // MARK: - Wire types

    private struct FilesListResponse: Decodable, Sendable {
        var files: [FileItem]
    }

    private struct FileItem: Decodable, Sendable {
        var id: String
        var name: String
        var mimeType: String
        var modifiedTime: String?
        var webViewLink: String?
        var size: Int?
    }
}
