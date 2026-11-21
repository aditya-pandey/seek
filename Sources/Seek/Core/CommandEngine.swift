import AppKit
import SwiftUI
import Foundation

public struct QuickCommandResult: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let badge: String
    public let iconName: String
    public let copyValue: String?
    public let actionID: String

    public init(
        id: String,
        title: String,
        subtitle: String,
        badge: String,
        iconName: String,
        copyValue: String? = nil,
        actionID: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.iconName = iconName
        self.copyValue = copyValue
        self.actionID = actionID
    }
}

/// Lightweight floating frosted-glass toast confirmation for Seek actions.
public final class SeekToast {
    private static var activePanel: NSPanel?
    private static var dismissWork: DispatchWorkItem?

    public static func show(title: String, subtitle: String, icon: String = "checkmark.circle.fill") {
        DispatchQueue.main.async {
            dismissWork?.cancel()
            activePanel?.orderOut(nil)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 290, height: 54),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(SeekTheme.steelSapphire.opacity(0.20))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SeekTheme.steelSapphire)
                }
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.72))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(width: 290, height: 54)
            .background(
                ZStack {
                    VisualEffectBlurView(material: .hudWindow, blendingMode: .behindWindow)
                    Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.62)
                }
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.9))

            panel.contentView = NSHostingView(rootView: view)

            let screen = NSScreen.screens.first(where: { NSPointInRect(NSEvent.mouseLocation, $0.frame) }) ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            panel.setFrameOrigin(CGPoint(
                x: round(visible.midX - 145),
                y: round(visible.minY + 64)
            ))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            activePanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                panel.animator().alphaValue = 1.0
            }

            let work = DispatchWorkItem {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.20
                    panel.animator().alphaValue = 0.0
                }, completionHandler: {
                    panel.orderOut(nil)
                })
            }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: work)
        }
    }
}

public final class CommandEngine {
    public static let shared = CommandEngine()
    private var caffeinateProcess: Process?

    private init() {}

