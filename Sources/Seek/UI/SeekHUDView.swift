import SwiftUI
import AppKit
import Quartz

public final class AutoFocusNSTextField: NSTextField {
    public var onWindowAttached: (() -> Void)?

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let win = self.window else { return }
        onWindowAttached?()
        DispatchQueue.main.async { [weak self, weak win] in
            guard let self = self, let win = win else { return }
            win.makeFirstResponder(self)
        }
    }
}

public struct InstantSearchTextField: NSViewRepresentable {
    @Binding public var text: String
    public var placeholder: String
    public weak var manager: SeekSearchManager?
    public var onTextChange: (String) -> Void
    public var onMoveUp: () -> Void
    public var onMoveDown: () -> Void
    public var onTab: (Bool) -> Void
    public var onSubmit: (Bool) -> Void
    public var onEscape: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> AutoFocusNSTextField {
        let tf = AutoFocusNSTextField()
        tf.delegate = context.coordinator
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = NSFont.systemFont(ofSize: 17.0, weight: .medium)
        tf.textColor = .white
        tf.maximumNumberOfLines = 1
        tf.usesSingleLineMode = true
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        tf.lineBreakMode = .byTruncatingTail

        tf.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(white: 0.50, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 15.5, weight: .regular)
            ]
        )

        manager?.searchTextField = tf
        tf.onWindowAttached = { [weak manager, weak tf] in
            guard let tf = tf else { return }
            manager?.searchTextField = tf
        }
        return tf
    }

    public func updateNSView(_ nsView: AutoFocusNSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
            if let editor = nsView.currentEditor() {
                editor.selectedRange = NSRange(location: text.count, length: 0)
            }
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InstantSearchTextField
        init(parent: InstantSearchTextField) { self.parent = parent }

        public func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            let val = tf.stringValue
            if parent.text != val { parent.text = val }
            parent.onTextChange(val)
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveDown(_:)) { parent.onMoveDown(); return true }
            if commandSelector == #selector(NSResponder.moveUp(_:)) { parent.onMoveUp(); return true }
            if commandSelector == #selector(NSResponder.insertTab(_:)) { parent.onTab(false); return true }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) { parent.onTab(true); return true }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit(NSEvent.modifierFlags.contains(.command))
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            return false
        }
    }
}

