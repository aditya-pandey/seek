import AppKit
import ServiceManagement

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()
    private var loginItemMenuItem: NSMenuItem?
    private var hotkeyMenuItems: [SeekHotkeyPreset: NSMenuItem] = [:]

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        hotkeyManager.onToggleSeek = {
            SeekSearchManager.shared.toggle()
        }
        hotkeyManager.registerCurrentPreset()

        configureLaunchAtLoginOnFirstRun()
        setupStatusBar()
        SeekSearchManager.shared.refreshIndexIfNeeded()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.30) {
            BrowserIndexManager.shared.refreshIfNeeded()
        }

        print("[Seek] Ready: \(hotkeyManager.currentPreset.shortLabel) to toggle Seek")
    }

    /// Automatically registers Seek as a background Login Item on first launch outside a mounted DMG,
    /// triggering macOS's native "Allow in the Background" permission flow for GitHub DMG installs.
    private func configureLaunchAtLoginOnFirstRun() {
        let path = Bundle.main.bundlePath
        guard !path.hasPrefix("/Volumes/"), path.hasSuffix(".app") else { return }

        let key = "SeekConfiguredLoginItemOnce"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        if SMAppService.mainApp.status == .notRegistered {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("[Seek] Initial launch-at-login registration failed: \(error)")
            }
        }

        if SMAppService.mainApp.status == .requiresApproval {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.promptBackgroundApprovalIfNeeded()
            }
        }
    }

    private func promptBackgroundApprovalIfNeeded() {
        guard SMAppService.mainApp.status == .requiresApproval else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow Seek to Run in Background"
        alert.informativeText = "Enable Seek under System Settings → General → Login Items & Extensions so Seek starts automatically whenever you turn on your Mac."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Login Items Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func refreshLoginMenuItem() {
        guard let item = loginItemMenuItem else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            item.title = "Launch at Login"
            item.state = .on
        case .requiresApproval:
            item.title = "Approve Background Run in Settings…"
            item.state = .mixed
        default:
            item.title = "Launch at Login"
            item.state = .off
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        refreshLoginMenuItem()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let customImg = Bundle.main.image(forResource: NSImage.Name("MenuBarTemplate")) {
                customImg.size = NSSize(width: 18, height: 18)
                customImg.isTemplate = true
                button.image = customImg
            } else {
                button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Seek")
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        let openItem = NSMenuItem(title: "Open Seek (\(hotkeyManager.currentPreset.shortLabel))", action: #selector(openSeek), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let refreshItem = NSMenuItem(title: "Refresh File Index Now", action: #selector(refreshIndex), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Shortcut submenu so Seek works cleanly alongside or without WeaponWheel/Glance
        let shortcutRoot = NSMenuItem(title: "Global Shortcut", action: nil, keyEquivalent: "")
        let shortcutMenu = NSMenu()
        for preset in SeekHotkeyPreset.allCases {
            let item = NSMenuItem(title: preset.displayLabel, action: #selector(selectHotkeyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (preset == hotkeyManager.currentPreset) ? .on : .off
            shortcutMenu.addItem(item)
            hotkeyMenuItems[preset] = item
        }
        shortcutRoot.submenu = shortcutMenu
        menu.addItem(shortcutRoot)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        self.loginItemMenuItem = loginItem
        refreshLoginMenuItem()

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Seek", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openSeek() {
        SeekSearchManager.shared.show()
    }

    @objc private func refreshIndex() {
        SeekSearchManager.shared.refreshIndexIfNeeded(force: true)
        BrowserIndexManager.shared.refreshIfNeeded(force: true)
        SeekToast.show(title: "Refreshing Index", subtitle: "Scanning files, bookmarks & top sites", icon: "arrow.triangle.2.circlepath")
    }

    @objc private func selectHotkeyPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = SeekHotkeyPreset(rawValue: raw) else { return }
        hotkeyManager.currentPreset = preset
        for (p, item) in hotkeyMenuItems {
            item.state = (p == preset) ? .on : .off
        }
        statusItem?.menu?.items.first?.title = "Open Seek (\(preset.shortLabel))"
        SeekToast.show(title: "Shortcut Updated", subtitle: "Press \(preset.shortLabel) anytime to Seek", icon: "keyboard")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            SeekToast.show(title: "Launch at Login", subtitle: "Move Seek.app to /Applications first", icon: "exclamationmark.triangle")
        }
        refreshLoginMenuItem()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
