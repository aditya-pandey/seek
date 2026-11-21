import AppKit
import ApplicationServices

public struct OpenWindowEntry: Identifiable, Equatable {
    public let id: String
    public let pid: pid_t
    public let bundleID: String
    public let appName: String
    public let title: String
    public let app: NSRunningApplication
    public let axWindow: AXUIElement

    public static func == (lhs: OpenWindowEntry, rhs: OpenWindowEntry) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}

/// Fast, non-blocking open window lookup for jumping directly to active windows from Seek.
public enum OpenWindowLookup {
    public static func fetchOpenWindows(prioritizingApp: NSRunningApplication? = nil) -> [OpenWindowEntry] {
        guard AXIsProcessTrusted() else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier

        var apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != myPID && !$0.isTerminated
        }
        if let priority = prioritizingApp {
            apps.sort { ($0.processIdentifier == priority.processIdentifier) && ($1.processIdentifier != priority.processIdentifier) }
        }

        var results: [OpenWindowEntry] = []
        for app in apps {
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.12)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let axWindows = windowsRef as? [AXUIElement] else { continue }

            let appName = app.localizedName ?? "App"
            let bundleID = app.bundleIdentifier ?? ""

            for (idx, axWin) in axWindows.enumerated() {
                var subroleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &subroleRef)
                if let subrole = subroleRef as? String, subrole != "AXStandardWindow" && subrole != "AXDialog" {
                    continue
                }

                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty else { continue }

                results.append(
                    OpenWindowEntry(
                        id: "\(pid)_\(idx)_\(title)",
                        pid: pid,
                        bundleID: bundleID,
                        appName: appName,
                        title: title,
                        app: app,
                        axWindow: axWin
                    )
                )
            }
        }
        return results
    }

    public static func focusWindow(_ entry: OpenWindowEntry) {
        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(entry.axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
           let isMin = minimizedRef as? Bool, isMin {
            AXUIElementSetAttributeValue(entry.axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(entry.axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(entry.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        entry.app.activate()
    }
}