private func highlightedAttributedTitle(_ title: String, ranges: [Range<Int>], isSelected: Bool) -> AttributedString {
    var attr = AttributedString(title)
    attr.foregroundColor = isSelected ? Color.white : Color(white: 0.91)

    guard !ranges.isEmpty else { return attr }
    let chars = Array(title)
    for r in ranges {
        guard r.lowerBound >= 0, r.upperBound <= chars.count, r.lowerBound < r.upperBound else { continue }
        let startIdx = title.index(title.startIndex, offsetBy: r.lowerBound)
        let endIdx = title.index(title.startIndex, offsetBy: r.upperBound)
        if let attrStart = AttributedString.Index(startIdx, within: attr),
           let attrEnd = AttributedString.Index(endIdx, within: attr) {
            attr[attrStart..<attrEnd].foregroundColor = SeekTheme.steelSapphire
            attr[attrStart..<attrEnd].font = .system(size: 13, weight: .bold, design: .rounded)
        }
    }
    return attr
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Seek Main Frosted Native Vibrancy HUD
// ─────────────────────────────────────────────────────────────────────────

public struct SeekHUDView: View {
    @ObservedObject var manager: SeekSearchManager
    var onClose: () -> Void

    @StateObject private var previewLoader = FilePreviewLoader()
    @State private var searchText: String = ""
    @State private var selectedCategory: SearchFilterCategory = .all
    @State private var selectedIndex: Int = 0

    public init(manager: SeekSearchManager = .shared, onClose: @escaping () -> Void) {
        self.manager = manager
        self.onClose = onClose
    }

    private var items: [UnifiedSearchResult] { manager.snapshot.items }

    private var currentResult: UnifiedSearchResult? {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    private var currentFileItem: IndexedFileItem? { currentResult?.fileItem }

    public var body: some View {
        VStack(spacing: 0) {
            topSearchBar

            if manager.isExpanded {
                categoryFilterBar
                Rectangle().fill(SeekTheme.dividerStroke).frame(height: 1)

                HStack(spacing: 0) {
                    resultsListPane
                        .frame(width: 484)

                    Rectangle().fill(SeekTheme.dividerStroke).frame(width: 1)

                    FileInspectorPane(
                        result: currentResult,
                        previewLoader: previewLoader,
                        onOpenFile: { manager.openItem($0) },
                        onRevealFile: { manager.revealInFinder($0) },
                        onOpenEditor: { manager.openInCodeEditor($0) },
                        onQuickLook: { manager.toggleQuickLook(for: $0) },
                        onCopyFile: { manager.copyFileToClipboard($0) },
                        onRunCommand: { manager.executeCommand($0) },
                        onFocusWindow: { manager.focusOpenWindow($0) },
                        onOpenWeb: { site, preferDefault in manager.openWebSite(site, preferDefaultBrowser: preferDefault) },
                        onCopyWebURL: { manager.copyWebURL($0) },
                        onOpenSiteSearch: { manager.openSiteSearch($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle().fill(SeekTheme.dividerStroke).frame(height: 1)
                bottomShortcutBar
            } else {
                Rectangle().fill(SeekTheme.dividerStroke.opacity(0.65)).frame(height: 1)
                compactQuickStrip
            }

            hiddenActionShortcuts
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectBlurView(material: .hudWindow, blendingMode: .behindWindow)
                SeekTheme.glassTint
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: manager.isExpanded ? 18 : 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: manager.isExpanded ? 18 : 16, style: .continuous)
                .stroke(SeekTheme.specularRimGradient, lineWidth: 1.1)
        )
        .onAppear {
            selectedIndex = 0
            manager.onRequestFocus = { initialQuery, _ in
                selectedIndex = 0
                if let q = initialQuery {
                    searchText = q
                    manager.searchTextField?.stringValue = q
                    if q.isEmpty { selectedCategory = .all }
                    manager.performSearch(query: q, category: selectedCategory)
                } else {
                    manager.performSearch(query: searchText, category: selectedCategory)
                }
            }
            manager.performSearch(query: searchText, category: selectedCategory)
        }
        .onChange(of: manager.snapshot) { _, newSnap in
            if selectedIndex >= newSnap.items.count {
                selectedIndex = max(0, newSnap.items.count - 1)
            }
            if manager.isExpanded {
                syncPreview()
            }
        }
        .onChange(of: selectedIndex) { _, _ in
            if manager.isExpanded { syncPreview() }
        }
        .onChange(of: manager.isExpanded) { _, expanded in
            if expanded { syncPreview() }
        }
    }

    private func syncPreview() {
        previewLoader.loadPreview(for: currentFileItem)
    }

    // ── Top Frosted Search Bar ──
    @ViewBuilder
    private var topSearchBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(SeekTheme.steelSapphire.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(SeekTheme.steelSapphire.opacity(0.32), lineWidth: 0.9))

                if manager.snapshot.isSearchingDeep {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeekTheme.steelSapphire)
                }
            }

            InstantSearchTextField(
                text: $searchText,
                placeholder: "Seek files, apps, bookmarks, gmail <query>, in:downloads, or 18% of 2400...",
                manager: manager,
                onTextChange: { newValue in
                    selectedIndex = 0
                    let hasText = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if hasText && !manager.isExpanded {
                        manager.setExpanded(true, animated: true)
                    } else if !hasText && selectedCategory == .all && manager.isExpanded {
                        manager.setExpanded(false, animated: true)
                    }
                    manager.performSearch(query: newValue, category: selectedCategory)
                },
                onMoveUp: {
                    if !manager.isExpanded {
                        expandWithRecents()
                        return
                    }
                    if !items.isEmpty {
                        selectedIndex = (selectedIndex - 1 + items.count) % items.count
                    }
                },
                onMoveDown: {
                    if !manager.isExpanded {
                        expandWithRecents()
                        return
                    }
                    if !items.isEmpty {
                        selectedIndex = (selectedIndex + 1) % items.count
                    }
                },
                onTab: { isShift in
                    handleTab(reverse: isShift)
                },
                onSubmit: { isCommand in
                    if !manager.isExpanded {
                        expandWithRecents()
                    } else {
                        triggerCurrentSelection(isCommand: isCommand)
                    }
                },
                onEscape: {
                    if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
                        QLPreviewPanel.shared().orderOut(nil)
                    } else {
                        onClose()
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 26)

            if !searchText.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.52))
                }
                .buttonStyle(.plain)
                .help("Clear search (⌘⌫)")
            }

            HStack(spacing: 5) {
                if manager.isIndexing {
                    ProgressView()
                        .scaleEffect(0.42)
                        .frame(width: 9, height: 9)
                    Text("Indexing")
                } else {
                    Circle()
                        .fill(SeekTheme.emerald)
                        .frame(width: 5.5, height: 5.5)
                    Text("\(manager.totalIndexedCount) + Spotlight")
                }
            }
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(SeekTheme.labelSecondary)
            .padding(.horizontal, 8.5)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 0.7))
            .clipShape(Capsule())
            .onTapGesture {
                manager.refreshIndexIfNeeded(force: true)
                BrowserIndexManager.shared.refreshIfNeeded(force: true)
            }
            .help("Click to refresh local index (Spotlight also searches all of ~ & iCloud Drive live)")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    // ── Compact Idle Quick-Access Strip (Shown When Query Is Empty & Collapsed) ──
    @ViewBuilder
    private var compactQuickStrip: some View {
        HStack(spacing: 7) {
            quickPill(icon: "clock.arrow.circlepath", label: "Recent", hint: "↓") {
                expandWithRecents()
            }
            quickPill(icon: "globe", label: "Web", hint: "⌘7") {
                selectCategoryAndExpand(.web)
            }
            quickPill(icon: "square.grid.2x2.fill", label: "Apps", hint: "⌘2") {
                selectCategoryAndExpand(.apps)
            }
            quickPill(icon: "doc.richtext.fill", label: "Docs", hint: "⌘3") {
                selectCategoryAndExpand(.docsAndPDFs)
            }
            quickPill(icon: "arrow.down.circle.fill", label: "Downloads", hint: nil) {
                applyQuickQuery("in:downloads ")
            }
            quickPill(icon: "icloud.fill", label: "iCloud", hint: nil) {
                applyQuickQuery("in:icloud ")
            }
            Spacer()
            Text("Type to search · ↓ Recents")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(SeekTheme.labelMuted)
        }
        .padding(.horizontal, 16)
        .frame(height: 43)
    }

    @ViewBuilder
    private func quickPill(icon: String, label: String, hint: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4.5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(SeekTheme.steelSapphire.opacity(0.90))
                Text(label)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.84))
                if let hint = hint {
                    Text(hint)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.48))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.055))
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // ── Expanded Category Bar ──
    @ViewBuilder
    private var categoryFilterBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(SearchFilterCategory.allCases.enumerated()), id: \.element.id) { idx, cat in
                let isSelected = (selectedCategory == cat)
                Button(action: {
                    selectCategoryAndExpand(cat)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: cat.iconName)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(cat.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .lineLimit(1)
                        Text("⌘\(idx + 1)")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .opacity(isSelected ? 0.82 : 0.40)
                    }
                    .foregroundStyle(isSelected ? Color.white : Color(white: 0.65))
                    .padding(.horizontal, 9.5)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(isSelected ? SeekTheme.steelSapphire.opacity(0.28) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? SeekTheme.steelSapphire.opacity(0.82) : Color.white.opacity(0.09), lineWidth: 0.9)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            if let hint = manager.snapshot.statusHint {
                Text(hint)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(SeekTheme.steelSapphire)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SeekTheme.steelSapphire.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // ── Left Pane: Ranked Results ──
    @ViewBuilder
    private var resultsListPane: some View {
        if items.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: manager.snapshot.isSearchingDeep ? "sparkle.magnifyingglass" : "doc.text.magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color(white: 0.36))

                Text(
                    manager.snapshot.isSearchingDeep
                        ? "Searching Spotlight across your Mac..."
                        : (manager.isIndexing ? "Indexing your folders..." : "No matching files, apps, or commands")
                )
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.65))

                VStack(spacing: 4) {
                    Text("Try: 'invoice pdf', 'in:downloads deck', 'content:budget', '~/Documents/'")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.46))
                    Text("Or: '18% of 2400', '1440 px to rem', 'dark mode', 'fsm'")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.42))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(items.indices, id: \.self) { idx in
                            let res = items[idx]
                            UnifiedResultRow(
                                result: res,
                                isSelected: idx == selectedIndex,
                                onSelectAndTrigger: {
                                    selectedIndex = idx
                                    triggerResult(res, isCommand: false)
                                },
                                onReveal: {
                                    if let item = res.fileItem { manager.revealInFinder(item) }
                                }
                            )
                            .id(idx)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: selectedIndex) { _, newIdx in
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    // ── Bottom Shortcut Bar ──
    @ViewBuilder
    private var bottomShortcutBar: some View {
        HStack(spacing: 12) {
            shortcutHint(key: "↑↓", label: "Move")
            shortcutHint(key: "Tab", label: "Filter / Path")
            shortcutHint(key: "⏎", label: "Open")
            shortcutHint(key: "⌘⏎", label: "Finder")
            shortcutHint(key: "⌘O", label: "Editor")
            shortcutHint(key: "⌘Y", label: "QuickLook")
            Spacer()
            Text("in:bookmarks · gmail <q> · .pdf · content:")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(SeekTheme.labelMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 31)
        .background(Color.black.opacity(0.28))
    }

    @ViewBuilder
    private func shortcutHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.82))
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 3.5))
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(SeekTheme.labelSecondary)
        }
    }

    @ViewBuilder
    private var hiddenActionShortcuts: some View {
        HStack(spacing: 0) {
            ForEach(Array(SearchFilterCategory.allCases.enumerated()), id: \.element.id) { idx, cat in
                Button("") { selectCategoryAndExpand(cat) }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
            }
            Button("") { if let item = currentFileItem { manager.revealInFinder(item) } }
                .keyboardShortcut(.return, modifiers: .command)
            Button("") {
                if let item = currentFileItem { manager.openInCodeEditor(item) }
                else if let site = currentResult?.webSiteItem { manager.openWebSite(site, preferDefaultBrowser: true) }
            }
            .keyboardShortcut("o", modifiers: .command)
            Button("") { if let item = currentFileItem { manager.toggleQuickLook(for: item) } }
                .keyboardShortcut("y", modifiers: .command)
            Button("") {
                if let item = currentFileItem { manager.copyFileToClipboard(item) }
                else if let site = currentResult?.webSiteItem { manager.copyWebURL(site) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("") { clearSearch() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // ── Actions & Navigation ──
    private func expandWithRecents() {
        selectedIndex = 0
        manager.setExpanded(true, animated: true)
        manager.performSearch(query: searchText, category: selectedCategory)
    }

    private func selectCategoryAndExpand(_ cat: SearchFilterCategory) {
        selectedCategory = cat
        selectedIndex = 0
        manager.setExpanded(true, animated: true)
        manager.performSearch(query: searchText, category: cat)
    }

    private func applyQuickQuery(_ q: String) {
        searchText = q
        manager.searchTextField?.stringValue = q
        selectedIndex = 0
        manager.setExpanded(true, animated: true)
        manager.performSearch(query: q, category: selectedCategory)
    }

    private func clearSearch() {
        searchText = ""
        selectedCategory = .all
        selectedIndex = 0
        manager.searchTextField?.stringValue = ""
        manager.setExpanded(false, animated: true)
        manager.performSearch(query: "", category: .all)
    }

    private func handleTab(reverse: Bool) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reverse, (trimmed.hasPrefix("~/") || trimmed.hasPrefix("/")),
           let item = currentFileItem, item.isDirectory {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let completed = item.id.hasPrefix(home)
                ? "~" + String(item.id.dropFirst(home.count)) + "/"
                : item.id + "/"
            applyQuickQuery(completed)
            return
        }

        let all = SearchFilterCategory.allCases
        if let idx = all.firstIndex(of: selectedCategory) {
            let nextIdx = reverse ? (idx - 1 + all.count) % all.count : (idx + 1) % all.count
            selectCategoryAndExpand(all[nextIdx])
        }
    }

    private func triggerCurrentSelection(isCommand: Bool) {
        guard let res = currentResult else { return }
        triggerResult(res, isCommand: isCommand)
    }

    private func triggerResult(_ res: UnifiedSearchResult, isCommand: Bool) {
        switch res.kind {
        case .inlineCommand(let cmd), .command(let cmd):
            manager.executeCommand(cmd)
        case .openWindow(let win):
            manager.focusOpenWindow(win)
        case .file(let item):
            if isCommand { manager.revealInFinder(item) }
            else { manager.openItem(item) }
        case .webSite(let site):
            manager.openWebSite(site, preferDefaultBrowser: isCommand)
        case .siteSearch(let action):
            manager.openSiteSearch(action)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Unified Frosted Row
// ─────────────────────────────────────────────────────────────────────────

private struct UnifiedResultRow: View {
    let result: UnifiedSearchResult
    let isSelected: Bool
    let onSelectAndTrigger: () -> Void
    let onReveal: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? SeekTheme.steelSapphire : Color.clear)
                .frame(width: 3, height: 28)

            rowIcon

            rowTextContent
                .frame(maxWidth: .infinity, alignment: .leading)

            trailingAccessory
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? SeekTheme.steelSapphire.opacity(0.19)
                        : (isHovered ? SeekTheme.rowHover : SeekTheme.rowSurface)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected
                        ? SeekTheme.steelSapphire.opacity(0.88)
                        : (isHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.05)),
                    lineWidth: isSelected ? 1.35 : 0.8
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelectAndTrigger() }
        .onHover { isHovered = $0 }
        .modifier(ConditionalFileDragModifier(fileURL: result.fileItem?.url))
    }

    @ViewBuilder
    private var rowIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.13 : 0.06))
                .frame(width: 32, height: 32)

            switch result.kind {
            case .inlineCommand(let cmd), .command(let cmd):
                Image(systemName: cmd.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeekTheme.steelSapphire)
            case .openWindow(let win):
                if let icon = win.app.icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 22, height: 22)
                } else {
                    Image(systemName: "macwindow").font(.system(size: 14)).foregroundStyle(SeekTheme.steelSapphire)
                }
            case .file(let item):
                Image(nsImage: FileIconCache.shared.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            case .webSite(let site):
                Image(nsImage: BrowserIconCache.shared.icon(for: site.source))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            case .siteSearch(let action):
                Image(systemName: action.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeekTheme.steelSapphire)
            }
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var rowTextContent: some View {
        switch result.kind {
        case .inlineCommand(let cmd), .command(let cmd):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(highlightedAttributedTitle(cmd.title, ranges: result.matchedRanges, isSelected: isSelected))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    badgePill(cmd.badge, color: SeekTheme.platinumIce)
                }
                Text(cmd.subtitle)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.56))
                    .lineLimit(1)
            }

        case .openWindow(let win):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(highlightedAttributedTitle(win.title, ranges: result.matchedRanges, isSelected: isSelected))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    badgePill("WINDOW", color: SeekTheme.steelSapphire)
                }
                Text("\(win.appName) · Switch straight to open window")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.54))
                    .lineLimit(1)
            }

        case .file(let item):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(highlightedAttributedTitle(item.name, ranges: result.matchedRanges, isSelected: isSelected))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    if item.isContentMatch {
                        badgePill("IN CONTENT", color: SeekTheme.brushedGold)
                    } else if item.isApplication {
                        badgePill("APP", color: SeekTheme.platinumIce)
                    } else if item.isProjectRepo {
                        badgePill("REPO", color: SeekTheme.emerald)
                    } else if item.ext == "pdf" {
                        badgePill("PDF", color: SeekTheme.warmChampagne)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color(white: 0.48))
                    Text(item.displayPath)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(isSelected ? Color(white: 0.72) : Color(white: 0.52))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .onTapGesture { onReveal() }
            }

        case .webSite(let site):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(highlightedAttributedTitle(site.title, ranges: result.matchedRanges, isSelected: isSelected))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    if site.isBookmark {
                        badgePill("BOOKMARK", color: SeekTheme.warmChampagne)
                    } else if site.visitCount >= 5 {
                        badgePill("TOP SITE", color: SeekTheme.steelSapphire)
                    } else {
                        badgePill(site.source.shortName.uppercased(), color: SeekTheme.platinumIce)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color(white: 0.48))
                    Text(site.displaySubtitle)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(isSelected ? Color(white: 0.72) : Color(white: 0.52))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

        case .siteSearch(let action):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Search \(action.siteName) for \"\(action.query)\"")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color(white: 0.92))
                        .lineLimit(1)
                    badgePill("SEARCH IN", color: SeekTheme.steelSapphire)
                }
                Text("\(action.domain) · Opens directly in browser")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.56))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if isSelected {
            Text("⏎")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(SeekTheme.steelSapphire.opacity(0.34))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SeekTheme.steelSapphire.opacity(0.75), lineWidth: 0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if case .file(let item) = result.kind {
            Text(item.relativeTimeString)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.52))
                .lineLimit(1)
        } else if case .webSite(let site) = result.kind {
            Text(site.visitCount >= 2 ? "\(site.visitCount)×" : site.source.shortName)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.52))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.15))
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.7))
            .clipShape(Capsule())
    }
}

