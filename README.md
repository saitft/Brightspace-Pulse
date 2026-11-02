# Brightspace Pulse (BrightspaceSync)

A native, lightweight macOS utility (macOS 14+ Sonoma / macOS 15+ Sequoia / macOS 26+ Tahoe) built with **SwiftUI** and **AppKit** that automatically discovers your enrolled **Brightspace (D2L)** courses, downloads new lecture slides, lab manuals, and class announcements into structured local folders, and mirrors them into a **Google Drive / NotebookLM** source directory.

---

## Key Features

- **Liquid Glass Native macOS Design:**
  - Built with `NSVisualEffectView` (`.behindWindow` / `.popover` materials) and SwiftUI `.ultraThinMaterial`, `1px` specular refraction borders, and ambient shadows.
  - Operates on-demand when launched (auto-syncs on open and terminates cleanly on window close with `0%` idle background CPU/RAM) alongside a live menu bar status item.
- **Zero-Config Brightspace Course Discovery:**
  - Integrated `WKWebView` Single Sign-On (SSO) sheet captures `d2lSessionVal` and `d2lSecureSessionVal` automatically.
  - Queries `/d2l/api/lp/1.43/enrollments/myenrollments/` to auto-discover all active course offerings (`orgUnitId`, course code, and title).
- **Recursive Content & Announcement Sync + SHA-256 Deduplication:**
  - Traverses `/d2l/api/le/{version}/{orgUnitId}/content/toc`, `/content/root/`, and `/news/` across Valence API versions (`1.67` → `1.60` → `1.51` → `1.43`).
  - Streams files directly to `<TargetFolder>/<CourseCode>/<ModuleName>/<FileName>` using `URLSession` and verifies `CryptoKit.SHA256` digests against a persistent local cache (`state.json`) to eliminate redundant downloads.
- **NotebookLM & Google Drive Ingestion Pipeline:**
  - **Route A (Local Drive Mirror):** Automatically copies verified course assets into `<DriveMirror>/<CourseCode>_Notebook/` and maintains a Markdown index (`00_<CourseCode>_NotebookLM_Index.md`) for instant `@Google Drive` Gemini queries or one-step NotebookLM uploads.
  - **Route B (Custom IPC / CLI Hook):** Optional shell hook triggered after each verified download with `$BRIGHTSPACE_FILE_PATH`, `$BRIGHTSPACE_COURSE_CODE`, `$BRIGHTSPACE_MODULE_NAME`, and `$BRIGHTSPACE_FILE_SHA256`.

---

## Architecture

```
BrightspaceSync/
├── Package.swift
├── bundle_app.sh
├── notebook_ingest.sh
└── Sources/BrightspaceSync/
    ├── AppMain.swift               # App entry point, on-demand window, MenuBarExtra, Settings & WKWebView SSO
    ├── GlassComponents.swift       # Reusable Liquid Glass cards, vibrancy wrappers, and glow status badges
    ├── BrightspaceSyncEngine.swift # Swift Actor for Valence REST polling, course discovery, and SHA-256 state cache
    └── LocalFileManager.swift      # Security-scoped bookmarks, streaming SHA-256 downloader, and NotebookLM mirror
```

---

## Quick Start & Build Instructions

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode Command Line Tools (`xcode-select --install`, Swift 5.10 / Swift 6+)

### Build & Package `.app` Bundle
```bash
git clone https://github.com/saitft/Brightspace-Pulse.git
cd Brightspace-Pulse
chmod +x bundle_app.sh
./bundle_app.sh
open BrightspaceSync.app
```

### Usage
1. Launch **`Brightspace Pulse.app`**.
3. Click the **Gear icon (`⚙️`)** → **Sign In via WebView** and log in to your university's Brightspace instance (e.g. `https://brightspace.example.edu`).
4. Your enrolled courses are discovered automatically and synced into your chosen root folder and NotebookLM mirror folder.

---

## Security & Privacy
- **Local-Only Credentials:** Session tokens are stored strictly on your Mac (`Keychain` / `0600`-permissioned Application Support storage) and are never transmitted to any third-party server.
- **Sandboxed Folder Access:** Uses macOS Security-Scoped Bookmarks (`URL.bookmarkData(options: [.withSecurityScope])`) for persistent folder permissions.

---

## License
Released under the [MIT License](LICENSE). Created by **saitft**.