    public var isCaffeinateActive: Bool {
        caffeinateProcess?.isRunning == true
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 1. Instant Math & Unit / Currency / Time Evaluation
    // ─────────────────────────────────────────────────────────────
    public static func evaluateInline(query: String) -> QuickCommandResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        let lower = trimmed.lowercased()

        // A. Unix Epoch & "now" Timestamp
        if lower == "now" || lower == "epoch" || lower == "timestamp" {
            let now = Date()
            let iso = DateFormatter()
            iso.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let ts = Int(now.timeIntervalSince1970)
            return QuickCommandResult(
                id: "cmd_epoch_now",
                title: "\(ts)  (\(iso.string(from: now)))",
                subtitle: "Press ⏎ to copy Unix timestamp",
                badge: "TIME",
                iconName: "clock.fill",
                copyValue: "\(ts)",
                actionID: "copy"
            )
        }

        if lower.hasPrefix("unix ") || lower.hasPrefix("ts ") {
            let numStr = lower.replacingOccurrences(of: "unix ", with: "")
                .replacingOccurrences(of: "ts ", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let raw = Double(numStr) {
                let seconds = raw > 1e11 ? raw / 1000.0 : raw
                let date = Date(timeIntervalSince1970: seconds)
                let df = DateFormatter()
                df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                let formatted = df.string(from: date)
                return QuickCommandResult(
                    id: "cmd_unix_parse",
                    title: formatted,
                    subtitle: "Press ⏎ to copy readable date",
                    badge: "TIME",
                    iconName: "clock.fill",
                    copyValue: formatted,
                    actionID: "copy"
                )
            }
        }

        // B. Unit & Currency Conversions ("1440 px to rem", "450 usd to inr", "100 km in mi")
        if let conv = evaluateConversion(lower: lower) {
            return conv
        }

        // C. "18% of 2400" natural percentage phrasing
        if let pctMatch = parsePercentOf(lower) {
            let formatted = MathEvaluator.format(pctMatch)
            return QuickCommandResult(
                id: "cmd_math_pct",
                title: "= \(formatted)",
                subtitle: "\(trimmed) · Press ⏎ to copy result",
                badge: "MATH",
                iconName: "function",
                copyValue: formatted,
                actionID: "copy"
            )
        }

        // D. Direct arithmetic expression
        let hasOperator = lower.contains("+") || lower.contains("-") || lower.contains("*")
            || lower.contains("/") || lower.contains("^") || lower.contains("%") || lower.contains("sqrt(")
        if hasOperator, let val = MathEvaluator.evaluate(trimmed) {
            let formatted = MathEvaluator.format(val)
            return QuickCommandResult(
                id: "cmd_math",
                title: "= \(formatted)",
                subtitle: "\(trimmed) · Press ⏎ to copy result",
                badge: "MATH",
                iconName: "function",
                copyValue: formatted,
                actionID: "copy"
            )
        }

        return nil
    }

    private static func parsePercentOf(_ lower: String) -> Double? {
        let parts = lower.components(separatedBy: " of ")
        guard parts.count == 2 else { return nil }
        let left = parts[0].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        let right = parts[1].trimmingCharacters(in: .whitespaces)
        guard let pct = Double(left), let base = MathEvaluator.evaluate(right) else { return nil }
        return (pct / 100.0) * base
    }

    public static func evaluateConversion(lower: String) -> QuickCommandResult? {
        let normalized = lower.replacingOccurrences(of: " in ", with: " to ")
        let halves = normalized.components(separatedBy: " to ")
        guard halves.count == 2 else { return nil }

        let targetUnit = halves[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let leftRaw = halves[0].trimmingCharacters(in: .whitespacesAndNewlines)

        var numChars = ""
        var unitChars = ""
        for ch in leftRaw {
            if unitChars.isEmpty && (ch.isNumber || ch == "." || ch == "-") {
                numChars.append(ch)
            } else {
                unitChars.append(ch)
            }
        }
        let srcUnit = unitChars.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(numChars), !srcUnit.isEmpty, !targetUnit.isEmpty else { return nil }

        var converted: Double?
        var outLabel = targetUnit
        var note = "Press ⏎ to copy converted value"

        switch (srcUnit, targetUnit) {
        case ("px", "rem"):   converted = value / 16.0; outLabel = "rem"; note = "At 16px root · Press ⏎ to copy"
        case ("rem", "px"):   converted = value * 16.0; outLabel = "px";  note = "At 16px root · Press ⏎ to copy"
        case ("km", "mi"), ("km", "miles"): converted = value * 0.621371; outLabel = "mi"
        case ("mi", "km"), ("miles", "km"): converted = value / 0.621371; outLabel = "km"
        case ("kg", "lbs"), ("kg", "lb"):   converted = value * 2.20462;  outLabel = "lbs"
        case ("lbs", "kg"), ("lb", "kg"):   converted = value / 2.20462;  outLabel = "kg"
        case ("c", "f"):      converted = (value * 9.0 / 5.0) + 32.0; outLabel = "°F"
        case ("f", "c"):      converted = (value - 32.0) * 5.0 / 9.0; outLabel = "°C"
        case ("gb", "mb"):    converted = value * 1024.0; outLabel = "MB"
        case ("mb", "gb"):    converted = value / 1024.0; outLabel = "GB"
        case ("tb", "gb"):    converted = value * 1024.0; outLabel = "GB"
        case ("usd", "inr"):  converted = value * 84.5; outLabel = "INR"; note = "Approx. reference FX · Press ⏎ to copy"
        case ("inr", "usd"):  converted = value / 84.5; outLabel = "USD"; note = "Approx. reference FX · Press ⏎ to copy"
        case ("eur", "usd"):  converted = value * 1.08; outLabel = "USD"; note = "Approx. reference FX · Press ⏎ to copy"
        case ("usd", "eur"):  converted = value / 1.08; outLabel = "EUR"; note = "Approx. reference FX · Press ⏎ to copy"
        case ("gbp", "inr"):  converted = value * 107.0; outLabel = "INR"; note = "Approx. reference FX · Press ⏎ to copy"
        case ("gbp", "usd"):  converted = value * 1.27; outLabel = "USD"; note = "Approx. reference FX · Press ⏎ to copy"
        default: break
        }

        guard let outVal = converted else { return nil }
        let formatted = MathEvaluator.format(outVal)
        return QuickCommandResult(
            id: "cmd_conv_\(srcUnit)_\(targetUnit)",
            title: "\(formatted) \(outLabel)",
            subtitle: note,
            badge: "CONVERT",
            iconName: "arrow.left.arrow.right",
            copyValue: formatted,
            actionID: "copy"
        )
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: - 2. Tightly-Scoped System & Context Commands
    // ─────────────────────────────────────────────────────────────
    public static func matchingCommands(query: String, frontAppBundleID: String?) -> [QuickCommandResult] {
        scoredCommands(query: query, frontAppBundleID: frontAppBundleID).map { $0.command }
    }

    public static func scoredCommands(query: String, frontAppBundleID: String?) -> [(command: QuickCommandResult, score: Double)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 2 else { return [] }

        var catalog: [(QuickCommandResult, [String])] = [
            (
                QuickCommandResult(
                    id: "sys_dark_mode",
                    title: "Toggle Dark / Light Mode",
                    subtitle: "Switch macOS system appearance immediately",
                    badge: "SYSTEM",
                    iconName: "moon.stars.fill",
                    actionID: "dark_mode"
                ),
                ["dark mode", "light mode", "toggle dark", "appearance", "theme"]
            ),
            (
                QuickCommandResult(
                    id: "sys_caffeinate",
                    title: shared.isCaffeinateActive ? "Stop Keep-Awake (Caffeinate Active)" : "Keep Mac Awake (Caffeinate 1h)",
                    subtitle: shared.isCaffeinateActive ? "Allow display sleep normally" : "Prevent Mac sleep while downloads or builds run",
                    badge: "SYSTEM",
                    iconName: "cup.and.saucer.fill",
                    actionID: "caffeinate"
                ),
                ["caffeinate", "keep awake", "stay awake", "prevent sleep", "awake"]
            ),
            (
                QuickCommandResult(
                    id: "sys_copy_ip",
                    title: "Copy Local IP Address",
                    subtitle: "Copy active LAN / Wi-Fi IPv4 address to clipboard",
                    badge: "SYSTEM",
                    iconName: "network",
                    actionID: "copy_ip"
                ),
                ["copy ip", "ip address", "local ip", "my ip", "ipv4"]
            ),
            (
                QuickCommandResult(
                    id: "sys_empty_trash",
                    title: "Empty Trash",
                    subtitle: "Move Finder Trash contents permanently out of disk",
                    badge: "SYSTEM",
                    iconName: "trash.fill",
                    actionID: "empty_trash"
                ),
                ["empty trash", "clear trash"]
            ),
            (
                QuickCommandResult(
                    id: "sys_lock",
                    title: "Sleep Display / Lock Screen",
                    subtitle: "Put display to sleep immediately",
                    badge: "SYSTEM",
                    iconName: "lock.fill",
                    actionID: "lock_screen"
                ),
                ["lock screen", "sleep display", "sleep screen", "lock mac"]
            )
        ]

        let bundle = (frontAppBundleID ?? "").lowercased()
        if bundle.contains("chrome") || bundle.contains("safari") || bundle.contains("arc") || bundle.contains("brave") {
            catalog.insert((
                QuickCommandResult(
                    id: "ctx_clean_url",
                    title: "Browser: Copy Clean URL (Strip Tracking)",
                    subtitle: "Copies active tab URL without ?utm_*, fbclid, gclid, si=",
                    badge: "CONTEXT",
                    iconName: "link.badge.plus",
                    actionID: "clean_url"
                ),
                ["clean url", "copy url", "strip tracking", "clean link"]
            ), at: 0)
        } else if bundle == "com.apple.finder" {
            catalog.insert((
                QuickCommandResult(
                    id: "ctx_finder_cursor",
                    title: "Finder: Open Selected Folder in Cursor / VS Code",
                    subtitle: "Opens the active Finder folder directly in your code editor",
                    badge: "CONTEXT",
                    iconName: "chevron.left.forwardslash.chevron.right",
                    actionID: "finder_editor"
                ),
                ["open in cursor", "open in vscode", "finder editor", "open folder in editor"]
            ), at: 0)
        }

        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var scored: [(command: QuickCommandResult, score: Double)] = []

        for (cmd, keywords) in catalog {
            let titleLower = cmd.title.lowercased()
            let kwJoined = keywords.joined(separator: " ")

            if keywords.contains(trimmed) {
                scored.append((cmd, 340.0))
                continue
            }
            if trimmed.count >= 3, keywords.contains(where: { $0.hasPrefix(trimmed) }) {
                scored.append((cmd, 240.0))
                continue
            }

            let words = (titleLower + " " + kwJoined)
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)

            var allMatched = true
            var pts = 0.0
            for tok in tokens {
                if words.contains(tok) {
                    pts += 90.0
                } else if tok.count >= 3, words.contains(where: { $0.hasPrefix(tok) }) {
                    pts += 68.0
                } else {
                    allMatched = false
                    break
                }
            }
            if allMatched && pts > 0 {
                let finalScore = tokens.count >= 2 ? (120.0 + pts) : min(175.0, 70.0 + pts)
                scored.append((cmd, finalScore))
            }
        }

        return scored.sorted { $0.score > $1.score }
    }

    public static func execute(_ cmd: QuickCommandResult, previousApp: NSRunningApplication? = nil) {
        if let val = cmd.copyValue, cmd.actionID == "copy" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(val, forType: .string)
            NSSound(named: "Glass")?.play()
            SeekToast.show(title: "Copied to Clipboard", subtitle: val, icon: cmd.iconName)
            return
        }

        switch cmd.actionID {
        case "dark_mode":
            runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            SeekToast.show(title: "Appearance Toggled", subtitle: "Switched Dark / Light Mode", icon: "moon.stars.fill")

        case "caffeinate":
            shared.toggleCaffeinate()

        case "copy_ip":
            if let ip = fetchLocalIPAddress() {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ip, forType: .string)
                NSSound(named: "Glass")?.play()
                SeekToast.show(title: "Local IP Copied", subtitle: ip, icon: "network")
            }

        case "empty_trash":
            runAppleScript("tell application \"Finder\" to empty trash")
            SeekToast.show(title: "Trash Emptied", subtitle: "Finder Trash cleared", icon: "trash.fill")

        case "lock_screen":
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            proc.arguments = ["displaysleepnow"]
            try? proc.run()

        case "clean_url":
            copyCleanBrowserURL(bundleID: previousApp?.bundleIdentifier)

        case "finder_editor":
            openSelectedFinderFolderInEditor()

        default:
            break
        }
    }

