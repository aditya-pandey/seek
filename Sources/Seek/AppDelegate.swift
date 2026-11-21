import AppKit
import ServiceManagement

public final class AppDelegate: NSObject, NSApplicationDelegate {
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

        setupStatusBar()
        SeekSearchManager.shared.refreshIndexIfNeeded()

        print("[Seek] Ready: \(hotkeyManager.currentPreset.shortLabel) to toggle Seek")
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let customURL = Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png"),
               let customImg = NSImage(contentsOf: customURL) {
                customImg.size = NSSize(width: 18, height: 18)
                customImg.isTemplate = true
                button.image = customImg
            } else {
                button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Seek")
            }
        }

        let menu = NSMenu()
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
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)
        self.loginItemMenuItem = loginItem

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
        SeekToast.show(title: "Refreshing Index", subtitle: "Scanning apps, folders & iCloud Drive", icon: "arrow.triangle.2.circlepath")
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
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                loginItemMenuItem?.state = .off
            } else {
                try SMAppService.mainApp.register()
                loginItemMenuItem?.state = .on
            }
        } catch {
            SeekToast.show(title: "Launch at Login", subtitle: "Move Seek.app to /Applications first", icon: "exclamationmark.triangle")
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
