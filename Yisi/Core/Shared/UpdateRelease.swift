import Foundation

struct UpdateRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    let tag_name: String
    let html_url: URL
    let body: String?
    let assets: [Asset]?

    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    var dmgURL: URL? {
        assets?.first { $0.name.lowercased().hasSuffix(".dmg") && $0.browser_download_url.scheme == "https" }?.browser_download_url
    }

    static func decode(data: Data?, response: URLResponse?, error: Error?) throws -> UpdateRelease {
        if let error { throw error }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, let data else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(UpdateRelease.self, from: data)
        let components = release.version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && Int($0) != nil }),
              release.html_url.scheme == "https" else { throw URLError(.cannotParseResponse) }
        return release
    }

    func isNewer(than local: String) -> Bool {
        let remoteParts = version.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(remoteParts.count, localParts.count) {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }
}
