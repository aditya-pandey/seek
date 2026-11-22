import AppKit
import SwiftUI
import Quartz
import CoreServices
import UniformTypeIdentifiers
import QuickLookThumbnailing

public enum SearchFilterCategory: String, CaseIterable, Identifiable {
    case all             = "All"
    case apps            = "Apps"
    case docsAndPDFs     = "Docs & PDF"
    case foldersAndRepos = "Folders"
    case imagesAndMedia  = "Media"
    case code            = "Code"
    case web             = "Web"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all:             return "sparkles"
        case .apps:            return "square.grid.2x2.fill"
        case .docsAndPDFs:     return "doc.richtext.fill"
        case .foldersAndRepos: return "folder.fill.badge.gearshape"
        case .imagesAndMedia:  return "photo.on.rectangle.angled"
        case .code:            return "chevron.left.forwardslash.chevron.right"
        case .web:             return "globe"
        }
    }
}

public struct IndexedFileItem: Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let name: String
    public let nameLower: String
    public let nameWithoutExtLower: String
    public let nameNormalized: String
    public let wordTokensLower: [String]
    public let initialsLower: String
    public let parentName: String
    public let parentNameLower: String
    public let fullRelativeLower: String
    public let displayPath: String
    public let ext: String
    public let isDirectory: Bool
    public let isApplication: Bool
    public let isProjectRepo: Bool
    public let isContentMatch: Bool
    public let modificationDate: Date
    public let lastUsedDate: Date?
    public let useCount: Int
    public let fileSize: Int64
    public let depth: Int
    public let formattedSize: String
    public let relativeTimeString: String

    public init(
        id: String,
        url: URL,
        name: String,
        nameLower: String,
        parentName: String,
        parentNameLower: String,
        displayPath: String,
        ext: String,
        isDirectory: Bool,
        isApplication: Bool = false,
        isProjectRepo: Bool,
        modificationDate: Date,
        fileSize: Int64,
        depth: Int,
        fullRelativeLower: String? = nil,
        formattedSize: String? = nil,
        relativeTimeString: String? = nil,
        lastUsedDate: Date? = nil,
        useCount: Int = 0,
        isContentMatch: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.nameLower = nameLower
        let rawNoExt = (name as NSString).deletingPathExtension
        let withoutExtLower = (nameLower as NSString).deletingPathExtension
        self.nameWithoutExtLower = withoutExtLower

        let words = Self.extractWords(from: rawNoExt.isEmpty ? name : rawNoExt)
        self.wordTokensLower = words
        self.initialsLower = Self.computeInitials(fromWords: words)
        self.nameNormalized = Self.normalizeCompact(withoutExtLower)

        self.parentName = parentName
        self.parentNameLower = parentNameLower
        self.fullRelativeLower = fullRelativeLower ?? "\(parentNameLower)/\(nameLower)"
        self.displayPath = displayPath
        self.ext = ext
        self.isDirectory = isDirectory
        self.isApplication = isApplication
        self.isProjectRepo = isProjectRepo
        self.isContentMatch = isContentMatch
        self.modificationDate = modificationDate
        self.lastUsedDate = lastUsedDate
        self.useCount = useCount
        self.fileSize = fileSize
        self.depth = depth

        if let formattedSize = formattedSize {
            self.formattedSize = formattedSize
        } else if isApplication {
            self.formattedSize = "Application"
        } else if isDirectory {
            self.formattedSize = isProjectRepo ? "Project Repo" : "Folder"
        } else {
            self.formattedSize = Self.fastByteCount(fileSize)
        }

        if let relativeTimeString = relativeTimeString {
            self.relativeTimeString = relativeTimeString
        } else {
            self.relativeTimeString = Self.fastRelativeTime(from: lastUsedDate ?? modificationDate)
        }
    }

    public static func extractWords(from text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let chars = Array(text)

        for i in 0..<chars.count {
            let ch = chars[i]
            if !ch.isLetter && !ch.isNumber {
                if !current.isEmpty {
                    words.append(current.lowercased())
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            if !current.isEmpty && ch.isUppercase {
                let prev = chars[i - 1]
                let nextIsLower = (i + 1 < chars.count) && chars[i + 1].isLowercase
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) {
                    words.append(current.lowercased())
                    current.removeAll(keepingCapacity: true)
                }
            }
            current.append(ch)
        }

        if !current.isEmpty {
            words.append(current.lowercased())
        }
        return words
    }

    public static func computeInitials(fromWords words: [String]) -> String {
        guard words.count >= 2 else { return "" }
        var chars: [Character] = []
        chars.reserveCapacity(words.count)
        for w in words {
            if let first = w.first {
                chars.append(first)
            }
        }
        return String(chars)
    }

    public static func normalizeCompact(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text where ch.isLetter || ch.isNumber {
            out.append(ch)
        }
        return out
    }

    public static func fastByteCount(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        if bytes < 1_000 { return "\(bytes) B" }
        let kb = Double(bytes) / 1_000.0
        if kb < 1_000.0 { return kb < 10.0 ? String(format: "%.1f KB", kb) : "\(Int(kb.rounded())) KB" }
        let mb = kb / 1_000.0
        if mb < 1_000.0 { return mb < 10.0 ? String(format: "%.1f MB", mb) : String(format: "%.0f MB", mb) }
        let gb = mb / 1_000.0
        return String(format: "%.2f GB", gb)
    }

    public static func fastRelativeTime(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        return "\(days / 365)y ago"
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Unified Ranked Search Result & Atomic UI Snapshot
// ─────────────────────────────────────────────────────────────────────────

public enum UnifiedSearchResultKind: Equatable {
    case inlineCommand(QuickCommandResult)
    case command(QuickCommandResult)
    case openWindow(OpenWindowEntry)
    case file(IndexedFileItem)
    case webSite(BrowserSiteItem)
    case siteSearch(SiteSearchAction)
}

public struct UnifiedSearchResult: Identifiable, Equatable {
    public let id: String
    public let kind: UnifiedSearchResultKind
    public let score: Double
    public let matchedRanges: [Range<Int>]

    public init(id: String, kind: UnifiedSearchResultKind, score: Double, matchedRanges: [Range<Int>] = []) {
        self.id = id
        self.kind = kind
        self.score = score
        self.matchedRanges = matchedRanges
    }

    public var fileItem: IndexedFileItem? {
        if case .file(let item) = kind { return item }
        return nil
    }

    public var webSiteItem: BrowserSiteItem? {
        if case .webSite(let site) = kind { return site }
        return nil
    }

    public var siteSearchAction: SiteSearchAction? {
        if case .siteSearch(let action) = kind { return action }
        return nil
    }
}

public struct SearchSnapshot: Equatable {
    public let query: String
    public let category: SearchFilterCategory
    public let items: [UnifiedSearchResult]
    public let isSearchingDeep: Bool
    public let statusHint: String?

    public static let empty = SearchSnapshot(
        query: "",
        category: .all,
        items: [],
        isSearchingDeep: false,
        statusHint: nil
    )
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Natural Query Parser (Paths, Scopes, Extensions, Content)
// ─────────────────────────────────────────────────────────────────────────

public enum WebScopeFilter: Equatable {
    case allWeb
    case bookmarksOnly
    case historyOnly
}

public struct ParsedSearchQuery {
    public let raw: String
    public let trimmed: String
    public let isPathMode: Bool
    public let scopeDirectory: URL?
    public let scopeLabel: String?
    public let webScope: WebScopeFilter?
    public let forceContentSearch: Bool
    public let forcedExtensions: Set<String>
    public let searchTokens: [String]
    public let allHighlightTokens: [String]

    private static let typeAliases: [String: Set<String>] = [
        "pdf": ["pdf"],
        "doc": ["doc", "docx", "pages", "rtf", "odt"],
        "docx": ["docx", "doc"],
        "word": ["doc", "docx", "pages"],
        "excel": ["xls", "xlsx", "csv", "numbers"],
        "sheet": ["xls", "xlsx", "csv", "numbers"],
        "sheets": ["xls", "xlsx", "csv", "numbers"],
        "xlsx": ["xlsx", "xls"],
        "csv": ["csv"],
        "ppt": ["ppt", "pptx", "key"],
        "pptx": ["pptx", "ppt"],
        "slides": ["ppt", "pptx", "key"],
        "deck": ["ppt", "pptx", "key", "pdf"],
        "image": ["png", "jpg", "jpeg", "heic", "webp", "gif", "svg"],
        "images": ["png", "jpg", "jpeg", "heic", "webp", "gif", "svg"],
        "img": ["png", "jpg", "jpeg", "heic", "webp", "gif", "svg"],
        "png": ["png"],
        "jpg": ["jpg", "jpeg"],
        "video": ["mp4", "mov", "mkv", "avi", "webm"],
        "audio": ["mp3", "m4a", "wav", "flac", "aac"],
        "zip": ["zip", "tar", "gz", "dmg", "7z", "rar"]
    ]

    public static func parse(_ rawQuery: String) -> ParsedSearchQuery {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("~/") || trimmed == "~" || trimmed.hasPrefix("/") {
            return ParsedSearchQuery(
                raw: rawQuery,
                trimmed: trimmed,
                isPathMode: true,
                scopeDirectory: nil,
                scopeLabel: "Path Browser",
                webScope: nil,
                forceContentSearch: false,
                forcedExtensions: [],
                searchTokens: [],
                allHighlightTokens: []
            )
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let lowerParts = trimmed.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var scopeDir: URL?
        var scopeLabel: String?
        var webScope: WebScopeFilter?
        var forceContent = false
        var forcedExts: Set<String> = []
        var tokens: [String] = []

        for part in lowerParts {
            if part.hasPrefix("in:") {
                let target = String(part.dropFirst(3))
                switch target {
                case "downloads", "dl", "download":
                    scopeDir = home.appendingPathComponent("Downloads")
                    scopeLabel = "Downloads"
                case "desktop", "dt":
                    scopeDir = home.appendingPathComponent("Desktop")
                    scopeLabel = "Desktop"
                case "docs", "doc", "documents":
                    scopeDir = home.appendingPathComponent("Documents")
                    scopeLabel = "Documents"
                case "icloud", "cloud":
                    scopeDir = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
                    scopeLabel = "iCloud Drive"
                case "pics", "pictures", "photos":
                    scopeDir = home.appendingPathComponent("Pictures")
                    scopeLabel = "Pictures"
                case "apps", "applications":
                    scopeDir = URL(fileURLWithPath: "/Applications")
                    scopeLabel = "Applications"
                case "web", "browser", "sites":
                    webScope = .allWeb
                    scopeLabel = "Web & Bookmarks"
                case "bookmarks", "bookmark", "bm":
                    webScope = .bookmarksOnly
                    scopeLabel = "Bookmarks"
                case "history", "top":
                    webScope = .historyOnly
                    scopeLabel = "Top Sites"
                default:
                    if !target.isEmpty { tokens.append(target) }
                }
                continue
            }

            if part.hasPrefix("content:") || part.hasPrefix("text:") || part.hasPrefix("inside:") {
                forceContent = true
                let val = part.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                if !val.isEmpty { tokens.append(val) }
                continue
            }

            if part.hasPrefix(".") && part.count >= 2 && part.count <= 6 {
                let ext = String(part.dropFirst())
                if ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    forcedExts.insert(ext)
                    continue
                }
            }

            tokens.append(part)
        }

        var highlightTokens = tokens
        if tokens.count >= 2 && webScope == nil {
            var remaining: [String] = []
            var extractedExts: Set<String> = []
            for tok in tokens {
                if let exts = typeAliases[tok], tok != "deck" {
                    extractedExts.formUnion(exts)
                } else {
                    remaining.append(tok)
                }
            }
            if !remaining.isEmpty && !extractedExts.isEmpty {
                forcedExts.formUnion(extractedExts)
                tokens = remaining
                highlightTokens = remaining
            }
        } else if tokens.count == 1 && webScope == nil, let tok = tokens.first,
                  let exts = typeAliases[tok],
                  ["pdf", "xlsx", "pptx", "docx", "csv", "png", "jpg", "excel", "slides", "video", "audio"].contains(tok) {
            forcedExts.formUnion(exts)
        }

        return ParsedSearchQuery(
            raw: rawQuery,
            trimmed: trimmed,
            isPathMode: false,
            scopeDirectory: scopeDir,
            scopeLabel: scopeLabel,
            webScope: webScope,
            forceContentSearch: forceContent,
            forcedExtensions: forcedExts,
            searchTokens: tokens,
            allHighlightTokens: highlightTokens
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Persistent Frecency Store
// ─────────────────────────────────────────────────────────────────────────

public final class SearchFrecencyStore {
    public static let shared = SearchFrecencyStore()

    private struct Record: Codable {
        var openCount: Int
        var lastOpened: TimeInterval
        var queryHits: [String: Int]
    }

    private var records: [String: Record] = [:]
    private let lock = NSLock()
    private let storageURL: URL
    private let ioQueue = DispatchQueue(label: "com.local.Seek.FrecencyIO", qos: .utility)

    public init(customStorageURL: URL? = nil) {
        if let custom = customStorageURL {
            self.storageURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let dir = appSupport.appendingPathComponent("Seek", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("frecency.json")
        }
        load()
    }

    public func recordLaunch(itemID: String, query: String) {
        let normQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date().timeIntervalSince1970

        lock.lock()
        var rec = records[itemID] ?? Record(openCount: 0, lastOpened: now, queryHits: [:])
        rec.openCount += 1
        rec.lastOpened = now
        if normQuery.count >= 1 && normQuery.count <= 24 {
            rec.queryHits[normQuery, default: 0] += 1
        }
        records[itemID] = rec
        let snapshot = records
        lock.unlock()

        ioQueue.async { [storageURL] in
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: storageURL, options: .atomic)
            }
        }
    }

    public func boost(for itemID: String, query: String, now: Date = Date()) -> Double {
        let normQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        guard let rec = records[itemID] else {
            lock.unlock()
            return 0.0
        }
        lock.unlock()

        let ageDays = max(0.0, (now.timeIntervalSince1970 - rec.lastOpened) / 86_400.0)
        let decay = 1.0 / (1.0 + ageDays * 0.12)
        var score = min(75.0, log2(Double(rec.openCount) + 1.0) * 26.0) * decay

        if !normQuery.isEmpty {
            if let exactHits = rec.queryHits[normQuery] {
                score += min(110.0, 55.0 + Double(exactHits) * 18.0)
            } else {
                for (q, hits) in rec.queryHits where q.hasPrefix(normQuery) || normQuery.hasPrefix(q) {
                    score += min(65.0, 28.0 + Double(hits) * 10.0)
                    break
                }
            }
        }
        return score
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return
        }
        lock.lock()
        records = decoded
        lock.unlock()
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Pre-Scaled 32×32 Icon Cache
// ─────────────────────────────────────────────────────────────────────────

public final class FileIconCache {
    public static let shared = FileIconCache()
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()
    private let warmQueue = DispatchQueue(label: "com.local.Seek.IconWarm", qos: .utility)

    private lazy var fallbackFolderIcon: NSImage = Self.resized(NSWorkspace.shared.icon(for: .folder))
    private lazy var fallbackDocIcon: NSImage = Self.resized(NSWorkspace.shared.icon(for: .data))

    public func icon(for item: IndexedFileItem) -> NSImage {
        let key: String
        if item.isApplication {
            key = "app_\(item.id)"
        } else if item.isDirectory {
            key = item.isProjectRepo ? "__repo_folder__" : "__folder__"
        } else if !item.ext.isEmpty {
            key = "ext_\(item.ext)"
        } else {
            key = "__generic_file__"
        }

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved: NSImage
        if item.isApplication {
            resolved = Self.resized(NSWorkspace.shared.icon(forFile: item.url.path))
        } else if item.isDirectory {
            resolved = fallbackFolderIcon
        } else if !item.ext.isEmpty, let utType = UTType(filenameExtension: item.ext) {
            resolved = Self.resized(NSWorkspace.shared.icon(for: utType))
        } else {
            resolved = fallbackDocIcon
        }

        lock.lock()
        cache[key] = resolved
        lock.unlock()
        return resolved
    }

    public func prewarmApps(_ apps: [IndexedFileItem]) {
        warmQueue.async { [weak self] in
            guard let self = self else { return }
            for app in apps {
                let key = "app_\(app.id)"
                self.lock.lock()
                let exists = self.cache[key] != nil
                self.lock.unlock()
                if !exists {
                    let img = Self.resized(NSWorkspace.shared.icon(forFile: app.url.path))
                    self.lock.lock()
                    self.cache[key] = img
                    self.lock.unlock()
                }
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
// MARK: - Async File Preview Loader
// ─────────────────────────────────────────────────────────────────────────

public enum FilePreviewContent: Equatable {
    case idle
    case loading
    case thumbnail(NSImage)
    case textExcerpt(String)
    case folderContents([String], totalCount: Int)
    case fallbackIcon(NSImage)

    public static func == (lhs: FilePreviewContent, rhs: FilePreviewContent) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading): return true
        case (.thumbnail(let a), .thumbnail(let b)): return a === b
        case (.textExcerpt(let a), .textExcerpt(let b)): return a == b
        case (.folderContents(let a, let ac), .folderContents(let b, let bc)): return a == b && ac == bc
        case (.fallbackIcon(let a), .fallbackIcon(let b)): return a === b
        default: return false
        }
    }
}

public final class FilePreviewLoader: ObservableObject {
    @Published public private(set) var content: FilePreviewContent = .idle
    @Published public private(set) var currentItemID: String?

    private let thumbCache = NSCache<NSString, NSImage>()
    private let textCache = NSCache<NSString, NSString>()
    private let workQueue = DispatchQueue(label: "com.local.Seek.PreviewLoader", qos: .userInitiated)
    private var debounceWork: DispatchWorkItem?
    private var generation: Int = 0

    private static let textPreviewExts: Set<String> = [
        "md", "txt", "json", "yaml", "yml", "toml", "csv", "log", "env", "xml",
        "swift", "py", "js", "ts", "tsx", "jsx", "html", "css", "sh", "sql",
        "go", "rs", "c", "cpp", "h", "java", "kt", "rb", "php", "gitignore"
    ]

    public init() {
        thumbCache.countLimit = 80
        textCache.countLimit = 80
    }

    public func loadPreview(for item: IndexedFileItem?) {
        debounceWork?.cancel()
        generation &+= 1
        let gen = generation

        guard let item = item else {
            currentItemID = nil
            content = .idle
            return
        }

        currentItemID = item.id

        if let cachedImg = thumbCache.object(forKey: item.id as NSString) {
            content = .thumbnail(cachedImg)
            return
        }
        if let cachedTxt = textCache.object(forKey: item.id as NSString) {
            content = .textExcerpt(cachedTxt as String)
            return
        }

        if item.isApplication {
            content = .fallbackIcon(NSWorkspace.shared.icon(forFile: item.url.path))
            return
        }

        content = .loading

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == gen else { return }
            if item.isDirectory {
                self.loadFolderPeek(item: item, generation: gen)
            } else if Self.textPreviewExts.contains(item.ext) {
                self.loadTextExcerpt(item: item, generation: gen)
            } else {
                self.loadQuickLookThumbnail(item: item, generation: gen)
            }
        }
        debounceWork = work
        workQueue.asyncAfter(deadline: .now() + 0.035, execute: work)
    }

    private func loadFolderPeek(item: IndexedFileItem, generation: Int) {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: item.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sorted = entries.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }

        let names = sorted.prefix(9).map { url -> String in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? "📁 \(url.lastPathComponent)" : "📄 \(url.lastPathComponent)"
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.generation == generation else { return }
            self.content = .folderContents(names, totalCount: entries.count)
        }
    }

    private func loadTextExcerpt(item: IndexedFileItem, generation: Int) {
        guard let handle = try? FileHandle(forReadingFrom: item.url) else {
            loadQuickLookThumbnail(item: item, generation: generation)
            return
        }
        defer { try? handle.close() }
        let chunk = handle.readData(ofLength: 4096)
        guard let rawStr = String(data: chunk, encoding: .utf8), !rawStr.isEmpty else {
            loadQuickLookThumbnail(item: item, generation: generation)
            return
        }

        let excerpt = rawStr
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(18)
            .map { String($0.prefix(90)) }
            .joined(separator: "\n")

        textCache.setObject(excerpt as NSString, forKey: item.id as NSString)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.generation == generation else { return }
            self.content = .textExcerpt(excerpt)
        }
    }

    private func loadQuickLookThumbnail(item: IndexedFileItem, generation: Int) {
        let req = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 250, height: 175),
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let self = self else { return }
            let img = rep?.nsImage
            if let img = img {
                self.thumbCache.setObject(img, forKey: item.id as NSString)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.generation == generation else { return }
                if let img = img {
                    self.content = .thumbnail(img)
                } else {
                    self.content = .fallbackIcon(NSWorkspace.shared.icon(forFile: item.url.path))
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Seek Core Hybrid Search Manager
// ─────────────────────────────────────────────────────────────────────────

public final class SeekSearchManager: NSObject, ObservableObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = SeekSearchManager()

    public static let compactSize  = NSSize(width: 680, height: 102)
    public static let expandedSize = NSSize(width: 780, height: 514)

    @Published public private(set) var snapshot: SearchSnapshot = .empty
    @Published public private(set) var isIndexing: Bool = false
    @Published public private(set) var totalIndexedCount: Int = 0
    @Published public private(set) var isExpanded: Bool = false

    private let stateLock = NSLock()
    private var indexedItems: [IndexedFileItem] = []
    private var cachedOpenWindows: [OpenWindowEntry] = []
    private var searchGeneration: Int = 0
    private var currentQuery: String = ""
    private var currentCategory: SearchFilterCategory = .all
    private var activeMDQuery: MDQuery?
    private var lastHideTime: Date = .distantPast
    private var lastLaunchedItem: Bool = false

    private let indexQueue = DispatchQueue(label: "com.local.Seek.FileIndexer", qos: .utility)
    private let memorySearchQueue = DispatchQueue(label: "com.local.Seek.MemorySearch", qos: .userInteractive)
    private let spotlightQueue = DispatchQueue(label: "com.local.Seek.SpotlightMDQuery", qos: .userInitiated)

    private var activeMemoryWorkItem: DispatchWorkItem?
    private var activeSpotlightWorkItem: DispatchWorkItem?

    private var panel: SeekPanel?
    private var anchoredTopY: CGFloat?
    private var anchoredMidX: CGFloat?

    public weak var searchTextField: NSTextField? {
        didSet { panel?.primaryTextField = searchTextField }
    }
    public var onRequestFocus: ((String?, Bool) -> Void)?

    private var previousApp: NSRunningApplication?
    private var previewURL: URL?
    private var lastIndexTime: Date = .distantPast
    private var isIndexRunning: Bool = false

    public static let ignoredDirectoryNames: Set<String> = [
        "node_modules", ".git", ".build", "DerivedData", "Pods",
        ".venv", "venv", "env", "__pycache__", ".pytest_cache", ".mypy_cache",
        ".next", ".nuxt", ".svelte-kit", "dist", "build", "out", "target",
        "vendor", "bower_components", ".gradle", ".idea", ".vscode",
        "Library", ".Trash", ".npm", ".cargo", ".rustup", ".cache",
        "site-packages", "coverage", ".tox", ".eggs", "xcuserdata",
        ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100"
    ]

    public static let ignoredPathFragments: [String] = [
        "/node_modules/", "/.git/", "/.build/", "/DerivedData/", "/Pods/",
        "/.venv/", "/venv/", "/__pycache__/", "/.next/", "/.nuxt/",
        "/dist/", "/build/", "/target/", "/vendor/", "/site-packages/",
        "/.Trash/", "/.gradle/", "/.cache/", "/.npm/", "/.cargo/",
        "/Library/Caches/", "/Library/Logs/", "/Library/Application Support/",
        "/Library/Containers/", "/Library/Group Containers/", "/Library/Preferences/",
        "/Library/Saved Application State/", "/Library/Metadata/", "/Library/Developer/",
        "/Library/Mail/", "/Library/Messages/", "/Library/Cookies/", "/Library/WebKit/"
    ]

    public static let docExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx",
        "pages", "numbers", "key", "txt", "md", "rtf", "epub", "odt"
    ]

    public static let mediaExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "webp", "gif", "svg", "tiff", "bmp",
        "mp4", "mov", "mkv", "avi", "webm", "mp3", "m4a", "wav", "flac", "fig", "psd", "ai"
    ]

    public static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "c", "cpp", "h", "hpp",
        "java", "kt", "rb", "php", "html", "css", "scss", "json", "yaml", "yml",
        "toml", "sh", "zsh", "sql", "xml", "graphql", "dockerfile"
    ]

    private override init() {
        super.init()
    }

    public static func isNoisyPath(_ path: String) -> Bool {
        if path.contains("/Library/Mobile Documents/com~apple~CloudDocs") {
            for frag in ignoredPathFragments where !frag.hasPrefix("/Library/") {
                if path.contains(frag) { return true }
            }
            return false
        }
        if path.contains("/Library/") { return true }
        for fragment in ignoredPathFragments {
            if path.contains(fragment) { return true }
        }
        return false
    }

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Smooth Compact ↔ Expanded Morphing (Top-Edge Anchored!)
    // ─────────────────────────────────────────────────────────────

    public func setExpanded(_ expand: Bool, animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let changed = (self.isExpanded != expand)
            self.isExpanded = expand
            guard changed, let panel = self.panel else { return }

            let targetSize = expand ? Self.expandedSize : Self.compactSize
            let midX = self.anchoredMidX ?? panel.frame.midX
            let topY = self.anchoredTopY ?? panel.frame.maxY

            let targetFrame = NSRect(
                x: round(midX - targetSize.width / 2.0),
                y: round(topY - targetSize.height),
                width: targetSize.width,
                height: targetSize.height
            )

            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if animated && !reduceMotion {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.13
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(targetFrame, display: true)
                }
            } else {
                panel.setFrame(targetFrame, display: true)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Non-Blocking Live Search
    // ─────────────────────────────────────────────────────────────

    public func performSearch(query: String, category: SearchFilterCategory) {
        stateLock.lock()
        self.currentQuery = query
        self.currentCategory = category
        self.searchGeneration &+= 1
        let gen = self.searchGeneration

        let prevMem = self.activeMemoryWorkItem
        let prevSpot = self.activeSpotlightWorkItem
        let prevMD = self.activeMDQuery
        self.activeMDQuery = nil
        stateLock.unlock()

        prevMem?.cancel()
        prevSpot?.cancel()
        if let md = prevMD { MDQueryStop(md) }

        let memWork = DispatchWorkItem { [weak self] in
            guard let self = self, self.isCurrentGeneration(gen) else { return }
            self.executeHybridSearch(rawQuery: query, category: category, generation: gen)
        }

        stateLock.lock()
        self.activeMemoryWorkItem = memWork
        stateLock.unlock()

        memorySearchQueue.async(execute: memWork)
    }

    private func isCurrentGeneration(_ gen: Int) -> Bool {
        stateLock.lock()
        let ok = (self.searchGeneration == gen)
        stateLock.unlock()
        return ok
    }

    private func executeHybridSearch(rawQuery: String, category: SearchFilterCategory, generation: Int) {
        let parsed = ParsedSearchQuery.parse(rawQuery)
        let now = Date()

        if parsed.isPathMode {
            let pathItems = browsePath(parsed.trimmed, now: now)
            let unified = pathItems.map { UnifiedSearchResult(id: "file_\($0.id)", kind: .file($0), score: 500.0) }
            publishSnapshot(
                SearchSnapshot(
                    query: rawQuery,
                    category: category,
                    items: unified,
                    isSearchingDeep: false,
                    statusHint: "Path mode · Tab to autocomplete folder"
                ),
                generation: generation
            )
            return
        }

        stateLock.lock()
        let indexSnapshot = indexedItems
        let openWinSnapshot = cachedOpenWindows
        let prevBundle = previousApp?.bundleIdentifier
        stateLock.unlock()
        let webSnapshot = BrowserIndexManager.shared.currentSnapshot()
        let isWebOnlyMode = (category == .web) || (parsed.webScope != nil)

        if parsed.trimmed.isEmpty {
            if isWebOnlyMode {
                let webIdle = webSnapshot.map { site -> (BrowserSiteItem, Double) in
                    let base = Self.idleWebScore(for: site, now: now)
                    let frec = SearchFrecencyStore.shared.boost(for: "web_\(site.id)", query: "", now: now)
                    return (site, base + frec)
                }
                let topWeb = webIdle
                    .sorted { $0.1 > $1.1 }
                    .prefix(40)
                    .map { UnifiedSearchResult(id: "web_\($0.0.id)", kind: .webSite($0.0), score: $0.1) }

                publishSnapshot(
                    SearchSnapshot(
                        query: rawQuery,
                        category: category,
                        items: topWeb,
                        isSearchingDeep: false,
                        statusHint: "Bookmarks & Top Sites"
                    ),
                    generation: generation
                )
                return
            }

            let filtered = indexSnapshot.filter { Self.matchesCategory(item: $0, category: category) }
            let scoredIdle = filtered.map { item -> (IndexedFileItem, Double) in
                let base = Self.idleScore(for: item, now: now)
                let frec = SearchFrecencyStore.shared.boost(for: item.id, query: "", now: now)
                return (item, base + frec)
            }
            let top = scoredIdle
                .sorted { $0.1 > $1.1 }
                .prefix(40)
                .map { UnifiedSearchResult(id: "file_\($0.0.id)", kind: .file($0.0), score: $0.1) }

            publishSnapshot(
                SearchSnapshot(
                    query: rawQuery,
                    category: category,
                    items: top,
                    isSearchingDeep: false,
                    statusHint: category == .all ? "Recent & Frequent" : category.rawValue
                ),
                generation: generation
            )
            return
        }

        var unifiedResults: [UnifiedSearchResult] = []
        unifiedResults.reserveCapacity(64)

        if parsed.scopeDirectory == nil && !parsed.forceContentSearch && !isWebOnlyMode,
           let inlineHit = CommandEngine.evaluateInline(query: rawQuery) {
            unifiedResults.append(
                UnifiedSearchResult(id: "inline_\(inlineHit.id)", kind: .inlineCommand(inlineHit), score: 10_000.0)
            )
        }

        // Direct in-site search ("gmail invoice", "drive budget", "gh seek", "yt lofi", "g swift")
        if (category == .all || isWebOnlyMode) && parsed.scopeDirectory == nil && !parsed.forceContentSearch,
           let siteSearch = QuickSiteSearchEngine.match(rawQuery: rawQuery) {
            unifiedResults.append(
                UnifiedSearchResult(
                    id: siteSearch.id,
                    kind: .siteSearch(siteSearch),
                    score: 360.0
                )
            )
        }

        // Browser Bookmarks & Top Visited Websites
        if (category == .all || isWebOnlyMode) && parsed.scopeDirectory == nil && !parsed.forceContentSearch && parsed.forcedExtensions.isEmpty {
            let webFilter = parsed.webScope ?? .allWeb
            var webHits: [(BrowserSiteItem, Double)] = []
            webHits.reserveCapacity(32)

            for site in webSnapshot {
                if webFilter == .bookmarksOnly && !site.isBookmark { continue }
                if webFilter == .historyOnly && site.visitCount < 2 { continue }

                let s: Double?
                if parsed.searchTokens.isEmpty {
                    s = Self.idleWebScore(for: site, now: now) + 120.0
                } else {
                    let frec = SearchFrecencyStore.shared.boost(for: "web_\(site.id)", query: parsed.trimmed, now: now)
                    s = Self.scoreWebSite(site, tokens: parsed.searchTokens, now: now, frecencyBoost: frec)
                }

                if let score = s {
                    webHits.append((site, score))
                }
            }

            let webLimit = isWebOnlyMode ? 45 : 8
            for (site, score) in webHits.sorted(by: { $0.1 > $1.1 }).prefix(webLimit) {
                let ranges = Self.matchRanges(in: site.title, tokens: parsed.allHighlightTokens)
                unifiedResults.append(
                    UnifiedSearchResult(
                        id: "web_\(site.id)",
                        kind: .webSite(site),
                        score: score,
                        matchedRanges: ranges
                    )
                )
            }
        }

        if category == .all && !isWebOnlyMode && parsed.scopeDirectory == nil && !parsed.forceContentSearch {
            let cmdHits = CommandEngine.scoredCommands(query: rawQuery, frontAppBundleID: prevBundle).prefix(3)
            for hit in cmdHits {
                let ranges = Self.matchRanges(in: hit.command.title, tokens: parsed.allHighlightTokens)
                unifiedResults.append(
                    UnifiedSearchResult(
                        id: "cmd_\(hit.command.id)",
                        kind: .command(hit.command),
                        score: hit.score,
                        matchedRanges: ranges
                    )
                )
            }
        }

        if (category == .all || category == .apps) && !isWebOnlyMode && parsed.scopeDirectory == nil && !parsed.forceContentSearch && !parsed.searchTokens.isEmpty {
            var winHits: [(OpenWindowEntry, Double)] = []
            for entry in openWinSnapshot {
                let appLower = entry.appName.lowercased()
                let titleLower = entry.title.lowercased()
                let combined = "\(appLower) \(titleLower)"
                if parsed.searchTokens.allSatisfy({ combined.contains($0) }) {
                    var s = 210.0
                    if titleLower.hasPrefix(parsed.trimmed.lowercased()) { s += 55.0 }
                    if appLower == parsed.trimmed.lowercased() { s += 30.0 }
                    winHits.append((entry, s))
                }
            }
            for (win, s) in winHits.sorted(by: { $0.1 > $1.1 }).prefix(4) {
                let ranges = Self.matchRanges(in: win.title, tokens: parsed.allHighlightTokens)
                unifiedResults.append(
                    UnifiedSearchResult(
                        id: "win_\(win.id)",
                        kind: .openWindow(win),
                        score: s,
                        matchedRanges: ranges
                    )
                )
            }
        }

        var fileMap: [String: (IndexedFileItem, Double)] = [:]
        fileMap.reserveCapacity(80)
        let scopePathPrefix = parsed.scopeDirectory?.path

        if !parsed.forceContentSearch && !isWebOnlyMode {
            for item in indexSnapshot {
                if let prefix = scopePathPrefix, !item.id.hasPrefix(prefix) { continue }
                guard Self.matchesCategory(item: item, category: category) else { continue }
                if !parsed.forcedExtensions.isEmpty {
                    let extMatch = parsed.forcedExtensions.contains(item.ext)
                    let nameMatch = parsed.searchTokens.count == 1 && item.nameLower.contains(parsed.searchTokens[0])
                    if !extMatch && !nameMatch { continue }
                }

                let score: Double?
                if parsed.searchTokens.isEmpty {
                    score = Self.idleScore(for: item, now: now) + 120.0
                } else {
                    score = Self.scoreItem(
                        item,
                        tokens: parsed.searchTokens,
                        now: now,
                        frecencyBoost: SearchFrecencyStore.shared.boost(for: item.id, query: parsed.trimmed, now: now)
                    )
                }

                if let s = score {
                    fileMap[item.id] = (item, s)
                }
            }
        }

        let initialUnified = Self.mergeAndSort(
            nonFileResults: unifiedResults,
            fileMap: fileMap,
            highlightTokens: parsed.allHighlightTokens,
            limit: 45
        )

        let shouldRunDeepSpotlight = !isWebOnlyMode
            && (parsed.trimmed.count >= 2 || !parsed.forcedExtensions.isEmpty || parsed.forceContentSearch)
            && category != .apps

        var hint: String? = parsed.scopeLabel.map { "Scope: \($0)" }
        if parsed.forceContentSearch {
            hint = "Searching inside files..."
        } else if !parsed.forcedExtensions.isEmpty {
            let exts = parsed.forcedExtensions.sorted().prefix(3).map { ".\($0)" }.joined(separator: ", ")
            hint = hint.map { "\($0) · \(exts)" } ?? "Type: \(exts)"
        }

        publishSnapshot(
            SearchSnapshot(
                query: rawQuery,
                category: category,
                items: initialUnified,
                isSearchingDeep: shouldRunDeepSpotlight,
                statusHint: hint
            ),
            generation: generation
        )

        guard shouldRunDeepSpotlight, isCurrentGeneration(generation) else { return }

        let capturedFileMap = fileMap
        let capturedNonFiles = unifiedResults
        let spotWork = DispatchWorkItem { [weak self] in
            guard let self = self, self.isCurrentGeneration(generation) else { return }

            let spotlightHits = self.querySpotlight(
                parsed: parsed,
                category: category,
                existingCount: capturedFileMap.count,
                now: now,
                generation: generation
            )
            guard self.isCurrentGeneration(generation) else { return }

            var mergedMap = capturedFileMap
            var addedOrUpdated = false

            for item in spotlightHits {
                if let prefix = scopePathPrefix, !item.id.hasPrefix(prefix) { continue }
                guard Self.matchesCategory(item: item, category: category) else { continue }
                if !parsed.forcedExtensions.isEmpty && !parsed.forcedExtensions.contains(item.ext) {
                    if !(parsed.searchTokens.count == 1 && item.nameLower.contains(parsed.searchTokens[0])) {
                        continue
                    }
                }

                if mergedMap[item.id] == nil {
                    let frec = SearchFrecencyStore.shared.boost(for: item.id, query: parsed.trimmed, now: now)
                    if item.isContentMatch {
                        let ageBoost = Self.recencyBoost(for: item.lastUsedDate ?? item.modificationDate, now: now)
                        let contentScore = 118.0 + ageBoost + frec + (Self.docExtensions.contains(item.ext) ? 20.0 : 0.0)
                        mergedMap[item.id] = (item, contentScore)
                        addedOrUpdated = true
                    } else if parsed.searchTokens.isEmpty {
                        mergedMap[item.id] = (item, Self.idleScore(for: item, now: now) + 120.0 + frec)
                        addedOrUpdated = true
                    } else if let s = Self.scoreItem(item, tokens: parsed.searchTokens, now: now, frecencyBoost: frec) {
                        mergedMap[item.id] = (item, s)
                        addedOrUpdated = true
                    }
                }
            }

            let finalUnified = addedOrUpdated
                ? Self.mergeAndSort(
                    nonFileResults: capturedNonFiles,
                    fileMap: mergedMap,
                    highlightTokens: parsed.allHighlightTokens,
                    limit: 50
                )
                : initialUnified

            self.publishSnapshot(
                SearchSnapshot(
                    query: rawQuery,
                    category: category,
                    items: finalUnified,
                    isSearchingDeep: false,
                    statusHint: parsed.forceContentSearch ? "Content matches" : hint
                ),
                generation: generation
            )
        }

        stateLock.lock()
        self.activeSpotlightWorkItem = spotWork
        stateLock.unlock()

        spotlightQueue.asyncAfter(deadline: .now() + 0.045, execute: spotWork)
    }

    private func publishSnapshot(_ newSnapshot: SearchSnapshot, generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCurrentGeneration(generation) else { return }
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                self.snapshot = newSnapshot
            }
        }
    }

    private static func mergeAndSort(
        nonFileResults: [UnifiedSearchResult],
        fileMap: [String: (IndexedFileItem, Double)],
        highlightTokens: [String],
        limit: Int
    ) -> [UnifiedSearchResult] {
        var combined = nonFileResults
        combined.reserveCapacity(nonFileResults.count + min(fileMap.count, limit))

        let sortedFiles = fileMap.values.sorted { a, b in
            if abs(a.1 - b.1) > 0.5 { return a.1 > b.1 }
            let aDate = a.0.lastUsedDate ?? a.0.modificationDate
            let bDate = b.0.lastUsedDate ?? b.0.modificationDate
            return aDate > bDate
        }

        for (item, score) in sortedFiles.prefix(limit) {
            let ranges = matchRanges(in: item.name, tokens: highlightTokens)
            combined.append(
                UnifiedSearchResult(
                    id: "file_\(item.id)",
                    kind: .file(item),
                    score: score,
                    matchedRanges: ranges
                )
            )
        }

        combined.sort { $0.score > $1.score }
        return combined.count > limit ? Array(combined.prefix(limit)) : combined
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Direct Path Browser
    // ─────────────────────────────────────────────────────────────

    private func browsePath(_ rawPath: String, now: Date) -> [IndexedFileItem] {
        let fm = FileManager.default
        let homePath = fm.homeDirectoryForCurrentUser.path
        let expanded = (rawPath as NSString).expandingTildeInPath

        let dirPath: String
        let filterPrefix: String
        var isDirFlag: ObjCBool = false

        if rawPath.hasSuffix("/") && fm.fileExists(atPath: expanded, isDirectory: &isDirFlag) && isDirFlag.boolValue {
            dirPath = expanded
            filterPrefix = ""
        } else {
            dirPath = (expanded as NSString).deletingLastPathComponent
            filterPrefix = (expanded as NSString).lastPathComponent.lowercased()
        }

        let dirURL = URL(fileURLWithPath: dirPath)
        guard let children = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey],
            options: filterPrefix.hasPrefix(".") ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [IndexedFileItem] = []
        for url in children {
            let nameLower = url.lastPathComponent.lowercased()
            if !filterPrefix.isEmpty && !nameLower.contains(filterPrefix) { continue }
            if let item = Self.buildIndexedItem(for: url, homePath: homePath, depth: 1, fm: fm, now: now) {
                items.append(item)
            }
        }

        return items.sorted { a, b in
            if !filterPrefix.isEmpty {
                let aPref = a.nameLower.hasPrefix(filterPrefix)
                let bPref = b.nameLower.hasPrefix(filterPrefix)
                if aPref != bPref { return aPref }
            }
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Native In-Process CoreServices Spotlight (`MDQuery`)
    // ─────────────────────────────────────────────────────────────

    private func querySpotlight(
        parsed: ParsedSearchQuery,
        category: SearchFilterCategory,
        existingCount: Int,
        now: Date,
        generation: Int
    ) -> [IndexedFileItem] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        var results: [IndexedFileItem] = []
        var seen: Set<String> = []

        let scopes: [CFTypeRef] = parsed.scopeDirectory.map { [$0.path as CFString] } ?? [
            kMDQueryScopeHome,
            "/Applications" as CFString,
            "/System/Applications" as CFString
        ]

        let extPredicate: String?
        if !parsed.forcedExtensions.isEmpty {
            let clauses = parsed.forcedExtensions.map { "kMDItemFSName == '*.\(Self.escapeMDQuery($0))'cd" }
            extPredicate = "(" + clauses.joined(separator: " || ") + ")"
        } else if category == .docsAndPDFs {
            let clauses = ["pdf", "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx", "pages", "numbers", "key", "md", "txt"]
                .map { "kMDItemFSName == '*.\($0)'cd" }
            extPredicate = "(" + clauses.joined(separator: " || ") + ")"
        } else if category == .foldersAndRepos {
            extPredicate = "kMDItemContentType == 'public.folder'"
        } else {
            extPredicate = nil
        }

        if !parsed.forceContentSearch {
            var predicates: [String] = []
            for tok in parsed.searchTokens where tok.count >= 2 {
                let safe = Self.escapeMDQuery(tok)
                predicates.append("(kMDItemFSName == '*\(safe)*'cd || kMDItemDisplayName == '*\(safe)*'cd)")
            }
            if let ep = extPredicate { predicates.append(ep) }

            if !predicates.isEmpty {
                let hits = runMDQuery(
                    queryString: predicates.joined(separator: " && "),
                    scopes: scopes,
                    maxCount: 160,
                    homePath: homePath,
                    now: now,
                    isContentMatch: false,
                    generation: generation
                )
                for item in hits where seen.insert(item.id).inserted { results.append(item) }
            }

            if results.count < 12 && parsed.searchTokens.count >= 2 && isCurrentGeneration(generation),
               let primary = parsed.searchTokens.max(by: { $0.count < $1.count }), primary.count >= 2 {
                let safe = Self.escapeMDQuery(primary)
                var q = "(kMDItemFSName == '*\(safe)*'cd || kMDItemDisplayName == '*\(safe)*'cd)"
                if let ep = extPredicate { q += " && \(ep)" }
                let broader = runMDQuery(
                    queryString: q,
                    scopes: scopes,
                    maxCount: 140,
                    homePath: homePath,
                    now: now,
                    isContentMatch: false,
                    generation: generation
                )
                for item in broader where seen.insert(item.id).inserted { results.append(item) }
            }
        }

        let totalFilenameHits = existingCount + results.count
        let shouldSearchContent = parsed.forceContentSearch
            || (totalFilenameHits < 6
                && !parsed.searchTokens.isEmpty
                && parsed.trimmed.count >= 3
                && (category == .all || category == .docsAndPDFs || category == .code))

        if shouldSearchContent && isCurrentGeneration(generation) {
            let contentTokens = parsed.searchTokens.filter { $0.count >= 3 }
            if !contentTokens.isEmpty {
                let phrasePreds = contentTokens.map { "kMDItemTextContent == '\(Self.escapeMDQuery($0))*'cdw" }
                var q = "(" + phrasePreds.joined(separator: " && ") + ") && kMDItemContentTypeTree == 'public.content'"
                if let ep = extPredicate { q += " && \(ep)" }
                let contentHits = runMDQuery(
                    queryString: q,
                    scopes: scopes,
                    maxCount: 40,
                    homePath: homePath,
                    now: now,
                    isContentMatch: true,
                    generation: generation
                )
                for item in contentHits where seen.insert(item.id).inserted { results.append(item) }
            }
        }

        return results
    }

    private func runMDQuery(
        queryString: String,
        scopes: [CFTypeRef],
        maxCount: Int,
        homePath: String,
        now: Date,
        isContentMatch: Bool,
        generation: Int
    ) -> [IndexedFileItem] {
        guard isCurrentGeneration(generation) else { return [] }

        let useCountKey = "kMDItemUseCount" as CFString
        let valueAttrs: [CFString] = [
            kMDItemPath,
            kMDItemFSName,
            kMDItemDisplayName,
            kMDItemContentModificationDate,
            kMDItemLastUsedDate,
            kMDItemFSSize,
            kMDItemContentType,
            useCountKey
        ]
        let sortAttrs: [CFString] = [
            kMDItemLastUsedDate,
            kMDItemContentModificationDate
        ]

        guard let query = MDQueryCreate(
            kCFAllocatorDefault,
            queryString as CFString,
            valueAttrs as CFArray,
            sortAttrs as CFArray
        ) else {
            return []
        }

        MDQuerySetSearchScope(query, scopes as CFArray, 0)
        MDQuerySetMaxCount(query, maxCount)

        stateLock.lock()
        guard self.searchGeneration == generation else {
            stateLock.unlock()
            return []
        }
        self.activeMDQuery = query
        stateLock.unlock()

        let ok = MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))

        stateLock.lock()
        if self.activeMDQuery === query { self.activeMDQuery = nil }
        let stillValid = (self.searchGeneration == generation)
        stateLock.unlock()

        guard ok, stillValid else { return [] }

        let count = MDQueryGetResultCount(query)
        guard count > 0 else { return [] }

        var items: [IndexedFileItem] = []
        items.reserveCapacity(min(count, maxCount))

        for idx in 0..<count {
            if idx % 32 == 0 && !isCurrentGeneration(generation) { break }
            guard let rawPtr = MDQueryGetResultAtIndex(query, idx) else { continue }
            let mdItem = Unmanaged<MDItem>.fromOpaque(rawPtr).takeUnretainedValue()

            guard let path = MDItemCopyAttribute(mdItem, kMDItemPath) as? String,
                  !Self.isNoisyPath(path) else {
                continue
            }

            let url = URL(fileURLWithPath: path)
            let rawName = (MDItemCopyAttribute(mdItem, kMDItemFSName) as? String) ?? url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let isApp = (ext == "app")
            let contentType = MDItemCopyAttribute(mdItem, kMDItemContentType) as? String
            let isFolder = (contentType == "public.folder") && !isApp
            let displayName = isApp ? (rawName as NSString).deletingPathExtension : rawName

            let modDate = (MDItemCopyAttribute(mdItem, kMDItemContentModificationDate) as? Date) ?? Date.distantPast
            let lastUsed = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date
            let fileSize = (MDItemCopyAttribute(mdItem, kMDItemFSSize) as? NSNumber)?.int64Value ?? 0
            let useCount = (MDItemCopyAttribute(mdItem, useCountKey) as? NSNumber)?.intValue ?? 0

            let parentURL = url.deletingLastPathComponent()
            let parentName = parentURL.lastPathComponent
            let displayPath = Self.cleanDisplayPath(parentURL.path, homePath: homePath)
            let computedDepth = isApp ? 0 : max(1, url.pathComponents.count - 4)
            let fullRelLower = displayPath.lowercased() + "/" + rawName.lowercased()

            items.append(
                IndexedFileItem(
                    id: path,
                    url: url,
                    name: displayName,
                    nameLower: rawName.lowercased(),
                    parentName: parentName,
                    parentNameLower: parentName.lowercased(),
                    displayPath: displayPath,
                    ext: ext,
                    isDirectory: isFolder,
                    isApplication: isApp,
                    isProjectRepo: false,
                    modificationDate: modDate,
                    fileSize: fileSize,
                    depth: computedDepth,
                    fullRelativeLower: fullRelLower,
                    lastUsedDate: lastUsed,
                    useCount: useCount,
                    isContentMatch: isContentMatch
                )
            )
        }
        return items
    }

    private static func escapeMDQuery(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    private static func cleanDisplayPath(_ rawParentPath: String, homePath: String) -> String {
        let icloudPrefix = homePath + "/Library/Mobile Documents/com~apple~CloudDocs"
        if rawParentPath == icloudPrefix { return "iCloud Drive" }
        if rawParentPath.hasPrefix(icloudPrefix + "/") {
            return "iCloud Drive" + String(rawParentPath.dropFirst(icloudPrefix.count))
        }
        if rawParentPath == homePath { return "~" }
        if rawParentPath.hasPrefix(homePath + "/") {
            return "~" + String(rawParentPath.dropFirst(homePath.count))
        }
        return rawParentPath
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Breadth-First (BFS) Zero-Starvation Background Indexer
    // ─────────────────────────────────────────────────────────────

    public func refreshIndexIfNeeded(force: Bool = false) {
        stateLock.lock()
        let isEmpty = indexedItems.isEmpty
        let running = isIndexRunning
        let elapsed = Date().timeIntervalSince(lastIndexTime)
        guard !running && (force || isEmpty || elapsed > 300.0) else {
            stateLock.unlock()
            return
        }
        isIndexRunning = true
        stateLock.unlock()

        DispatchQueue.main.async { self.isIndexing = true }
        let home = FileManager.default.homeDirectoryForCurrentUser

        let appRoots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications"),
            home.appendingPathComponent("Applications")
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        var userRoots: [URL] = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music")
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        let knownRootPaths = Set(userRoots.map { $0.path })
        let skipHomeDirs: Set<String> = ["Library", "Applications", "Public", ".Trash"]
        if let homeChildren = try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in homeChildren {
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir && !skipHomeDirs.contains(child.lastPathComponent) && !knownRootPaths.contains(child.path) {
                    userRoots.append(child)
                }
            }
        }

        indexQueue.async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let homePath = home.path
            let now = Date()
            var collected: [IndexedFileItem] = []
            collected.reserveCapacity(4096)
            var seenPaths: Set<String> = []
            seenPaths.reserveCapacity(4096)

            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey
            ]

            var appsOnly: [IndexedFileItem] = []
            let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            if fm.fileExists(atPath: finderURL.path),
               let finderItem = Self.buildIndexedItem(for: finderURL, homePath: homePath, depth: 0, fm: fm, now: now) {
                collected.append(finderItem)
                appsOnly.append(finderItem)
                seenPaths.insert(finderItem.id)
            }

            for appRoot in appRoots {
                let rootDepth = appRoot.pathComponents.count
                guard let enumerator = fm.enumerator(at: appRoot, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else { continue }
                while let fileURL = enumerator.nextObject() as? URL {
                    let ext = fileURL.pathExtension.lowercased()
                    let depth = max(0, fileURL.pathComponents.count - rootDepth)
                    if ext == "app" {
                        enumerator.skipDescendants()
                        if seenPaths.insert(fileURL.path).inserted,
                           let appItem = Self.buildIndexedItem(for: fileURL, homePath: homePath, depth: 0, fm: fm, now: now) {
                            collected.append(appItem)
                            appsOnly.append(appItem)
                        }
                        continue
                    }
                    if depth >= 2 || ext == "framework" || ext == "bundle" || ext == "plugin" {
                        enumerator.skipDescendants()
                    }
                }
            }

            FileIconCache.shared.prewarmApps(appsOnly)

            if !appsOnly.isEmpty {
                self.stateLock.lock()
                let wasEmpty = self.indexedItems.isEmpty
                if wasEmpty { self.indexedItems = collected }
                self.stateLock.unlock()

                if wasEmpty {
                    DispatchQueue.main.async {
                        self.totalIndexedCount = max(self.totalIndexedCount, collected.count)
                        self.retriggerSearchIfVisible()
                    }
                }
            }

            var bfsQueue: [(url: URL, depth: Int)] = userRoots.map { ($0, 0) }
            var head = 0
            let maxDepth = 6
            let maxTotalItems = 20_000
            let repoMarkers: Set<String> = ["Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "go.mod"]
            var repoFolderPaths: Set<String> = []
            var publishedEarlyBatch = false

            while head < bfsQueue.count && collected.count < maxTotalItems {
                let (dirURL, currentDepth) = bfsQueue[head]
                head += 1

                guard let children = try? fm.contentsOfDirectory(
                    at: dirURL,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                if currentDepth >= 1 && currentDepth <= 3 {
                    if children.contains(where: { repoMarkers.contains($0.lastPathComponent) }) {
                        repoFolderPaths.insert(dirURL.path)
                    }
                }

                let nextDepth = currentDepth + 1
                for childURL in children {
                    if collected.count >= maxTotalItems { break }
                    let name = childURL.lastPathComponent
                    if Self.ignoredDirectoryNames.contains(name) { continue }
                    let ext = childURL.pathExtension.lowercased()
                    guard seenPaths.insert(childURL.path).inserted else { continue }

                    if let item = Self.buildIndexedItem(for: childURL, homePath: homePath, depth: nextDepth, fm: fm, now: now) {
                        collected.append(item)
                        if item.isDirectory && nextDepth < maxDepth
                            && ext != "app" && ext != "framework" && ext != "bundle"
                            && ext != "xcodeproj" && ext != "xcworkspace" && ext != "photoslibrary" {
                            bfsQueue.append((childURL, nextDepth))
                        }

                        if !publishedEarlyBatch && collected.count >= 600 {
                            publishedEarlyBatch = true
                            let earlySnapshot = collected
                            self.stateLock.lock()
                            if self.indexedItems.count < earlySnapshot.count {
                                self.indexedItems = earlySnapshot
                            }
                            self.stateLock.unlock()
                            DispatchQueue.main.async {
                                self.totalIndexedCount = max(self.totalIndexedCount, earlySnapshot.count)
                                self.retriggerSearchIfVisible()
                            }
                        }
                    }
                }
            }

            if !repoFolderPaths.isEmpty {
                for i in 0..<collected.count {
                    let it = collected[i]
                    if it.isDirectory && repoFolderPaths.contains(it.id) {
                        collected[i] = IndexedFileItem(
                            id: it.id, url: it.url, name: it.name, nameLower: it.nameLower,
                            parentName: it.parentName, parentNameLower: it.parentNameLower,
                            displayPath: it.displayPath, ext: it.ext, isDirectory: true,
                            isApplication: false, isProjectRepo: true, modificationDate: it.modificationDate,
                            fileSize: it.fileSize, depth: it.depth, fullRelativeLower: it.fullRelativeLower,
                            formattedSize: "Project Repo", relativeTimeString: it.relativeTimeString
                        )
                    }
                }
            }

            collected.sort { $0.modificationDate > $1.modificationDate }

            self.stateLock.lock()
            self.indexedItems = collected
            self.lastIndexTime = Date()
            self.isIndexRunning = false
            self.stateLock.unlock()

            DispatchQueue.main.async {
                self.totalIndexedCount = collected.count
                self.isIndexing = false
                self.retriggerSearchIfVisible()
            }
        }
    }

    private func retriggerSearchIfVisible() {
        guard isVisible else { return }
        stateLock.lock()
        let q = currentQuery
        let cat = currentCategory
        stateLock.unlock()
        performSearch(query: q, category: cat)
    }

    private static func buildIndexedItem(
        for fileURL: URL,
        homePath: String,
        depth: Int? = nil,
        fm: FileManager = .default,
        now: Date = Date()
    ) -> IndexedFileItem? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey
        ]
        guard let values = try? fileURL.resourceValues(forKeys: keys) else { return nil }

        let rawName = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let isApp = (ext == "app")
        let displayName = isApp ? (rawName as NSString).deletingPathExtension : rawName
        let isDir = values.isDirectory ?? false
        let isPkg = values.isPackage ?? false
        let effectiveIsDir = isDir && !isPkg && !isApp
        let computedDepth = isApp ? 0 : (depth ?? max(1, fileURL.pathComponents.count - 4))
        let modDate = values.contentModificationDate ?? values.creationDate ?? Date.distantPast
        let size = Int64(values.fileSize ?? 0)
        let parentURL = fileURL.deletingLastPathComponent()
        let parentName = parentURL.lastPathComponent
        let displayPath = Self.cleanDisplayPath(parentURL.path, homePath: homePath)
        let fullRelLower = displayPath.lowercased() + "/" + rawName.lowercased()

        return IndexedFileItem(
            id: fileURL.path, url: fileURL, name: displayName, nameLower: rawName.lowercased(),
            parentName: parentName, parentNameLower: parentName.lowercased(), displayPath: displayPath,
            ext: ext, isDirectory: effectiveIsDir, isApplication: isApp, isProjectRepo: false,
            modificationDate: modDate, fileSize: size, depth: computedDepth, fullRelativeLower: fullRelLower
        )
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Smart Multi-Token, CamelCase, Typo-Tolerant Scorer
    // ─────────────────────────────────────────────────────────────

    public static func matchesCategory(item: IndexedFileItem, category: SearchFilterCategory) -> Bool {
        switch category {
        case .all:             return true
        case .apps:            return item.isApplication
        case .docsAndPDFs:     return !item.isDirectory && !item.isApplication && docExtensions.contains(item.ext)
        case .foldersAndRepos: return item.isDirectory
        case .imagesAndMedia:  return !item.isDirectory && !item.isApplication && mediaExtensions.contains(item.ext)
        case .code:            return (!item.isDirectory && !item.isApplication && codeExtensions.contains(item.ext)) || item.isProjectRepo
        case .web:             return false
        }
    }

    private static func idleWebScore(for site: BrowserSiteItem, now: Date = Date()) -> Double {
        var score: Double = 0.0
        if site.isBookmark { score += 90.0 }
        if site.isRootApp { score += 55.0 }
        if site.visitCount > 0 { score += min(80.0, log2(Double(site.visitCount) + 1.0) * 16.0) }
        if site.typedCount > 0 { score += min(35.0, Double(site.typedCount) * 4.0) }
        if site.lastVisited != .distantPast {
            score += recencyBoost(for: site.lastVisited, now: now)
        }
        return score
    }

    /// Calibrated web scorer: exact bookmarks & root web apps (`gmail`, `github`, `figma`) surface near the top,
    /// while deep/low-visit history pages remain ranked below exact local files & apps in All mode.
    public static func scoreWebSite(
        _ site: BrowserSiteItem,
        tokens: [String],
        now: Date = Date(),
        frecencyBoost: Double = 0.0
    ) -> Double? {
        guard !tokens.isEmpty else { return nil }
        var totalScore: Double = 0.0

        // Primary domain stem (e.g. "mail.google.com" -> "google", "github.com" -> "github")
        let domainParts = site.domainLower.split(separator: ".").map(String.init)
        let primaryHostWord = domainParts.first ?? site.domainLower

        for token in tokens {
            let compactToken = IndexedFileItem.normalizeCompact(token)

            // 1. Exact title or exact domain match (e.g. "gmail", "github", "figma")
            if site.titleLower == token || site.domainLower == token || primaryHostWord == token || (!compactToken.isEmpty && site.titleNormalized == compactToken) {
                totalScore += 195.0
                continue
            }

            // 2. Title or domain prefix match (e.g. "gma" -> "Gmail", "git" -> "github.com")
            if site.titleLower.hasPrefix(token) || site.domainLower.hasPrefix(token) || primaryHostWord.hasPrefix(token) {
                totalScore += 150.0
                continue
            }

            // 3. Initials match on title
            if token.count >= 2 && (site.initialsLower == token || site.initialsLower.hasPrefix(token)) {
                totalScore += 135.0
                continue
            }

            // 4. Word-start match inside title or domain
            if let wordBonus = bestWordPrefixBonus(token: token, words: site.wordTokensLower) {
                totalScore += 120.0 + wordBonus
                continue
            }

            // 5. Substring match in title or domain
            if site.titleLower.contains(token) || site.domainLower.contains(token) {
                totalScore += 90.0
                continue
            }

            // 6. Bookmark folder, Chrome profile name, or URL path match
            if !site.profileDisplayNameLower.isEmpty && site.profileDisplayNameLower.contains(token) {
                totalScore += 88.0
                continue
            }
            if !site.folderPathLower.isEmpty && site.folderPathLower.contains(token) {
                totalScore += 76.0
                continue
            }
            if site.urlLower.contains(token) {
                totalScore += 60.0
                continue
            }

            // 7. Typo tolerance on title/domain words (e.g. "gamil" -> "gmail", "gihub" -> "github")
            if token.count >= 4 && matchesWithTypoTolerance(token, words: site.wordTokensLower, compactName: site.titleNormalized) {
                totalScore += 68.0
                continue
            }

            return nil
        }

        // ── Calibrated Web Quality & Frecency Boosts ──
        if site.isBookmark {
            totalScore += 48.0
        }
        if site.isRootApp {
            totalScore += 28.0
        } else if site.url.path.count > 30 || site.url.query != nil {
            // Gently penalize deep specific pages so root web apps & local exact files win cleanly
            totalScore -= 24.0
        }

        if site.visitCount > 0 {
            totalScore += min(55.0, log2(Double(site.visitCount) + 1.0) * 12.0)
        }
        if site.typedCount > 0 {
            totalScore += min(25.0, Double(site.typedCount) * 3.5)
        }
        if site.lastVisited != .distantPast {
            totalScore += recencyBoost(for: site.lastVisited, now: now) * 0.75
        }
        totalScore += frecencyBoost
        return totalScore
    }

    private static func idleScore(for item: IndexedFileItem, now: Date = Date()) -> Double {
        let refDate = item.lastUsedDate ?? item.modificationDate
        let ageHours = max(0.1, now.timeIntervalSince(refDate) / 3600.0)
        var score = 200.0 / (ageHours + 2.0)
        if item.isApplication { score += 45.0 }
        if item.isProjectRepo { score += 35.0 }
        if docExtensions.contains(item.ext) || mediaExtensions.contains(item.ext) { score += 25.0 }
        if item.useCount > 0 { score += min(30.0, Double(item.useCount) * 2.5) }
        score -= Double(item.depth) * 10.0
        return score
    }

    private static func recencyBoost(for date: Date, now: Date) -> Double {
        let ageSeconds = max(0, now.timeIntervalSince(date))
        if ageSeconds < 3_600 { return 52.0 }
        if ageSeconds < 86_400 { return 42.0 }
        if ageSeconds < 7 * 86_400 { return 26.0 }
        if ageSeconds < 30 * 86_400 { return 12.0 }
        return 0.0
    }

    public static func scoreItem(
        _ item: IndexedFileItem,
        tokens: [String],
        now: Date = Date(),
        frecencyBoost: Double = 0.0
    ) -> Double? {
        guard !tokens.isEmpty else { return nil }
        var totalScore: Double = 0.0
        var filenameMatchedCount = 0

        for token in tokens {
            let cleanToken = token.hasPrefix(".") ? String(token.dropFirst()) : token
            let compactToken = IndexedFileItem.normalizeCompact(cleanToken)

            if item.nameLower == token || item.nameWithoutExtLower == token || (!compactToken.isEmpty && item.nameNormalized == compactToken) {
                totalScore += 210.0
                filenameMatchedCount += 1
                continue
            }
            if cleanToken.count >= 2 && (item.initialsLower == cleanToken || item.initialsLower.hasPrefix(cleanToken)) {
                totalScore += (item.initialsLower == cleanToken) ? 175.0 : 145.0
                filenameMatchedCount += 1
                continue
            }
            if item.nameWithoutExtLower.hasPrefix(token) || item.nameLower.hasPrefix(token) {
                let coverage = Double(token.count) / Double(max(item.nameWithoutExtLower.count, 1))
                totalScore += 155.0 + coverage * 30.0
                filenameMatchedCount += 1
                continue
            }
            if let wordMatchBonus = bestWordPrefixBonus(token: cleanToken, words: item.wordTokensLower) {
                totalScore += 135.0 + wordMatchBonus
                filenameMatchedCount += 1
                continue
            }
            if compactToken.count >= 4 && item.nameNormalized.contains(compactToken) {
                totalScore += item.nameNormalized.hasPrefix(compactToken) ? 140.0 : 108.0
                filenameMatchedCount += 1
                continue
            }
            if !item.ext.isEmpty && item.ext == cleanToken {
                totalScore += 100.0
                continue
            }
            if item.nameLower.contains(token) {
                totalScore += 92.0
                filenameMatchedCount += 1
                continue
            }
            if item.parentNameLower.contains(token) {
                totalScore += 78.0
                continue
            }
            if item.fullRelativeLower.contains(token) {
                totalScore += 62.0
                continue
            }
            if let fuzzyScore = scoredSubsequence(cleanToken, in: item.nameWithoutExtLower) {
                totalScore += fuzzyScore
                filenameMatchedCount += 1
                continue
            }
            if cleanToken.count >= 4 && matchesWithTypoTolerance(cleanToken, words: item.wordTokensLower, compactName: item.nameNormalized) {
                totalScore += 74.0
                filenameMatchedCount += 1
                continue
            }
            return nil
        }

        if tokens.count >= 2 && filenameMatchedCount == tokens.count { totalScore += 35.0 }
        if item.isApplication { totalScore += 78.0 }
        else if item.isProjectRepo { totalScore += 42.0 }
        else if item.isDirectory && item.depth <= 2 { totalScore += 22.0 }

        if docExtensions.contains(item.ext) { totalScore += 24.0 }
        else if mediaExtensions.contains(item.ext) { totalScore += 16.0 }
        else if codeExtensions.contains(item.ext) && item.depth > 3 { totalScore -= 12.0 }

        let refDate = item.lastUsedDate ?? item.modificationDate
        totalScore += recencyBoost(for: refDate, now: now)
        if item.useCount > 0 { totalScore += min(28.0, log2(Double(item.useCount) + 1.0) * 7.0) }
        totalScore += frecencyBoost
        totalScore -= Double(item.depth) * 4.5
        totalScore -= Double(min(item.name.count, 50)) * 0.20

        return totalScore
    }

    private static func bestWordPrefixBonus(token: String, words: [String]) -> Double? {
        var best: Double?
        for (idx, word) in words.enumerated() {
            if word == token {
                best = max(best ?? 0, idx == 0 ? 35.0 : 22.0)
            } else if word.hasPrefix(token) {
                best = max(best ?? 0, idx == 0 ? 20.0 : 10.0)
            }
        }
        return best
    }

    private static func scoredSubsequence(_ needle: String, in haystack: String) -> Double? {
        guard needle.count >= 3, needle.count <= haystack.count else { return nil }
        let nChars = Array(needle)
        let hChars = Array(haystack)

        var nIdx = 0
        var firstPos = -1
        var lastPos = -1
        var consecutive = 0
        var maxConsecutive = 0

        for hIdx in 0..<hChars.count {
            if hChars[hIdx] == nChars[nIdx] {
                if firstPos == -1 { firstPos = hIdx }
                if lastPos == hIdx - 1 {
                    consecutive += 1
                    maxConsecutive = max(maxConsecutive, consecutive)
                } else {
                    consecutive = 1
                }
                lastPos = hIdx
                nIdx += 1
                if nIdx == nChars.count { break }
            }
        }

        guard nIdx == nChars.count, firstPos >= 0 else { return nil }
        let span = lastPos - firstPos + 1
        let maxAllowedSpan = max(needle.count * 3, needle.count + 8)
        guard span <= maxAllowedSpan else { return nil }

        let compactness = Double(needle.count) / Double(span)
        return 30.0 + compactness * 34.0 + Double(maxConsecutive) * 4.0
    }

    private static func matchesWithTypoTolerance(_ token: String, words: [String], compactName: String) -> Bool {
        let maxEdits = token.count >= 7 ? 2 : 1
        let tChars = Array(token)

        for word in words {
            if abs(word.count - tChars.count) > maxEdits || word.count < 3 { continue }
            if damerauLevenshtein(tChars, Array(word), maxDistance: maxEdits) <= maxEdits { return true }
        }
        if compactName.count >= tChars.count - maxEdits && compactName.count <= tChars.count + maxEdits {
            if damerauLevenshtein(tChars, Array(compactName), maxDistance: maxEdits) <= maxEdits { return true }
        }
        return false
    }

    public static func damerauLevenshtein(_ a: [Character], _ b: [Character], maxDistance: Int) -> Int {
        let m = a.count
        let n = b.count
        if abs(m - n) > maxDistance { return maxDistance + 1 }
        if m == 0 { return n }
        if n == 0 { return m }

        var prev2 = Array(repeating: 0, count: n + 1)
        var prev1 = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...n {
                let cost = (a[i - 1] == b[j - 1]) ? 0 : 1
                var val = min(prev1[j] + 1, curr[j - 1] + 1, prev1[j - 1] + cost)
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    val = min(val, prev2[j - 2] + 1)
                }
                curr[j] = val
                if val < rowMin { rowMin = val }
            }
            if rowMin > maxDistance { return maxDistance + 1 }
            swap(&prev2, &prev1)
            swap(&prev1, &curr)
        }
        return prev1[n]
    }

    public static func matchRanges(in text: String, tokens: [String]) -> [Range<Int>] {
        guard !tokens.isEmpty, !text.isEmpty else { return [] }
        let lowerChars = Array(text.lowercased())
        var ranges: [Range<Int>] = []

        for tok in tokens where !tok.isEmpty {
            let tChars = Array(tok.lowercased())
            guard tChars.count <= lowerChars.count else { continue }
            var found = false
            for start in 0...(lowerChars.count - tChars.count) {
                var ok = true
                for k in 0..<tChars.count where lowerChars[start + k] != tChars[k] {
                    ok = false
                    break
                }
                if ok {
                    ranges.append(start..<(start + tChars.count))
                    found = true
                    break
                }
            }
            if !found && tChars.count >= 2 {
                var ti = 0
                for idx in 0..<lowerChars.count where lowerChars[idx] == tChars[ti] {
                    ranges.append(idx..<(idx + 1))
                    ti += 1
                    if ti == tChars.count { break }
                }
            }
        }
        return ranges
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────

    public func openItem(_ item: IndexedFileItem) {
        stateLock.lock()
        let q = currentQuery
        lastLaunchedItem = true
        stateLock.unlock()

        SearchFrecencyStore.shared.recordLaunch(itemID: item.id, query: q)
        hide(restorePreviousApp: false)
        NSWorkspace.shared.open(item.url)
    }

    public func executeCommand(_ cmd: QuickCommandResult) {
        stateLock.lock()
        lastLaunchedItem = true
        stateLock.unlock()

        let shouldRestore = (cmd.actionID == "copy")
        hide(restorePreviousApp: shouldRestore)
        let prev = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            CommandEngine.execute(cmd, previousApp: prev)
        }
    }

    public func focusOpenWindow(_ entry: OpenWindowEntry) {
        stateLock.lock()
        lastLaunchedItem = true
        stateLock.unlock()

        hide(restorePreviousApp: false)
        OpenWindowLookup.focusWindow(entry)
    }

    public func openWebSite(_ site: BrowserSiteItem, preferDefaultBrowser: Bool = false) {
        stateLock.lock()
        let q = currentQuery
        lastLaunchedItem = true
        stateLock.unlock()

        SearchFrecencyStore.shared.recordLaunch(itemID: "web_\(site.id)", query: q)
        hide(restorePreviousApp: false)

        openURLInBrowser(
            site.url,
            source: site.source,
            profileDirectory: site.profileDirectory,
            preferDefaultBrowser: preferDefaultBrowser
        )
    }

    public func copyWebURL(_ site: BrowserSiteItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(site.url.absoluteString, forType: .string)
        NSSound(named: "Glass")?.play()
        SeekToast.show(title: "URL Copied", subtitle: site.domain.isEmpty ? site.url.absoluteString : site.domain, icon: "link")
    }

    public func openSiteSearch(_ action: SiteSearchAction) {
        stateLock.lock()
        lastLaunchedItem = true
        stateLock.unlock()

        hide(restorePreviousApp: false)

        // Route `gmail <query>`, `drive <query>`, etc. into the exact browser & existing profile
        // where the user actually uses that site!
        if let preferred = BrowserIndexManager.shared.preferredBrowserAndProfile(forDomain: action.domain) {
            openURLInBrowser(
                action.targetURL,
                source: preferred.source,
                profileDirectory: preferred.profileDirectory,
                preferDefaultBrowser: false
            )
        } else {
            NSWorkspace.shared.open(action.targetURL)
        }
    }

    /// Opens a URL directly inside an existing Chromium profile window (as a new tab) using
    /// Chromium's ProcessSingleton IPC when running, guaranteeing we NEVER spawn a new profile
    /// or open the wrong Chrome profile window.
    private func openURLInBrowser(
        _ url: URL,
        source: BrowserSource,
        profileDirectory: String?,
        preferDefaultBrowser: Bool
    ) {
        if preferDefaultBrowser {
            NSWorkspace.shared.open(url)
            return
        }

        guard let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else {
            NSWorkspace.shared.open(url)
            return
        }

        // For Chrome / Brave / Edge / Vivaldi with a verified existing profile folder on disk:
        if source.supportsChromiumProfileFlag,
           let profileDir = profileDirectory,
           BrowserIndexManager.chromiumProfileExists(source: source, profileDirectory: profileDir) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).first

            if let runningApp = running,
               let execURL = Bundle(url: browserURL)?.executableURL {
                DispatchQueue.global(qos: .userInitiated).async {
                    let proc = Process()
                    proc.executableURL = execURL
                    proc.arguments = ["--profile-directory=\(profileDir)", url.absoluteString]
                    proc.standardOutput = FileHandle.nullDevice
                    proc.standardError = FileHandle.nullDevice
                    try? proc.run()
                    DispatchQueue.main.async {
                        runningApp.activate()
                    }
                }
                return
            } else {
                // Browser isn't running yet -> launch cleanly via LaunchServices into that exact profile
                DispatchQueue.global(qos: .userInitiated).async {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    proc.arguments = ["-a", browserURL.path, "--args", "--profile-directory=\(profileDir)", url.absoluteString]
                    proc.standardOutput = FileHandle.nullDevice
                    proc.standardError = FileHandle.nullDevice
                    try? proc.run()
                }
                return
            }
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: config, completionHandler: nil)
    }

    public func revealInFinder(_ item: IndexedFileItem) {
        stateLock.lock()
        let q = currentQuery
        lastLaunchedItem = true
        stateLock.unlock()

        SearchFrecencyStore.shared.recordLaunch(itemID: item.id, query: q)
        hide(restorePreviousApp: false)
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                finder.activate()
            }
        }
    }

    public func openInCodeEditor(_ item: IndexedFileItem) {
        stateLock.lock()
        let q = currentQuery
        lastLaunchedItem = true
        stateLock.unlock()

        SearchFrecencyStore.shared.recordLaunch(itemID: item.id, query: q)
        hide(restorePreviousApp: false)
        for editorPath in ["/Applications/Cursor.app", "/Applications/Visual Studio Code.app", "/Applications/Zed.app", "/Applications/Sublime Text.app"] {
            if FileManager.default.fileExists(atPath: editorPath) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                proc.arguments = ["-a", editorPath, item.url.path]
                try? proc.run()
                return
            }
        }
        NSWorkspace.shared.open(item.url)
    }

    public func copyFileToClipboard(_ item: IndexedFileItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item.url as NSURL])
        pb.setString(item.url.path, forType: .string)
        NSSound(named: "Glass")?.play()
        SeekToast.show(title: "Copied Path & File", subtitle: item.name, icon: "doc.on.clipboard.fill")
    }

    public func toggleQuickLook(for item: IndexedFileItem) {
        self.previewURL = item.url
        guard let ql = QLPreviewPanel.shared() else { return }
        if ql.isVisible {
            ql.orderOut(nil)
            panel?.makeKeyAndOrderFront(nil)
            panel?.focusPrimaryTextField(selectAll: false)
        } else {
            ql.dataSource = self
            ql.delegate = self
            ql.makeKeyAndOrderFront(nil)
            ql.reloadData()
        }
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL != nil ? 1 : 0
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        (previewURL as NSURL?) ?? nil
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - Window Presentation (Floating Compact Bar → Expanded Palette)
    // ─────────────────────────────────────────────────────────────

    public func toggle(previousApp: NSRunningApplication? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.panel?.isVisible == true {
                self.hide(restorePreviousApp: true)
            } else {
                self.show(previousApp: previousApp)
            }
        }
    }

    public func show(previousApp: NSRunningApplication? = nil, initialQuery: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
                self.previousApp = prev
            } else if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
                self.previousApp = front
            }

            self.stateLock.lock()
            let shouldClearStale = (initialQuery == nil) && (self.lastLaunchedItem || Date().timeIntervalSince(self.lastHideTime) > 20.0)
            let existingQuery = self.currentQuery
            self.lastLaunchedItem = false
            self.stateLock.unlock()

            self.refreshIndexIfNeeded()
            BrowserIndexManager.shared.refreshIfNeeded()

            let frontRef = self.previousApp
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let wins = OpenWindowLookup.fetchOpenWindows(prioritizingApp: frontRef)
                guard let self = self else { return }
                self.stateLock.lock()
                self.cachedOpenWindows = wins
                let activeQ = self.currentQuery
                let activeCat = self.currentCategory
                self.stateLock.unlock()
                if !activeQ.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.performSearch(query: activeQ, category: activeCat)
                }
            }

            let queryToApply: String? = initialQuery ?? (shouldClearStale ? "" : nil)
            let effectiveQuery = queryToApply ?? existingQuery
            let startExpanded = !effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if self.panel == nil {
                let initialSize = startExpanded ? Self.expandedSize : Self.compactSize
                let panel = SeekPanel(
                    contentRect: NSRect(origin: .zero, size: initialSize),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.isFloatingPanel = true
                panel.level = .floating
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.becomesKeyOnlyIfNeeded = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.quickLookDataSource = self
                panel.quickLookDelegate = self
                panel.onEscape = { [weak self] in
                    if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
                        QLPreviewPanel.shared().orderOut(nil)
                    } else {
                        self?.hide()
                    }
                }
                panel.onResignKey = { [weak self] in
                    if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
                        return
                    }
                    self?.hide(restorePreviousApp: false)
                }

                let host = NSHostingView(
                    rootView: SeekHUDView(
                        manager: self,
                        onClose: { [weak self] in self?.hide() }
                    )
                )
                panel.contentView = host
                panel.primaryTextField = self.searchTextField
                self.panel = panel
            }

            guard let panel = self.panel else { return }
            panel.primaryTextField = self.searchTextField
            self.isExpanded = startExpanded

            let screen = NSScreen.screens.first(where: { NSPointInRect(NSEvent.mouseLocation, $0.frame) }) ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let targetSize = startExpanded ? Self.expandedSize : Self.compactSize

            // Anchor top edge cleanly at ~78% up the visible screen so expanding downward feels effortless!
            let midX = round(visible.midX)
            let topY = round(visible.minY + visible.height * 0.78)
            self.anchoredMidX = midX
            self.anchoredTopY = topY

            let targetFrame = NSRect(
                x: round(midX - targetSize.width / 2.0),
                y: round(topY - targetSize.height),
                width: targetSize.width,
                height: targetSize.height
            )
            panel.setFrame(targetFrame, display: true)

            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)

            let selectAll = (queryToApply == nil)
            self.onRequestFocus?(queryToApply, selectAll)
            panel.focusPrimaryTextField(selectAll: selectAll)

            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self = self, let panel = panel else { return }
                panel.primaryTextField = self.searchTextField
                panel.focusPrimaryTextField(selectAll: selectAll)
            }
        }
    }

    public func hide(restorePreviousApp: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            self.lastHideTime = Date()
            let md = self.activeMDQuery
            self.activeMDQuery = nil
            self.stateLock.unlock()

            if let md = md { MDQueryStop(md) }

            if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().orderOut(nil)
            }
            self.panel?.orderOut(nil)
            if restorePreviousApp,
               let prev = self.previousApp,
               prev.bundleIdentifier != Bundle.main.bundleIdentifier {
                prev.activate()
            }
        }
    }
}