private struct ConditionalFileDragModifier: ViewModifier {
    let fileURL: URL?
    func body(content: Content) -> some View {
        if let url = fileURL {
            content.onDrag { NSItemProvider(object: url as NSURL) }
        } else {
            content
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Right Inspector Pane (Live Thumbnail / Code Excerpt / Folder Peek)
// ─────────────────────────────────────────────────────────────────────────

private struct FileInspectorPane: View {
    let result: UnifiedSearchResult?
    @ObservedObject var previewLoader: FilePreviewLoader
    let onOpenFile: (IndexedFileItem) -> Void
    let onRevealFile: (IndexedFileItem) -> Void
    let onOpenEditor: (IndexedFileItem) -> Void
    let onQuickLook: (IndexedFileItem) -> Void
    let onCopyFile: (IndexedFileItem) -> Void
    let onRunCommand: (QuickCommandResult) -> Void
    let onFocusWindow: (OpenWindowEntry) -> Void
    let onOpenWeb: (BrowserSiteItem, Bool) -> Void
    let onCopyWebURL: (BrowserSiteItem) -> Void
    let onOpenSiteSearch: (SiteSearchAction) -> Void

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        Group {
            if let result = result {
                switch result.kind {
                case .file(let item): fileInspector(item)
                case .inlineCommand(let cmd), .command(let cmd): commandInspector(cmd)
                case .openWindow(let win): windowInspector(win)
                case .webSite(let site): webSiteInspector(site)
                case .siteSearch(let action): siteSearchInspector(action)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color(white: 0.34))
                    Text("Select a result to preview")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.48))
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(SeekTheme.inspectorTint)
    }

    @ViewBuilder
    private func fileInspector(_ item: IndexedFileItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.8))

                switch previewLoader.content {
                case .thumbnail(let img):
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .padding(8)

                case .textExcerpt(let text):
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(text)
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(white: 0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                    }

                case .folderContents(let entries, let total):
                    VStack(alignment: .leading, spacing: 4) {
                        if entries.isEmpty {
                            Text("Empty folder")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(white: 0.48))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ForEach(entries, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.82))
                                    .lineLimit(1)
                            }
                            if total > entries.count {
                                Text("+\(total - entries.count) more items")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SeekTheme.steelSapphire)
                                    .padding(.top, 2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                case .fallbackIcon(let icon):
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 80, height: 80)

                case .loading:
                    ProgressView().scaleEffect(0.6)

                case .idle:
                    Image(nsImage: FileIconCache.shared.icon(for: item)).resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                }
            }
            .frame(height: 164)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.displayPath)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.60))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Rectangle().fill(SeekTheme.dividerStroke).frame(height: 1)

            VStack(spacing: 5) {
                metaRow("Kind", item.isApplication ? "Application" : (item.isDirectory ? (item.isProjectRepo ? "Project Repo" : "Folder") : (item.ext.isEmpty ? "File" : item.ext.uppercased())))
                metaRow("Size", item.formattedSize)
                if item.modificationDate != .distantPast {
                    metaRow("Modified", Self.dateFormatter.string(from: item.modificationDate))
                }
                if let used = item.lastUsedDate, used != .distantPast {
                    metaRow("Last Opened", IndexedFileItem.fastRelativeTime(from: used))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Button(action: { onOpenFile(item) }) {
                    HStack(spacing: 6) {
                        Image(systemName: item.isApplication ? "arrow.up.right.square.fill" : "arrow.up.forward.app.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.isApplication ? "Launch App" : (item.isDirectory ? "Open Folder" : "Open File"))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("⏎")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 31)
                    .background(SeekTheme.steelSapphire.opacity(0.32))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SeekTheme.steelSapphire.opacity(0.75), lineWidth: 0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    inspectorMiniButton("folder.fill", "Finder", "⌘⏎") { onRevealFile(item) }
                    inspectorMiniButton("chevron.left.forwardslash.chevron.right", "Code", "⌘O") { onOpenEditor(item) }
                    inspectorMiniButton("eye.fill", "Look", "⌘Y") { onQuickLook(item) }
                    inspectorMiniButton("doc.on.doc", "Copy", "⌘⇧C") { onCopyFile(item) }
                }
            }
        }
    }

    @ViewBuilder
    private func commandInspector(_ cmd: QuickCommandResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(SeekTheme.steelSapphire.opacity(0.16))
                    .frame(width: 60, height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(SeekTheme.steelSapphire.opacity(0.45), lineWidth: 1))
                Image(systemName: cmd.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(SeekTheme.steelSapphire)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(cmd.badge).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(SeekTheme.steelSapphire)
                Text(cmd.title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(cmd.subtitle).font(.system(size: 11.5, weight: .regular, design: .rounded)).foregroundStyle(Color(white: 0.62))
            }
            Spacer()
            Button(action: { onRunCommand(cmd) }) {
                HStack {
                    Text(cmd.actionID == "copy" ? "Copy Result" : "Run Command")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("⏎").font(.system(size: 10.5, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(SeekTheme.steelSapphire.opacity(0.32))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SeekTheme.steelSapphire.opacity(0.75), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func windowInspector(_ win: OpenWindowEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            if let icon = win.app.icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 60, height: 60)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("OPEN WINDOW").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(SeekTheme.steelSapphire)
                Text(win.title).font(.system(size: 14.5, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(3)
                Text(win.appName).font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(Color(white: 0.62))
            }
            Spacer()
            Button(action: { onFocusWindow(win) }) {
                HStack {
                    Text("Focus Window").font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("⏎").font(.system(size: 10.5, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(SeekTheme.steelSapphire.opacity(0.32))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SeekTheme.steelSapphire.opacity(0.75), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func webSiteInspector(_ site: BrowserSiteItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.8))

                VStack(spacing: 10) {
                    Image(nsImage: BrowserIconCache.shared.icon(for: site.source))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 54, height: 54)

                    Text(site.domain.isEmpty ? site.source.rawValue : site.domain)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SeekTheme.steelSapphire)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3.5)
                        .background(SeekTheme.steelSapphire.opacity(0.14))
                        .clipShape(Capsule())
                }
                .padding(12)
            }
            .frame(height: 140)

            VStack(alignment: .leading, spacing: 4) {
                Text(site.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(site.url.absoluteString)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.58))
                    .lineLimit(3)
                    .truncationMode(.middle)
            }

            Rectangle().fill(SeekTheme.dividerStroke).frame(height: 1)

            VStack(spacing: 5) {
                metaRow("Browser", site.source.rawValue)
                if let prof = site.profileDisplayName, !prof.isEmpty {
                    metaRow("Profile", prof)
                }
                metaRow("Type", site.isBookmark ? "Bookmark" : "Top Visited Site")
                if let folder = site.folderPath, !folder.isEmpty {
                    metaRow("Folder", folder)
                }
                if site.visitCount > 0 {
                    metaRow("Visits", "\(site.visitCount)")
                }
                if site.lastVisited != .distantPast {
                    metaRow("Last Visited", Self.dateFormatter.string(from: site.lastVisited))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Button(action: { onOpenWeb(site, false) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(site.openButtonLabel)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                        Text("⏎")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 31)
                    .background(SeekTheme.steelSapphire.opacity(0.32))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(SeekTheme.steelSapphire.opacity(0.75), lineWidth: 0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    inspectorMiniButton("globe", "Default", "⌘O") { onOpenWeb(site, true) }
                    inspectorMiniButton("link", "Copy URL", "⌘⇧C") { onCopyWebURL(site) }
                }
            }
        }
    }

    @ViewBuilder
    private func siteSearchInspector(_ action: SiteSearchAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(SeekTheme.steelSapphire.opacity(0.16))
                    .frame(width: 60, height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(SeekTheme.steelSapphire.opacity(0.45), lineWidth: 1))
                Image(systemName: action.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(SeekTheme.steelSapphire)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("DIRECT SITE SEARCH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(SeekTheme.steelSapphire)
                Text("Search \(action.siteName)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Query: \"\(action.query)\"")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.78))
                Text(action.targetURL.absoluteString)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.52))
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: { onOpenSiteSearch(action) }) {
                HStack {
                    Text("Search on \(action.siteName)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("⏎").font(.system(size: 10.5, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(SeekTheme.steelSapphire.opacity(0.32))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SeekTheme.steelSapphire.opacity(0.75), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Color(white: 0.50))
            Spacer()
            Text(value).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Color(white: 0.82)).lineLimit(1)
        }
    }

    @ViewBuilder
    private func inspectorMiniButton(_ icon: String, _ label: String, _ helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                Text(label).font(.system(size: 8.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color(white: 0.86))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color.white.opacity(0.065))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.11), lineWidth: 0.7))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("\(label) (\(helpText))")
    }
}
