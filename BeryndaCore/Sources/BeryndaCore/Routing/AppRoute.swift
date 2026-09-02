import Foundation

public enum AppRoute: Equatable, Sendable {
    case work(slug: String)
    case reader(fileID: UUID, page: Int?)

    public init?(url: URL, allowedHosts: Set<String> = ["berynda.org", "www.berynda.org"]) {
        if url.scheme == "https" {
            guard let host = url.host?.lowercased(), allowedHosts.contains(host) else { return nil }
        } else if url.scheme != "berynda" {
            return nil
        }

        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "berynda", let host = url.host, !host.isEmpty {
            parts.insert(host, at: 0)
        }
        guard parts.count >= 2 else { return nil }
        switch parts[0] {
        case "works":
            guard !parts[1].isEmpty else { return nil }
            self = .work(slug: parts[1])
        case "read":
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init)
            if let page, page <= 0 { return nil }
            self = .reader(fileID: id, page: page)
        default:
            return nil
        }
    }
}