    private func toggleCaffeinate() {
        if let proc = caffeinateProcess, proc.isRunning {
            proc.terminate()
            caffeinateProcess = nil
            SeekToast.show(title: "Caffeinate Stopped", subtitle: "Normal sleep restored", icon: "cup.and.saucer")
        } else {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            proc.arguments = ["-d", "-i", "-t", "3600"]
            try? proc.run()
            caffeinateProcess = proc
            SeekToast.show(title: "Keep-Awake Active (1h)", subtitle: "Display will stay awake", icon: "cup.and.saucer.fill")
        }
    }

    public static func stripTrackingParams(from rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL) else { return rawURL }
        let blockedParams: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "si", "igshid"
        ]
        if let items = components.queryItems {
            let filtered = items.filter { !blockedParams.contains($0.name.lowercased()) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        return components.string ?? rawURL
    }

    private static func copyCleanBrowserURL(bundleID: String?) {
        let lower = (bundleID ?? "").lowercased()
        let appScriptName: String
        if lower.contains("safari") { appScriptName = "Safari" }
        else if lower.contains("arc") { appScriptName = "Arc" }
        else if lower.contains("brave") { appScriptName = "Brave Browser" }
        else { appScriptName = "Google Chrome" }

        let script = (appScriptName == "Safari")
            ? "tell application \"Safari\" to return (URL of current tab of front window)"
            : "tell application \"\(appScriptName)\" to return (URL of active tab of front window)"

        guard let rawURL = runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            SeekToast.show(title: "Browser Access Needed", subtitle: "Allow Automation in System Settings", icon: "exclamationmark.triangle")
            return
        }

        let clean = stripTrackingParams(from: rawURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clean, forType: .string)
        NSSound(named: "Glass")?.play()
        SeekToast.show(title: "Clean URL Copied", subtitle: clean, icon: "link.badge.plus")
    }

    private static func openSelectedFinderFolderInEditor() {
        guard let path = runAppleScript("tell application \"Finder\" to get POSIX path of (insertion location as alias)")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return }
        for ed in ["/Applications/Cursor.app", "/Applications/Visual Studio Code.app", "/Applications/Zed.app"]
        where FileManager.default.fileExists(atPath: ed) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", ed, path]
            try? p.run()
            return
        }
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func fetchLocalIPAddress() -> String? {
        for iface in ["en0", "en1"] {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
            proc.arguments = ["getifaddr", iface]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty {
                    return ip
                }
            }
        }
        return nil
    }
}
