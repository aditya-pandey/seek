import AppKit
import Foundation
import SQLite3

public enum BrowserSource: String, CaseIterable, Equatable {
    case chrome  = "Google Chrome"
    case brave   = "Brave"
    case arc     = "Arc"
    case edge    = "Microsoft Edge"
    case vivaldi = "Vivaldi"
    case firefox = "Firefox"
    case safari  = "Safari"

    public var bundleIdentifier: String {
        switch self {
        case .chrome:  return "com.google.Chrome"
        case .brave:   return "com.brave.Browser"
        case .arc:     return "company.thebrowser.Browser"
        case .edge:    return "com.microsoft.edgemac"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .firefox: return "org.mozilla.firefox"
        case .safari:  return "com.apple.Safari"
        }
    }

    public var shortName: String {
        switch self {
        case .chrome:  return "Chrome"
        case .brave:   return "Brave"
        case .arc:     return "Arc"
        case .edge:    return "Edge"
        case .vivaldi: return "Vivaldi"
        case .firefox: return "Firefox"
        case .safari:  return "Safari"
        }
    }

    /// Chromium browsers that support `--profile-directory=<dir>` ProcessSingleton tab routing
    public var supportsChromiumProfileFlag: Bool {
        switch self {
        case .chrome, .brave, .edge, .vivaldi: return true
        case .arc, .firefox, .safari:          return false
        }
    }

    public var chromiumAppSupportRelPath: String? {
        switch self {
        case .chrome:  return "Google/Chrome"
        case .brave:   return "BraveSoftware/Brave-Browser"
        case .arc:     return "Arc/User Data"
        case .edge:    return "Microsoft Edge"
        case .vivaldi: return "Vivaldi"
        case .firefox, .safari: return nil
        }
    }
}

public struct BrowserSiteItem: Identifiable, Equatable {
    public let id: String // Unique per (canonicalURL, source, profileDirectory)
    public let canonicalURL: String
    public let url: URL
    public let title: String
    public let titleLower: String
    public let titleNormalized: String
    public let domain: String
    public let domainLower: String
    public let urlLower: String
    public let wordTokensLower: [String]
    public let initialsLower: String
    public let folderPath: String?
    public let folderPathLower: String
    public let isBookmark: Bool
    public let isRootApp: Bool
    public let visitCount: Int
    public let typedCount: Int
    public let lastVisited: Date
    public let source: BrowserSource
    /// Exact profile directory name on disk (e.g. "Default", "Profile 1") — safe for `--profile-directory=`
    public let profileDirectory: String?
    /// Human-readable profile label from Chromium Local State (e.g. "Work", "Personal")
    public let profileDisplayName: String?
    public let profileDisplayNameLower: String
    public let hasMultipleProfiles: Bool
    public let relativeTimeString: String

    public init(
        url: URL,
        title: String,
        folderPath: String? = nil,
        isBookmark: Bool,
        visitCount: Int = 0,
        typedCount: Int = 0,
        lastVisited: Date = .distantPast,
        source: BrowserSource,
        profileDirectory: String? = nil,
        profileDisplayName: String? = nil,
        hasMultipleProfiles: Bool = false,
        canonicalID: String? = nil
    ) {
        let canonical = canonicalID ?? BrowserIndexManager.canonicalizeURL(url)
        self.canonicalURL = canonical
        let profileKey = profileDirectory ?? ""
        self.id = "\(canonical)||\(source.rawValue)||\(profileKey)"
        self.url = url
        let host = (url.host ?? "").lowercased()
        let cleanDomain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        self.domain = cleanDomain
        self.domainLower = cleanDomain

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? (cleanDomain.isEmpty ? url.absoluteString : cleanDomain) : trimmedTitle
        self.title = resolvedTitle
        self.titleLower = resolvedTitle.lowercased()
        self.titleNormalized = IndexedFileItem.normalizeCompact(self.titleLower)
        self.urlLower = canonical.lowercased()

        let profLabel = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.profileDirectory = profileDirectory
        self.profileDisplayName = (profLabel?.isEmpty == false) ? profLabel : nil
        self.profileDisplayNameLower = (self.profileDisplayName ?? "").lowercased()
        self.hasMultipleProfiles = hasMultipleProfiles

        let words = IndexedFileItem.extractWords(from: "\(resolvedTitle) \(cleanDomain) \(self.profileDisplayName ?? "")")
        self.wordTokensLower = words
        self.initialsLower = IndexedFileItem.computeInitials(fromWords: IndexedFileItem.extractWords(from: resolvedTitle))

        self.folderPath = folderPath
        self.folderPathLower = (folderPath ?? "").lowercased()
        self.isBookmark = isBookmark
        self.isRootApp = BrowserIndexManager.isRootOrHomeURL(url, cleanDomain: cleanDomain)
        self.visitCount = visitCount
        self.typedCount = typedCount
        self.lastVisited = lastVisited
        self.source = source
        self.relativeTimeString = (lastVisited == .distantPast)
            ? ""
            : IndexedFileItem.fastRelativeTime(from: lastVisited)
    }

