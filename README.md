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

## Quick Start & Installation

### Option A: Direct Download (Pre-built macOS App)
1. **Download the latest release:**
   Head to [**Releases**](https://github.com/saitft/Brightspace-Pulse/releases) and download `Brightspace-Pulse-v1.0.0-macOS.zip`.
2. **Install:**
   Double-click to unzip, then drag `Brightspace Pulse.app` into your `/Applications` folder.
3. **First Launch (macOS Gatekeeper Bypass):**
   Because this open-source build is ad-hoc signed and not notarized through an Apple Developer Team account:
   - **Via Finder:** Right-click (or Control-click) `Brightspace Pulse.app` in `/Applications` > click **Open** > click **Open** in the dialog. (You only need to do this once).
   - **Or via Terminal:**
     ```bash
     xattr -cr "/Applications/Brightspace Pulse.app"
     ```

---

### Option B: Build From Source (Developers)
```bash
# 1. Clone repository
git clone https://github.com/saitft/Brightspace-Pulse.git
cd Brightspace-Pulse

# 2. Run unit & integration test suite (108 assertions)
./run_tests.sh

# 3. Compile native Universal binary & package .app bundle with Liquid Glass AppIcon
./bundle_app.sh

# 4. Launch the application
open "Brightspace Pulse.app"
```

---

## Connecting Your University (Any D2L / Brightspace Institution)

Brightspace Pulse works out of the box with **any university or college** powered by D2L Brightspace:

1. Click **Sign In with Brightspace** (or open the SSO Sheet).
2. Choose your school from the built-in presets:
   - **uOttawa** (`https://uottawa.brightspace.com`)
   - **Carleton** (`https://brightspace.carleton.ca`)
   - **Waterloo** (`https://learn.uwaterloo.ca`)
   - **TMU** (`https://my.torontomu.ca`)
   - **Calgary** (`https://d2l.ucalgary.ca`)
   - *...or type your custom portal URL into the address bar and click **Load**.*
3. Log in with your standard university Single Sign-On (SSO / Microsoft 365 / Duo 2FA / Okta).
4. **Zero Configuration:** Brightspace Pulse automatically intercepts your session credentials securely into your macOS Keychain, queries the D2L Valence REST API to discover all enrolled courses, and populates:
   - **Upcoming Assignments & Exam countdowns** (with 48-hour crunch alerts)
   - **Course Files & Lecture Slides** (instant search & indexing)
   - **Grades & Standing** (automatic uOttawa 10.0 CGPA & North American 4.0 GPA calculations)


---

## Security & Privacy
- **Local-Only Credentials:** Session tokens are stored strictly on your Mac (`Keychain` / `0600`-permissioned Application Support storage) and are never transmitted to any third-party server.
- **Sandboxed Folder Access:** Uses macOS Security-Scoped Bookmarks (`URL.bookmarkData(options: [.withSecurityScope])`) for persistent folder permissions.

---

## License
Released under the [MIT License](LICENSE). Created by **saitft**.
