import Foundation

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
}
