import Foundation

enum SafeLinks {
    static let schemes: Set<String> = ["https", "zoommtg", "msteams"]
    static func validate(_ raw: String) -> URL? {
        guard !raw.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }),
              let components = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              let scheme = components.scheme?.lowercased(), schemes.contains(scheme),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        if scheme == "zoommtg", !(host == "zoom.us" || host.hasSuffix(".zoom.us")) { return nil }
        if scheme == "msteams", !(host == "teams.microsoft.com" || host == "teams.live.com") { return nil }
        return url
    }
    static func extract(structured: String?, notes: String?) -> [URL] {
        var result: [URL] = []
        if let structured, let url = validate(structured) { result.append(url) }
        if let notes, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = notes as NSString
            for match in detector.matches(in: notes, range: NSRange(location: 0, length: ns.length)) {
                if let url = validate(ns.substring(with: match.range)), !result.contains(url) { result.append(url) }
            }
        }
        return result
    }
}
