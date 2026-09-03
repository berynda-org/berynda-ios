import Foundation

public enum APIEndpoint: Sendable, Equatable {
    case works(search: String?, page: Int)
    case work(slug: String)
    case editions(workID: UUID)
    case readerInfo(fileID: UUID)
    case readerContent(fileID: UUID, structuredText: Bool)
    case pagePDF(fileID: UUID, page: Int)
    case pageImage(fileID: UUID, page: Int, width: Int)

    func url(relativeTo baseURL: URL) -> URL? {
        let path: String
        var queryItems: [URLQueryItem] = []

        switch self {
        case let .works(search, page):
            path = "works/"
            queryItems.append(.init(name: "page", value: String(page)))
            if let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedSearch.isEmpty {
                // The public catalogue uses its prefix-aware `q` filter.
                // DRF's conventional `search` parameter is not enabled on
                // this endpoint, so sending it silently returned the full
                // catalogue instead of search results.
                queryItems.append(.init(name: "q", value: normalizedSearch))
            }
        case let .work(slug):
            path = "works/\(Self.encodePathSegment(slug))/"
        case let .editions(workID):
            path = "works/\(workID.uuidString.lowercased())/editions/"
        case let .readerInfo(fileID):
            path = "files/\(fileID.uuidString.lowercased())/reader-info/"
        case let .readerContent(fileID, structuredText):
            path = "files/\(fileID.uuidString.lowercased())/reader-content/"
            if structuredText {
                queryItems.append(.init(name: "delivery", value: "json"))
            }
        case let .pagePDF(fileID, page):
            path = "files/\(fileID.uuidString.lowercased())/pages/\(max(page, 1)).pdf"
        case let .pageImage(fileID, page, width):
            path = "files/\(fileID.uuidString.lowercased())/pages/\(max(page, 1))/"
            queryItems.append(.init(name: "width", value: String(min(max(width, 180), 2_000))))
        }

        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url?.absoluteURL
    }

    private static func encodePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
