import Foundation
import AppKit

public struct SiteSearchAction: Identifiable, Equatable {
    public let id: String
    public let siteName: String
    public let query: String
    public let targetURL: URL
    public let iconName: String
    public let domain: String
}

/// Instant "search inside website" templates triggered ONLY when the user types an explicit
/// site keyword followed by search terms (e.g. `gmail invoice`, `drive budget`, `yt swiftui`, `gh seek`).
/// Plain single-word queries like `gmail` do NOT trigger this, letting your Gmail bookmark/top site win cleanly.
public enum QuickSiteSearchEngine {
    private struct Template {
        let triggers: [String]
        let siteName: String
        let domain: String
        let iconName: String
        let urlTemplate: String // `{q}` replaced with URL-encoded query
    }

    private static let templates: [Template] = [
        Template(
            triggers: ["gmail", "mail"],
            siteName: "Gmail",
            domain: "mail.google.com",
            iconName: "envelope.fill",
            urlTemplate: "https://mail.google.com/mail/u/0/#search/{q}"
        ),
        Template(
            triggers: ["drive", "gdrive"],
            siteName: "Google Drive",
            domain: "drive.google.com",
            iconName: "externaldrive.fill.badge.icloud",
            urlTemplate: "https://drive.google.com/drive/search?q={q}"
        ),
        Template(
            triggers: ["calendar", "cal", "gcal"],
            siteName: "Google Calendar",
            domain: "calendar.google.com",
            iconName: "calendar",
            urlTemplate: "https://calendar.google.com/calendar/u/0/r/search?q={q}"
        ),
        Template(
            triggers: ["youtube", "yt"],
            siteName: "YouTube",
            domain: "youtube.com",
            iconName: "play.rectangle.fill",
            urlTemplate: "https://www.youtube.com/results?search_query={q}"
        ),
        Template(
            triggers: ["github", "gh"],
            siteName: "GitHub",
            domain: "github.com",
            iconName: "chevron.left.forwardslash.chevron.right",
            urlTemplate: "https://github.com/search?q={q}"
        ),
        Template(
            triggers: ["google", "g"],
            siteName: "Google",
            domain: "google.com",
            iconName: "globe",
            urlTemplate: "https://www.google.com/search?q={q}"
        ),
        Template(
            triggers: ["maps"],
            siteName: "Google Maps",
            domain: "maps.google.com",
            iconName: "map.fill",
            urlTemplate: "https://www.google.com/maps/search/{q}"
        ),
        Template(
            triggers: ["chatgpt", "gpt"],
            siteName: "ChatGPT",
            domain: "chatgpt.com",
            iconName: "sparkles",
            urlTemplate: "https://chatgpt.com/?q={q}"
        ),
        Template(
            triggers: ["claude"],
            siteName: "Claude",
            domain: "claude.ai",
            iconName: "bubble.left.and.text.bubble.right.fill",
            urlTemplate: "https://claude.ai/new?q={q}"
        ),
        Template(
            triggers: ["linkedin", "li"],
            siteName: "LinkedIn",
            domain: "linkedin.com",
            iconName: "person.2.fill",
            urlTemplate: "https://www.linkedin.com/search/results/all/?keywords={q}"
        ),
        Template(
            triggers: ["amazon", "amz"],
            siteName: "Amazon",
            domain: "amazon.com",
            iconName: "cart.fill",
            urlTemplate: "https://www.amazon.com/s?k={q}"
        )
    ]

    public static func match(rawQuery: String) -> SiteSearchAction? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) else {
            return nil
        }

        let trigger = String(trimmed[..<firstSpace]).lowercased()
        let searchTerms = trimmed[firstSpace...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchTerms.isEmpty else { return nil }

        guard let template = templates.first(where: { $0.triggers.contains(trigger) }) else {
            return nil
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        let encoded = searchTerms.addingPercentEncoding(withAllowedCharacters: allowed) ?? searchTerms
        let finalStr = template.urlTemplate.replacingOccurrences(of: "{q}", with: encoded)
        guard let url = URL(string: finalStr) else { return nil }

        return SiteSearchAction(
            id: "sitesearch_\(template.domain)_\(searchTerms.lowercased())",
            siteName: template.siteName,
            query: searchTerms,
            targetURL: url,
            iconName: template.iconName,
            domain: template.domain
        )
    }
}