    public var displaySubtitle: String {
        var parts: [String] = [domain]
        if hasMultipleProfiles, let prof = profileDisplayName, !prof.isEmpty {
            parts.append(prof)
        }
        if let folder = folderPath, !folder.isEmpty {
            parts.append(folder)
        }
        return parts.joined(separator: " · ")
    }

    public var openButtonLabel: String {
        if hasMultipleProfiles, let prof = profileDisplayName, !prof.isEmpty {
            return "Open in \(source.shortName) (\(prof))"
        }
        return "Open in \(source.shortName)"
    }
}

/// Zero-lag, pre-scaled 32x32 browser icon cache
public final class BrowserIconCache {
    public static let shared = BrowserIconCache()
    private var cache: [BrowserSource: NSImage] = [:]
    private let lock = NSLock()
    private lazy var fallbackGlobe: NSImage = {
        let img = NSImage(systemSymbolName: "globe", accessibilityDescription: "Web") ?? NSImage()
        return img
    }()

    public func icon(for source: BrowserSource) -> NSImage {
        lock.lock()
        if let cached = cache[source] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved: NSImage
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) {
            resolved = Self.resized(NSWorkspace.shared.icon(forFile: appURL.path))
        } else {
            resolved = fallbackGlobe
        }

        lock.lock()
        cache[source] = resolved
        lock.unlock()
        return resolved
    }

    public func prewarmAll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for src in BrowserSource.allCases {
                _ = self?.icon(for: src)
            }
        }
    }

    private static func resized(_ image: NSImage, size: CGFloat = 32) -> NSImage {
        let target = NSSize(width: size, height: size)
        let out = NSImage(size: target)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        out.unlockFocus()
        return out
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Multi-Browser Bookmarks & Top Visited History Indexer
// ─────────────────────────────────────────────────────────────────────────

public final class BrowserIndexManager {
    public static let shared = BrowserIndexManager()

    private let lock = NSLock()
    private var cachedSites: [BrowserSiteItem] = []
    private var lastIndexTime: Date = .distantPast
    private var isIndexing: Bool = false

    private let indexerQueue = DispatchQueue(label: "com.local.Seek.BrowserIndexer", qos: .utility)

    /// High-signal root web apps whose root URL should surface cleanly above individual threads/pages
    private static let wellKnownWebAppDomains: Set<String> = [
        "mail.google.com", "calendar.google.com", "drive.google.com", "docs.google.com",
        "sheets.google.com", "slides.google.com", "meet.google.com", "github.com",
        "figma.com", "notion.so", "chatgpt.com", "claude.ai", "linear.app",
        "youtube.com", "linkedin.com", "slack.com", "jira.atlassian.com",
        "teams.microsoft.com", "teams.cloud.microsoft", "outlook.office.com",
        "x.com", "twitter.com", "reddit.com", "whatsapp.com", "web.whatsapp.com",
        "spotify.com", "open.spotify.com", "vercel.com", "netlify.com"
    ]

    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "si", "igshid", "trk"
    ]

    private init() {}

    public func currentSnapshot() -> [BrowserSiteItem] {
        lock.lock()
        let copy = cachedSites
        lock.unlock()
        return copy
    }

    /// Finds the highest-engagement browser + existing profile directory for a domain (e.g. `mail.google.com`)
    /// so `QuickSiteSearchEngine` (`gmail invoice`, `drive budget`) routes into the user's actual Chrome profile!
    public func preferredBrowserAndProfile(forDomain domain: String) -> (source: BrowserSource, profileDirectory: String?)? {
        let lowerDomain = domain.lowercased()
        let sites = currentSnapshot()
        let matching = sites.filter { $0.domainLower == lowerDomain || $0.domainLower.hasSuffix("." + lowerDomain) }
        guard let best = matching.max(by: { a, b in
            let aScore = (a.isBookmark ? 60 : 0) + a.visitCount + a.typedCount * 5
            let bScore = (b.isBookmark ? 60 : 0) + b.visitCount + b.typedCount * 5
            if aScore != bScore { return aScore < bScore }
            return a.lastVisited < b.lastVisited
        }) else {
            return nil
        }
        return (best.source, best.profileDirectory)
    }

    /// Verifies that a Chromium profile folder physically exists on disk before passing `--profile-directory=`
    /// (guarantees Seek can NEVER accidentally create a new profile directory!).
    public static func chromiumProfileExists(source: BrowserSource, profileDirectory: String) -> Bool {
        guard source.supportsChromiumProfileFlag, let relPath = source.chromiumAppSupportRelPath else {
            return false
        }
        let dirURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(relPath)
            .appendingPathComponent(profileDirectory)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Parses Chromium `Local State` JSON to map disk profile folder names (`Default`, `Profile 1`)
    /// to the user's real profile labels (`Work`, `Personal`, etc.).
    public static func parseChromiumLocalState(_ data: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return [:]
        }

        var result: [String: String] = [:]
        for (dirName, rawVal) in infoCache {
            guard let info = rawVal as? [String: Any] else { continue }
            let rawName = (info["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let shortcutName = (info["shortcut_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let gaiaGiven = (info["gaia_given_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let gaiaName = (info["gaia_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let isGenericName = rawName.isEmpty || rawName.hasPrefix("Person ") || rawName == "Your Chrome"
            if !isGenericName {
                result[dirName] = rawName
            } else if !shortcutName.isEmpty && !shortcutName.hasPrefix("Person ") {
                result[dirName] = shortcutName
            } else if !gaiaGiven.isEmpty {
                result[dirName] = gaiaGiven
            } else if !gaiaName.isEmpty {
                result[dirName] = gaiaName
            } else if !rawName.isEmpty {
                result[dirName] = rawName
            } else {
                result[dirName] = dirName
            }
        }
        return result
    }

    public func refreshIfNeeded(force: Bool = false, completion: (() -> Void)? = nil) {
        lock.lock()
        let running = isIndexing
        let isEmpty = cachedSites.isEmpty
        let elapsed = Date().timeIntervalSince(lastIndexTime)
        guard !running && (force || isEmpty || elapsed > 300.0) else {
            lock.unlock()
            return
        }
        isIndexing = true
        lock.unlock()

        BrowserIconCache.shared.prewarmAll()

        indexerQueue.async { [weak self] in
            guard let self = self else { return }
            let items = self.collectAllBrowsers()
            let merged = Self.deduplicateAndMerge(items)

            self.lock.lock()
            self.cachedSites = merged
            self.lastIndexTime = Date()
            self.isIndexing = false
            self.lock.unlock()

            completion?()
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - URL Normalization & Noise Filtering
    // ─────────────────────────────────────────────────────────────

    public static func isNoisyURL(_ rawURL: String) -> Bool {
        let lower = rawURL.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return true // rejects chrome://, about:, file://, javascript:, data:, chrome-extension://
        }
        let noisyFragments = [
            "/oauth", "/oauth2", "/auth/callback", "/login/callback", "/sso/",
            "accounts.google.com/servicelogin", "accounts.google.com/v3/signin",
            "accounts.google.com/interactive", "login.microsoftonline.com/",
            "google.com/url?", "google.com/sorry/", "safelinks.protection.outlook.com"
        ]
        for frag in noisyFragments where lower.contains(frag) {
            return true
        }
        return false
    }

    public static func canonicalizeURL(_ url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        comps.scheme = (comps.scheme ?? "https").lowercased()
        if let host = comps.host?.lowercased() {
            comps.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if let items = comps.queryItems {
            let cleanItems = items.filter { !trackingParams.contains($0.name.lowercased()) }
            comps.queryItems = cleanItems.isEmpty ? nil : cleanItems
        }
        if comps.path == "/" {
            comps.path = ""
        } else if comps.path.hasSuffix("/") {
            comps.path = String(comps.path.dropLast())
        }
        // Strip empty fragments
        if comps.fragment?.isEmpty == true {
            comps.fragment = nil
        }
        return comps.string ?? url.absoluteString
    }

    public static func isRootOrHomeURL(_ url: URL, cleanDomain: String) -> Bool {
        let path = url.path
        let isShallow = (path.isEmpty || path == "/" || path == "/mail/u/0" || path == "/mail/u/0/" || path == "/drive/my-drive")
        if isShallow && (url.query == nil || url.query?.isEmpty == true) {
            return true
        }
        if wellKnownWebAppDomains.contains(cleanDomain) && path.count <= 14 && (url.query == nil) {
            return true
        }
        return false
    }

    public static func deduplicateAndMerge(_ rawItems: [BrowserSiteItem]) -> [BrowserSiteItem] {
        var map: [String: BrowserSiteItem] = [:]
        map.reserveCapacity(rawItems.count)

        for item in rawItems {
            if let existing = map[item.id] {
                let mergedBookmark = existing.isBookmark || item.isBookmark
                let mergedVisits = max(existing.visitCount, item.visitCount)
                let mergedTyped = max(existing.typedCount, item.typedCount)
                let mergedDate = max(existing.lastVisited, item.lastVisited)
                let mergedFolder = existing.folderPath ?? item.folderPath

                // Prefer bookmark title/source when available, otherwise higher visit count
                let useIncomingPrimary = (!existing.isBookmark && item.isBookmark)
                    || (existing.isBookmark == item.isBookmark && item.visitCount > existing.visitCount)
                let primary = useIncomingPrimary ? item : existing
                let bestTitle = (primary.title != primary.domain && !primary.title.isEmpty) ? primary.title : existing.title

                map[item.id] = BrowserSiteItem(
                    url: primary.url,
                    title: bestTitle,
                    folderPath: mergedFolder,
                    isBookmark: mergedBookmark,
                    visitCount: mergedVisits,
                    typedCount: mergedTyped,
                    lastVisited: mergedDate,
                    source: primary.source,
                    profileDirectory: primary.profileDirectory ?? existing.profileDirectory,
                    profileDisplayName: primary.profileDisplayName ?? existing.profileDisplayName,
                    hasMultipleProfiles: primary.hasMultipleProfiles || existing.hasMultipleProfiles,
                    canonicalID: item.canonicalURL
                )
            } else {
                map[item.id] = item
            }
        }

        return Array(map.values).sorted { a, b in
            if a.isBookmark != b.isBookmark { return a.isBookmark }
            if a.visitCount != b.visitCount { return a.visitCount > b.visitCount }
            return a.lastVisited > b.lastVisited
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Multi-Browser Discovery
    // ─────────────────────────────────────────────────────────────

    private func collectAllBrowsers() -> [BrowserSiteItem] {
        let fm = FileManager.default
        let appSupport = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        var collected: [BrowserSiteItem] = []

        // 1. Chromium-based browsers (Chrome, Brave, Arc, Edge, Vivaldi)
        let chromiumRoots: [(BrowserSource, String)] = [
            (.chrome,  "Google/Chrome"),
            (.brave,   "BraveSoftware/Brave-Browser"),
            (.arc,     "Arc/User Data"),
            (.edge,    "Microsoft Edge"),
            (.vivaldi, "Vivaldi")
        ]

        for (source, relPath) in chromiumRoots {
            let rootURL = appSupport.appendingPathComponent(relPath)
            guard fm.fileExists(atPath: rootURL.path) else { continue }
            let localStateURL = rootURL.appendingPathComponent("Local State")
            let profileNames: [String: String] = (try? Data(contentsOf: localStateURL))
                .map { Self.parseChromiumLocalState($0) } ?? [:]

            let profiles = discoverChromiumProfiles(in: rootURL, fm: fm)
            let multiProfile = profiles.count > 1
            for profileDir in profiles {
                let dirName = profileDir.lastPathComponent
                let displayName = profileNames[dirName] ?? dirName
                let bookmarksURL = profileDir.appendingPathComponent("Bookmarks")
                if let data = try? Data(contentsOf: bookmarksURL) {
                    collected.append(contentsOf: Self.parseChromiumBookmarksData(
                        data,
                        source: source,
                        profileDirectory: dirName,
                        profileDisplayName: displayName,
                        hasMultipleProfiles: multiProfile
                    ))
                }
                let historyURL = profileDir.appendingPathComponent("History")
                if fm.fileExists(atPath: historyURL.path) {
                    collected.append(contentsOf: Self.parseChromiumHistorySQLite(
                        at: historyURL,
                        source: source,
                        profileDirectory: dirName,
                        profileDisplayName: displayName,
                        hasMultipleProfiles: multiProfile
                    ))
                }
            }
        }

        // 2. Arc Pinned Spaces (`~/Library/Application Support/Arc/StorableSidebar.json`)
        let arcSidebar = appSupport.appendingPathComponent("Arc/StorableSidebar.json")
        if let data = try? Data(contentsOf: arcSidebar) {
            collected.append(contentsOf: Self.parseArcSidebarData(data))
        }

        // 3. Firefox (`~/Library/Application Support/Firefox/Profiles/*/places.sqlite`)
        let firefoxProfilesRoot = appSupport.appendingPathComponent("Firefox/Profiles")
        if let profileDirs = try? fm.contentsOfDirectory(
            at: firefoxProfilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for dir in profileDirs {
                let placesURL = dir.appendingPathComponent("places.sqlite")
                if fm.fileExists(atPath: placesURL.path) {
                    collected.append(contentsOf: Self.parseFirefoxPlacesSQLite(at: placesURL, profileName: dir.lastPathComponent))
                }
            }
        }

        // 4. Safari (Optional — macOS protects ~/Library/Safari behind Full Disk Access; fail silently on EPERM)
        let safariDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")
        let safariBookmarks = safariDir.appendingPathComponent("Bookmarks.plist")
        if fm.isReadableFile(atPath: safariBookmarks.path),
           let data = try? Data(contentsOf: safariBookmarks) {
            collected.append(contentsOf: Self.parseSafariBookmarksData(data))
        }
        let safariHistory = safariDir.appendingPathComponent("History.db")
        if fm.isReadableFile(atPath: safariHistory.path) {
            collected.append(contentsOf: Self.parseSafariHistorySQLite(at: safariHistory))
        }

        return collected
    }

    private func discoverChromiumProfiles(in rootURL: URL, fm: FileManager) -> [URL] {
        guard let children = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.filter { dir in
            let name = dir.lastPathComponent
            guard name == "Default" || name.hasPrefix("Profile ") else { return false }
            let hasBM = fm.fileExists(atPath: dir.appendingPathComponent("Bookmarks").path)
            let hasHist = fm.fileExists(atPath: dir.appendingPathComponent("History").path)
            return hasBM || hasHist
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Chromium Bookmarks JSON Parser
    // ─────────────────────────────────────────────────────────────

    public static func parseChromiumBookmarksData(
        _ data: Data,
        source: BrowserSource,
        profileDirectory: String? = nil,
        profileDisplayName: String? = nil,
        hasMultipleProfiles: Bool = false
    ) -> [BrowserSiteItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else {
            return []
        }

        var items: [BrowserSiteItem] = []

        func walk(node: [String: Any], folderTrail: [String]) {
            let type = node["type"] as? String ?? ""
            let name = (node["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if type == "url",
               let urlStr = node["url"] as? String,
               !isNoisyURL(urlStr),
               let url = URL(string: urlStr) {
                let dateAdded: Date
                if let rawStr = node["date_added"] as? String, let micros = Int64(rawStr), micros > 0 {
                    dateAdded = chromiumTimestampToDate(micros)
                } else {
                    dateAdded = .distantPast
                }
                let folder = folderTrail.isEmpty ? nil : folderTrail.joined(separator: " / ")
                items.append(
                    BrowserSiteItem(
                        url: url,
                        title: name,
                        folderPath: folder,
                        isBookmark: true,
                        visitCount: 0,
                        typedCount: 0,
                        lastVisited: dateAdded,
                        source: source,
                        profileDirectory: profileDirectory,
                        profileDisplayName: profileDisplayName,
                        hasMultipleProfiles: hasMultipleProfiles
                    )
                )
            } else if let children = node["children"] as? [[String: Any]] {
                let skipRootNames: Set<String> = ["Bookmarks Bar", "Bookmarks bar", "Other Bookmarks", "Other bookmarks", "Mobile Bookmarks", "Synced Bookmarks"]
                let nextTrail = (!name.isEmpty && !skipRootNames.contains(name)) ? (folderTrail + [name]) : folderTrail
                for child in children {
                    walk(node: child, folderTrail: nextTrail)
                }
            }
        }

        for (_, value) in roots {
            if let dict = value as? [String: Any] {
                walk(node: dict, folderTrail: [])
            }
        }
        return items
    }

    /// Parses Arc pinned / favorite tabs from StorableSidebar.json
    public static func parseArcSidebarData(_ data: Data) -> [BrowserSiteItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [Any] else {
            return []
        }

        var items: [BrowserSiteItem] = []
        for entry in containers {
            guard let dict = entry as? [String: Any],
                  let rawItems = dict["items"] as? [Any] else { continue }
            for raw in rawItems {
                guard let itemDict = raw as? [String: Any],
                      let dataObj = itemDict["data"] as? [String: Any],
                      let tab = dataObj["tab"] as? [String: Any],
                      let urlStr = tab["savedURL"] as? String,
                      !isNoisyURL(urlStr),
                      let url = URL(string: urlStr) else { continue }
                let title = (itemDict["title"] as? String) ?? (tab["savedTitle"] as? String) ?? ""
                items.append(
                    BrowserSiteItem(
                        url: url,
                        title: title,
                        folderPath: "Arc Pinned",
                        isBookmark: true,
                        source: .arc
                    )
                )
            }
        }
        return items
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Safe Copy-Then-Read SQLite Helper (Zero Lock Contention)
    // ─────────────────────────────────────────────────────────────

    private static func withSafeSQLiteCopy<T>(of dbURL: URL, _ body: (OpaquePointer) -> T) -> T? {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seek_db_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        defer { try? fm.removeItem(at: tempDir) }

        let dstDB = tempDir.appendingPathComponent(dbURL.lastPathComponent)
        do {
            try fm.copyItem(at: dbURL, to: dstDB)
        } catch {
            return nil
        }

        // Also copy companion WAL / SHM files if present so recently visited sites are captured!
        for suffix in ["-wal", "-shm"] {
            let srcSide = URL(fileURLWithPath: dbURL.path + suffix)
            if fm.fileExists(atPath: srcSide.path) {
                let dstSide = URL(fileURLWithPath: dstDB.path + suffix)
                try? fm.copyItem(at: srcSide, to: dstSide)
            }
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dstDB.path, &db, flags, nil) == SQLITE_OK, let handle = db else {
            if let db = db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(handle) }
        return body(handle)
    }

    /// Chromium timestamps are microseconds since Jan 1, 1601 UTC
    public static func chromiumTimestampToDate(_ microsSince1601: Int64) -> Date {
        guard microsSince1601 > 0 else { return .distantPast }
        let unixSeconds = (Double(microsSince1601) / 1_000_000.0) - 11_644_473_600.0
        guard unixSeconds > 0 && unixSeconds < 4_102_444_800.0 else { return .distantPast }
        return Date(timeIntervalSince1970: unixSeconds)
    }

    public static func parseChromiumHistorySQLite(
        at historyURL: URL,
        source: BrowserSource,
        profileDirectory: String? = nil,
        profileDisplayName: String? = nil,
        hasMultipleProfiles: Bool = false,
        limit: Int = 1200
    ) -> [BrowserSiteItem] {
        return withSafeSQLiteCopy(of: historyURL) { db in
            let sql = """
            SELECT url, title, visit_count, typed_count, last_visit_time
            FROM urls
            WHERE hidden = 0 AND visit_count >= 2
            ORDER BY (typed_count * 10 + visit_count) DESC, last_visit_time DESC
            LIMIT ?1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                return []
            }
            defer { sqlite3_finalize(s) }
            sqlite3_bind_int(s, 1, Int32(limit))

            var items: [BrowserSiteItem] = []
            while sqlite3_step(s) == SQLITE_ROW {
                guard let urlC = sqlite3_column_text(s, 0) else { continue }
                let urlStr = String(cString: urlC)
                guard !isNoisyURL(urlStr), let url = URL(string: urlStr) else { continue }

                let title = sqlite3_column_text(s, 1).map { String(cString: $0) } ?? ""
                let visitCount = Int(sqlite3_column_int64(s, 2))
                let typedCount = Int(sqlite3_column_int64(s, 3))
                let lastMicros = sqlite3_column_int64(s, 4)

                items.append(
                    BrowserSiteItem(
                        url: url,
                        title: title,
                        folderPath: nil,
                        isBookmark: false,
                        visitCount: visitCount,
                        typedCount: typedCount,
                        lastVisited: chromiumTimestampToDate(lastMicros),
                        source: source,
                        profileDirectory: profileDirectory,
                        profileDisplayName: profileDisplayName,
                        hasMultipleProfiles: hasMultipleProfiles
                    )
                )
            }
            return items
        } ?? []
    }

    public static func parseFirefoxPlacesSQLite(
        at placesURL: URL,
        profileName: String? = nil,
        limit: Int = 1200
    ) -> [BrowserSiteItem] {
        return withSafeSQLiteCopy(of: placesURL) { db in
            let sql = """
            SELECT p.url, COALESCE(b.title, p.title, ''), p.visit_count, p.last_visit_date,
                   CASE WHEN b.id IS NOT NULL THEN 1 ELSE 0 END AS is_bm
            FROM moz_places p
            LEFT JOIN moz_bookmarks b ON b.fk = p.id AND b.type = 1
            WHERE p.hidden = 0 AND (p.visit_count >= 2 OR b.id IS NOT NULL)
            ORDER BY is_bm DESC, p.frecency DESC
            LIMIT ?1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                return []
            }
            defer { sqlite3_finalize(s) }
            sqlite3_bind_int(s, 1, Int32(limit))

            var items: [BrowserSiteItem] = []
            while sqlite3_step(s) == SQLITE_ROW {
                guard let urlC = sqlite3_column_text(s, 0) else { continue }
                let urlStr = String(cString: urlC)
                guard !isNoisyURL(urlStr), let url = URL(string: urlStr) else { continue }

                let title = sqlite3_column_text(s, 1).map { String(cString: $0) } ?? ""
                let visitCount = Int(sqlite3_column_int64(s, 2))
                let lastMicros = sqlite3_column_int64(s, 3)
                let isBookmark = sqlite3_column_int(s, 4) != 0
                let lastDate = lastMicros > 0
                    ? Date(timeIntervalSince1970: Double(lastMicros) / 1_000_000.0)
                    : .distantPast

                items.append(
                    BrowserSiteItem(
                        url: url,
                        title: title,
                        folderPath: nil,
                        isBookmark: isBookmark,
                        visitCount: visitCount,
                        typedCount: 0,
                        lastVisited: lastDate,
                        source: .firefox,
                        profileDirectory: profileName,
                        profileDisplayName: profileName
                    )
                )
            }
            return items
        } ?? []
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Safari Bookmarks.plist & History.db Parsers
    // ─────────────────────────────────────────────────────────────

    public static func parseSafariBookmarksData(_ data: Data) -> [BrowserSiteItem] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return []
        }
        var items: [BrowserSiteItem] = []

        func walk(node: [String: Any], trail: [String]) {
            let type = node["WebBookmarkType"] as? String ?? ""
            if type == "WebBookmarkTypeLeaf",
               let urlStr = node["URLString"] as? String,
               !isNoisyURL(urlStr),
               let url = URL(string: urlStr) {
                let uriDict = node["URIDictionary"] as? [String: Any]
                let title = (uriDict?["title"] as? String) ?? ""
                let folder = trail.isEmpty ? nil : trail.joined(separator: " / ")
                items.append(
                    BrowserSiteItem(
                        url: url,
                        title: title,
                        folderPath: folder,
                        isBookmark: true,
                        source: .safari
                    )
                )
            } else if let children = node["Children"] as? [[String: Any]] {
                let name = (node["Title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let skip: Set<String> = ["BookmarksBar", "BookmarksMenu", "com.apple.ReadingList", ""]
                let nextTrail = skip.contains(name) ? trail : (trail + [name])
                for child in children {
                    walk(node: child, trail: nextTrail)
                }
            }
        }

        walk(node: root, trail: [])
        return items
    }

    public static func parseSafariHistorySQLite(at historyURL: URL, limit: Int = 1000) -> [BrowserSiteItem] {
        return withSafeSQLiteCopy(of: historyURL) { db in
            let sql = """
            SELECT hi.url, COALESCE(hv.title, ''), hi.visit_count, MAX(hv.visit_time)
            FROM history_items hi
            JOIN history_visits hv ON hv.history_item = hi.id
            WHERE hi.visit_count >= 2
            GROUP BY hi.id
            ORDER BY hi.visit_count DESC, MAX(hv.visit_time) DESC
            LIMIT ?1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                return []
            }
            defer { sqlite3_finalize(s) }
            sqlite3_bind_int(s, 1, Int32(limit))

            var items: [BrowserSiteItem] = []
            while sqlite3_step(s) == SQLITE_ROW {
                guard let urlC = sqlite3_column_text(s, 0) else { continue }
                let urlStr = String(cString: urlC)
                guard !isNoisyURL(urlStr), let url = URL(string: urlStr) else { continue }

                let title = sqlite3_column_text(s, 1).map { String(cString: $0) } ?? ""
                let visitCount = Int(sqlite3_column_int64(s, 2))
                // Safari CoreData timestamp = seconds since Jan 1, 2001 UTC
                let visitTime = sqlite3_column_double(s, 3)
                let date = visitTime > 0 ? Date(timeIntervalSinceReferenceDate: visitTime) : .distantPast

                items.append(
                    BrowserSiteItem(
                        url: url,
                        title: title,
                        folderPath: nil,
                        isBookmark: false,
                        visitCount: visitCount,
                        typedCount: 0,
                        lastVisited: date,
                        source: .safari
                    )
                )
            }
            return items
        } ?? []
    }
}
