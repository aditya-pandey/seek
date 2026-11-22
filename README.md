<p align="left">
  <img src="Assets/LogoKit/app-icon-512.png" width="88" alt="Seek — Aperture Lock App Icon" />
</p>

# Seek

A zero-lag, native macOS file, app, content & command launcher built in pure **Swift, SwiftUI, AppKit, CoreServices (`MDQuery`), and QuickLookThumbnailing**.

Press **`⌥ F`** (configurable to `⌥ Space` or `⌘⇧Space` in the menu bar) to summon a sleek **frosted native vibrancy** search bar that expands smoothly downward into a two-pane results & live preview palette as you type.

---

## Why Seek Feels Instant & Intuitive

- **Hybrid Sub-Millisecond Search Engine:** Combines a Breadth-First (BFS) in-memory cache (`< 1 ms`) with **native in-process Spotlight (`CoreServices.MDQuery`)** sorted inside the kernel by `Last Used` and `Modified Date`—zero subprocess spawning, zero per-result `stat()` delays.
- **Searches Everywhere You Work:** Covers Applications, Desktop, Downloads, Documents, **iCloud Drive**, Pictures, Movies, Music, Developer/Projects, and custom `~/` folders—while filtering out `node_modules`, `.git`, `.build`, `DerivedData`, `Pods`, and `Library/Caches`.
- **Understands Human Queries:**
  - **CamelCase & Acronym Initials:** `ssm` → `SeekSearchManager.swift`, `vsc` → `Visual Studio Code`
  - **Typo Tolerance:** `chorme` → `Google Chrome`, `invoce` → `Invoice_2026.pdf`
  - **Normalized Matching:** `weaponwheel` → `Weapon_Wheel_PRD.md`
  - **Browser Bookmarks & Top Visited Sites (`⌘ 7` / `in:web` / `in:bookmarks`):** Searches bookmarks and frequently visited websites across **Chrome, Brave, Arc, Edge, Vivaldi, Firefox, and Safari** without ever locking running browsers.
  - **Direct In-Site Search:** Type `gmail invoice`, `drive budget`, `gh seek`, `yt swiftui`, or `g macos` to search straight inside your favorite web apps.
  - **Natural Scopes & Types:** `in:downloads invoice pdf`, `in:icloud budget excel`, `in:bookmarks figma`, `.pptx`, `~/Documents/` (with `Tab` folder autocomplete!)
  - **Full-Text Content Search:** `content:quarterly` (or automatic fallback when filename matches are sparse, marked `IN CONTENT`)
  - **Inline Math, Units & Commands:** `18% of 2400`, `1440 px to rem`, `450 usd to inr`, `now`, `dark mode`, `caffeinate`, `copy ip`, `clean url`
  - **Persistent Frecency Learning:** Remembers the apps and files you open for your favorite queries.
- **Live Two-Pane Inspector:** Instant async QuickLook thumbnails (PDFs, images, Keynote/PowerPoint/Word/Excel), 18-line code & markdown excerpts, and folder contents peeking.

---

## Shortcuts

| Shortcut | Action |
|---|---|
| **`⌥ F`** | Toggle Seek (configurable in Menu Bar → Global Shortcut) |
| **`↓` / `↑`** | Expand Recents / navigate results |
| **`Tab` / `⇧ Tab`** | Cycle category filters (`All`, `Apps`, `Docs & PDF`, `Folders`, `Media`, `Code`, `Web`) or autocomplete folder path in `~/` mode |
| **`⌘ 1` – `⌘ 7`** | Jump straight to a category filter (`⌘ 7` for Browser Bookmarks & Top Sites) |
| **`⏎`** | Open file / launch app / run command / copy calculation |
| **`⌘ ⏎`** | Reveal in Finder |
| **`⌘ O`** | Open in Cursor / VS Code / Zed |
| **`⌘ Y`** | Full-screen QuickLook preview |
| **`⌘ ⇧ C`** | Copy file & path to clipboard |
| **`⌘ ⌫`** | Clear search & collapse to compact bar |

---

## Download & Install (No Xcode Required)

Download the pre-built **Universal app** (`Apple Silicon + Intel`, macOS 14.0+) from **[GitHub Releases](https://github.com/aditya-pandey/seek/releases/latest)**:

1. Open **`Seek-macOS-Universal.dmg`** and drag **`Seek.app`** into **`Applications`**.
2. Open **Seek** once. If macOS Sequoia Gatekeeper prompts because personal builds aren't Apple-notarized:
   - Click **Done** → open **System Settings → Privacy & Security → Open Anyway**, **or** run:
     ```bash
     xattr -cr /Applications/Seek.app && open /Applications/Seek.app
     ```
3. Toggle **Launch at Login** from the Seek menu bar icon.

---

## Build From Source

```bash
git clone https://github.com/aditya-pandey/seek.git
cd seek
chmod +x build_app.sh
./build_app.sh
open /Applications/Seek.app
```

---

## Companion Apps (Pick & Choose)

- **[Glance](https://github.com/aditya-pandey/glance)** — Visual `⌥ Tab` live window & browser tab switcher + Dock hover previews
- **[WeaponWheel](https://github.com/aditya-pandey/weapon-wheel)** — `⌥ Space` radial quick-action wheel (Clipboard, OCR, Window Snapping, Notes, Calculator, Media/Volume)
- **[FileWheel](https://github.com/aditya-pandey/file-wheel)** — Drag-and-drop radial file converter (PNG/JPG/WebP/PDF/AI Background Cutout)
