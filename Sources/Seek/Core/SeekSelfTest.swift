import Foundation
import SQLite3

public enum SeekSelfTest {
    private static var passedCount = 0
    private static var failedCount = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) {
        if condition() {
            passedCount += 1
        } else {
            failedCount += 1
            print("  ❌ FAIL [\(file):\(line)]: \(message)")
        }
    }

    private static func expectApprox(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-6, _ message: String) {
        guard let actual = actual, abs(actual - expected) <= tolerance else {
            failedCount += 1
            print("  ❌ FAIL: \(message) — expected \(expected), got \(String(describing: actual))")
            return
        }
        passedCount += 1
    }

    public static func runAllTests() -> Bool {
        passedCount = 0
        failedCount = 0
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧪 Running Seek Automated QA & Search Test Suite...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        testScorerAndFilters()
        testQueryParser()
        testMathAndCommands()
        testFrecencyStore()
        testBrowserBookmarksHistoryAndSiteSearch()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if failedCount == 0 {
            print("✅ ALL \(passedCount) SEEK TESTS PASSED (0 failures)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return true
        } else {
            print("❌ \(failedCount) SEEK TEST(S) FAILED (\(passedCount) passed)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return false
        }
    }

    private static func testScorerAndFilters() {
        print("▸ Testing SeekSearchManager (Noise, iCloud, CamelCase, Typos & Ranking)...")
        expect(SeekSearchManager.isNoisyPath("/Users/test/Documents/app/node_modules/react/index.js"), "Blocks node_modules")
        expect(SeekSearchManager.isNoisyPath("/Users/test/Library/Caches/foo.db"), "Blocks Library/Caches")
        expect(!SeekSearchManager.isNoisyPath("/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Reports/Q1.pdf"), "Allows iCloud Drive")
        expect(!SeekSearchManager.isNoisyPath("/Users/test/Documents/Invoices/2026_Invoice.pdf"), "Allows clean user document")

        let now = Date()
        let swiftFile = IndexedFileItem(
            id: "/Users/test/Documents/seek/Sources/Seek/Core/SeekSearchManager.swift",
            url: URL(fileURLWithPath: "/Users/test/Documents/seek/Sources/Seek/Core/SeekSearchManager.swift"),
            name: "SeekSearchManager.swift",
            nameLower: "seeksearchmanager.swift",
            parentName: "Core",
            parentNameLower: "core",
            displayPath: "~/Documents/seek/Sources/Seek/Core",
            ext: "swift",
            isDirectory: false,
            isProjectRepo: false,
            modificationDate: now,
            fileSize: 15000,
            depth: 5
        )
        expect(SeekSearchManager.matchesCategory(item: swiftFile, category: .all), "Deep code file remains searchable in All mode")
        expect(swiftFile.initialsLower == "ssm", "Extracts CamelCase initials 'ssm'")
        expect((SeekSearchManager.scoreItem(swiftFile, tokens: ["ssm"], now: now) ?? 0) > 160.0, "'ssm' matches SeekSearchManager.swift")

        let chromeApp = IndexedFileItem(
            id: "/Applications/Google Chrome.app",
            url: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            name: "Google Chrome",
            nameLower: "google chrome.app",
            parentName: "Applications",
            parentNameLower: "applications",
            displayPath: "/Applications",
            ext: "app",
            isDirectory: false,
            isApplication: true,
            isProjectRepo: false,
            modificationDate: now,
            fileSize: 0,
            depth: 0
        )
        expect(chromeApp.initialsLower == "gc", "Computes initials 'gc' for Google Chrome")
        expect((SeekSearchManager.scoreItem(chromeApp, tokens: ["chorme"], now: now) ?? 0) > 100.0, "Typo 'chorme' matches Google Chrome")

        let underscoreDoc = IndexedFileItem(
            id: "/Users/test/Documents/Weapon_Wheel_PRD.md",
            url: URL(fileURLWithPath: "/Users/test/Documents/Weapon_Wheel_PRD.md"),
            name: "Weapon_Wheel_PRD.md",
            nameLower: "weapon_wheel_prd.md",
            parentName: "Documents",
            parentNameLower: "documents",
            displayPath: "~/Documents",
            ext: "md",
            isDirectory: false,
            isProjectRepo: false,
            modificationDate: now,
            fileSize: 4096,
            depth: 1
        )
        expect((SeekSearchManager.scoreItem(underscoreDoc, tokens: ["weaponwheel"], now: now) ?? 0) > 120.0, "'weaponwheel' matches Weapon_Wheel_PRD.md")
    }

    private static func testQueryParser() {
        print("▸ Testing ParsedSearchQuery (Scopes, Type Aliases, Content, Paths)...")
        let scoped = ParsedSearchQuery.parse("in:downloads invoice pdf")
        expect(scoped.scopeLabel == "Downloads", "Parses in:downloads")
        expect(scoped.forcedExtensions.contains("pdf"), "Extracts .pdf extension")
        expect(scoped.searchTokens == ["invoice"], "Retains 'invoice' token")

        let content = ParsedSearchQuery.parse("content:quarterly budget")
        expect(content.forceContentSearch, "Parses content: modifier")
        expect(content.searchTokens == ["quarterly", "budget"], "Extracts content tokens")

        let path = ParsedSearchQuery.parse("~/Documents/")
        expect(path.isPathMode, "Detects ~/ path mode")
    }

    private static func testMathAndCommands() {
        print("▸ Testing MathEvaluator & CommandEngine (Inline Math, Units, Non-Hijacking)...")
        expectApprox(MathEvaluator.evaluate("2 + 3 * 4"), 14.0, "2 + 3 * 4 = 14")
        expectApprox(MathEvaluator.evaluate("125 *"), 125.0, "Incomplete '125 *' evaluates safely")
        expect(CommandEngine.evaluateInline(query: "18% of 2400")?.copyValue == "432", "18% of 2400 = 432")
        expect(CommandEngine.evaluateInline(query: "1440 px to rem")?.copyValue == "90", "1440 px to rem = 90")
        expect(CommandEngine.stripTrackingParams(from: "https://example.com/a?utm_source=x&id=7") == "https://example.com/a?id=7", "Strips tracking params")
        expect(CommandEngine.matchingCommands(query: "chrome", frontAppBundleID: nil).isEmpty, "'chrome' does not trigger false system commands")
        expect(!CommandEngine.matchingCommands(query: "dark mode", frontAppBundleID: nil).isEmpty, "'dark mode' matches appearance command")
    }

    private static func testFrecencyStore() {
        print("▸ Testing SearchFrecencyStore (Query Affinity & Persistence)...")
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("seek_frec_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = SearchFrecencyStore(customStorageURL: tempURL)
        store.recordLaunch(itemID: "/Applications/Google Chrome.app", query: "ch")
        expect(store.boost(for: "/Applications/Google Chrome.app", query: "ch") > 70.0, "Boosts launched item for query 'ch'")
    }

    private static func testBrowserBookmarksHistoryAndSiteSearch() {
        print("▸ Testing BrowserIndexManager (Bookmarks JSON, SQLite History, Dedup, Scoring & Site Search)...")

        // 1. URL filtering & canonicalization
        expect(BrowserIndexManager.isNoisyURL("chrome://settings"), "Rejects chrome:// URLs")
        expect(BrowserIndexManager.isNoisyURL("https://accounts.google.com/ServiceLogin?foo=1"), "Rejects OAuth login URLs")
        expect(!BrowserIndexManager.isNoisyURL("https://mail.google.com/mail/u/0/"), "Allows Gmail URL")

        let dirty = URL(string: "https://www.github.com/aditya-pandey/seek/?utm_source=twitter&fbclid=xyz")!
        expect(BrowserIndexManager.canonicalizeURL(dirty) == "https://github.com/aditya-pandey/seek", "Canonicalizes www, trailing slash & tracking params")

        // 2. Chromium Bookmarks JSON parsing
        let bmJSON = """
        {
          "roots": {
            "bookmark_bar": {
              "name": "Bookmarks Bar",
              "type": "folder",
              "children": [
                {
                  "name": "Work",
                  "type": "folder",
                  "children": [
                    { "name": "Gmail", "type": "url", "url": "https://mail.google.com/mail/u/0/", "date_added": "13350000000000000" },
                    { "name": "Chrome Flags", "type": "url", "url": "chrome://flags" }
                  ]
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let parsedBM = BrowserIndexManager.parseChromiumBookmarksData(
            bmJSON,
            source: .chrome,
            profileDirectory: "Default",
            profileDisplayName: "Personal",
            hasMultipleProfiles: true
        )
        expect(parsedBM.count == 1, "Parses valid bookmark and skips chrome://flags")
        expect(parsedBM.first?.title == "Gmail" && parsedBM.first?.folderPath == "Work", "Preserves title and folder breadcrumb")

        // 2b. Chromium Local State profile display names
        let localStateJSON = """
        {
          "profile": {
            "info_cache": {
              "Default": { "name": "Person 1", "gaia_given_name": "Personal" },
              "Profile 1": { "name": "Work" }
            }
          }
        }
        """.data(using: .utf8)!
        let profileMap = BrowserIndexManager.parseChromiumLocalState(localStateJSON)
        expect(profileMap["Default"] == "Personal" && profileMap["Profile 1"] == "Work", "Extracts human profile names from Chromium Local State")

        // 3. Chromium History SQLite safe read-only copy parsing
        let tempChromeDB = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("seek_test_chrome_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempChromeDB) }
        var db: OpaquePointer?
        if sqlite3_open(tempChromeDB.path, &db) == SQLITE_OK, let h = db {
            let setup = """
            CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER);
            INSERT INTO urls VALUES (1, 'https://mail.google.com/mail/u/0/', 'Gmail - Inbox', 120, 15, 13375000000000000, 0);
            INSERT INTO urls VALUES (2, 'https://github.com/aditya-pandey/seek', 'aditya-pandey/seek', 42, 6, 13375000000000000, 0);
            INSERT INTO urls VALUES (3, 'https://example.com/one-visit', 'Single Visit', 1, 0, 13375000000000000, 0);
            """
            sqlite3_exec(h, setup, nil, nil, nil)
            sqlite3_close(h)
        }
        let chromeHist = BrowserIndexManager.parseChromiumHistorySQLite(
            at: tempChromeDB,
            source: .chrome,
            profileDirectory: "Default",
            profileDisplayName: "Personal",
            hasMultipleProfiles: true
        )
        expect(chromeHist.count == 2, "Reads visit_count >= 2 entries safely from Chromium SQLite")
        expect(chromeHist.first?.domain == "mail.google.com", "Orders top visited Gmail entry first")

        // Multi-profile preservation: Profile 1 (Work) Gmail stays separate from Default (Personal) Gmail!
        let workGmail = BrowserSiteItem(
            url: URL(string: "https://mail.google.com/mail/u/0/")!,
            title: "Gmail",
            isBookmark: true,
            visitCount: 250,
            lastVisited: Date(),
            source: .chrome,
            profileDirectory: "Profile 1",
            profileDisplayName: "Work",
            hasMultipleProfiles: true
        )
        let multiMerged = BrowserIndexManager.deduplicateAndMerge(parsedBM + chromeHist + [workGmail])
        let gmailProfiles = multiMerged.filter { $0.domain == "mail.google.com" }
        expect(gmailProfiles.count == 2, "Keeps Work and Personal Chrome Gmail profiles distinct")
        expect((SeekSearchManager.scoreWebSite(workGmail, tokens: ["gmail", "work"]) ?? 0) > 250.0, "'gmail work' matches Work Chrome profile")

        // 4. Firefox places.sqlite safe read-only copy parsing
        let tempFFDB = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("seek_test_ff_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempFFDB) }
        var ffdb: OpaquePointer?
        if sqlite3_open(tempFFDB.path, &ffdb) == SQLITE_OK, let h = ffdb {
            let setup = """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, hidden INTEGER, frecency INTEGER, last_visit_date INTEGER);
            CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, title TEXT);
            INSERT INTO moz_places VALUES (1, 'https://figma.com', 'Figma', 35, 0, 4200, 1730000000000000);
            INSERT INTO moz_bookmarks VALUES (10, 1, 1, 'Figma Design');
            """
            sqlite3_exec(h, setup, nil, nil, nil)
            sqlite3_close(h)
        }
        let ffItems = BrowserIndexManager.parseFirefoxPlacesSQLite(at: tempFFDB)
        expect(ffItems.count == 1 && ffItems.first?.isBookmark == true && ffItems.first?.title == "Figma Design", "Reads Firefox places.sqlite bookmarks & visits")

        // 5. Deduplication merges bookmark + history visit count
        let merged = BrowserIndexManager.deduplicateAndMerge(parsedBM + chromeHist)
        let gmailMerged = merged.first(where: { $0.domain == "mail.google.com" })
        expect(gmailMerged?.isBookmark == true && (gmailMerged?.visitCount ?? 0) == 120, "Deduplication merges bookmark flag and visit count")

        // 6. Scoring calibration: root Gmail bookmark beats deep random history thread; typo 'gamil' still matches!
        let now = Date()
        let deepThread = BrowserSiteItem(
            url: URL(string: "https://mail.google.com/mail/u/0/#inbox/FMfcgzQXKLongThreadId999?view=pt")!,
            title: "Re: random thread gmail",
            isBookmark: false,
            visitCount: 2,
            lastVisited: now.addingTimeInterval(-30 * 86_400),
            source: .chrome
        )
        let gmailRootScore = SeekSearchManager.scoreWebSite(gmailMerged!, tokens: ["gmail"], now: now) ?? 0
        let threadScore = SeekSearchManager.scoreWebSite(deepThread, tokens: ["gmail"], now: now) ?? 0
        expect(gmailRootScore > threadScore, "Root Gmail bookmark outranks deep thread URL")
        expect((SeekSearchManager.scoreWebSite(gmailMerged!, tokens: ["gamil"], now: now) ?? 0) > 100.0, "Typo 'gamil' matches Gmail bookmark")

        // 7. QuickSiteSearchEngine & ParsedSearchQuery web scopes
        let gmailSearch = QuickSiteSearchEngine.match(rawQuery: "gmail invoice")
        expect(gmailSearch?.targetURL.absoluteString == "https://mail.google.com/mail/u/0/#search/invoice", "'gmail invoice' generates Gmail search URL")
        expect(QuickSiteSearchEngine.match(rawQuery: "gmail") == nil, "Plain 'gmail' does not trigger in-site search so bookmark wins")
        let ytSearch = QuickSiteSearchEngine.match(rawQuery: "yt swiftui")
        expect(ytSearch?.siteName == "YouTube" && ytSearch?.targetURL.absoluteString.contains("search_query=swiftui") == true, "'yt swiftui' generates YouTube search URL")

        let parsedWeb = ParsedSearchQuery.parse("in:bookmarks figma")
        expect(parsedWeb.webScope == .bookmarksOnly && parsedWeb.searchTokens == ["figma"], "Parses in:bookmarks scope cleanly")
        let parsedWebAll = ParsedSearchQuery.parse("in:web gmail")
        expect(parsedWebAll.webScope == .allWeb && parsedWebAll.searchTokens == ["gmail"], "Parses in:web scope cleanly")
    }
}
