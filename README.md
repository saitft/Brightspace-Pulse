# Brightspace Pulse (BrightspaceSync)

A native, high-performance macOS academic hub and menu bar utility (macOS 14+ Sonoma / macOS 15+ Sequoia / macOS 26+ Tahoe) built with **SwiftUI** and **AppKit** that brings your entire **Brightspace (D2L)** experience directly to your desktop.

Brightspace Pulse synchronizes upcoming assignments, quizzes, exams, released grades, lecture slides, lab manuals, and class announcements into structured local folders, and mirrors assets into a **Google Drive / NotebookLM** source directory.

---

## Key Features

- **Native macOS Liquid Glass Desktop Hub:**
  - Designed with `NSVisualEffectView` (`.behindWindow` / `.popover` materials), SwiftUI `.ultraThinMaterial`, `1px` luminous specular borders, and soft ambient drop shadows.
  - **Upcoming & Exams:** Real-time countdowns for all pending assignments, quizzes, and exams with 48-hour crunch alerts and direct web links.
  - **Course Files Browser:** Instant search and indexing across 290+ downloaded PDFs, slides, and lab code with one-click Open or Reveal in Finder.
  - **Grades & Standing Dashboard:** Categorized grade tables, weighted averages, letter grades (`A+` to `F`), and visual progress indicators.
  - Operates on-demand when launched (syncs automatically and quits cleanly with `0%` idle background CPU/RAM) alongside a live menu bar status popover.
- **Zero-Config Brightspace Course Discovery:**
  - Integrated `WKWebView` Single Sign-On (SSO) sheet captures `d2lSessionVal` and `d2lSecureSessionVal` automatically with silent cookie refresh.
  - Queries `/d2l/api/lp/1.43/enrollments/myenrollments/` to auto-discover all active course offerings (`orgUnitId`, course code, and title).
- **Valence REST Engine & SHA-256 Deduplication:**
  - Traverses `/content/toc`, `/news/`, `/dropbox/folders/`, paginated `/quizzes/`, `/calendar/events/`, and `/grades/values/myGradeValues/`.
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
├── run_tests.sh
├── notebook_ingest.sh
├── Sources/
│   ├── BrightspaceSync/
│   │   └── AppMain.swift               # App entry point, Desktop Workspace, MenuBarExtra & SSO Sheet
│   └── BrightspaceSyncCore/
│       ├── AppViewModel.swift          # Main-actor observable coordinator & academic helpers
│       ├── BrightspaceSyncEngine.swift # Valence REST polling actor, auth verification & state cache
│       ├── GlassComponents.swift       # Liquid Glass modifiers, status badges & visual styling
│       └── LocalFileManager.swift      # File downloads, SHA-256 hashing & local folder scanner
└── Tests/
    └── BrightspaceSyncTests/
        └── main.swift                  # Comprehensive unit & integration test runner (7 test suites)
```

---

## Quick Start & Build Instructions

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode Command Line Tools (`xcode-select --install`, Swift 5.10 / Swift 6+)

### Run Test Suite
```bash
./run_tests.sh
# or
swift run BrightspaceSyncTests
```

### Build & Package `.app` Bundle
```bash
chmod +x bundle_app.sh run_tests.sh
./bundle_app.sh
open BrightspaceSync.app
```

---

## Security & Privacy
- **Local-Only Credentials:** Session tokens are stored strictly on your Mac (`Keychain` / `0600`-permissioned Application Support storage) and are never transmitted to any third-party server.
- **Sandboxed Folder Access:** Uses macOS Security-Scoped Bookmarks (`URL.bookmarkData(options: [.withSecurityScope])`) for persistent folder permissions.

---

## License
Released under the [MIT License](LICENSE). Created by **saitft**.
