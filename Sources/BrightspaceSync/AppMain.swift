import SwiftUI
import AppKit
import WebKit

// MARK: - Main-Actor Observable Coordinator

@MainActor
public final class AppViewModel: ObservableObject {
    public static let shared = AppViewModel()

    @Published public var syncState: SyncVisualState = .synced
    @Published public var activities: [SyncActivityItem] = []
    @Published public var selectedCourseFilter: String = "ALL"
    @Published public var lastSyncDate: Date? = nil

    // Persisted User Settings
    @Published public var brightspaceURL: String {
        didSet { UserDefaults.standard.set(brightspaceURL, forKey: "BrightspaceSync.BaseURL") }
    }
    @Published public var pollingIntervalMinutes: Double {
        didSet {
            UserDefaults.standard.set(pollingIntervalMinutes, forKey: "BrightspaceSync.PollMinutes")
            rescheduleBackgroundSync()
        }
    }
    @Published public var enableDriveMirror: Bool {
        didSet { UserDefaults.standard.set(enableDriveMirror, forKey: "BrightspaceSync.EnableDriveMirror") }
    }
    @Published public var directAutomationCommand: String {
        didSet { UserDefaults.standard.set(directAutomationCommand, forKey: "BrightspaceSync.DirectCommand") }
    }
    @Published public var rootDirectoryPath: String = ""
    @Published public var driveMirrorPath: String = ""
    @Published public var courses: [CourseMapping] = [] {
        didSet { saveCourses() }
    }

    // Session Cookie Inputs (Backed by macOS Keychain)
    @Published public var d2lSessionVal: String = ""
    @Published public var d2lSecureSessionVal: String = ""
    @Published public var isWebLoginSheetPresented: Bool = false
    @Published public var autoCloseAfterSync: Bool {
        didSet { UserDefaults.standard.set(autoCloseAfterSync, forKey: "BrightspaceSync.AutoCloseAfterSync") }
    }

    private let engine = BrightspaceSyncEngine()
    private let coursesStorageKey = "BrightspaceSync.CoursesList"
    private var warmupWebView: WKWebView?

    public init() {
        self.brightspaceURL = UserDefaults.standard.string(forKey: "BrightspaceSync.BaseURL")
            ?? "https://brightspace.example.edu"
        let savedPoll = UserDefaults.standard.double(forKey: "BrightspaceSync.PollMinutes")
        self.pollingIntervalMinutes = savedPoll > 0 ? savedPoll : 30.0
        self.enableDriveMirror = UserDefaults.standard.object(forKey: "BrightspaceSync.EnableDriveMirror") as? Bool ?? true
        let savedCmd = UserDefaults.standard.string(forKey: "BrightspaceSync.DirectCommand") ?? ""
        self.directAutomationCommand = savedCmd.contains("notebook_ingest.sh") ? "" : savedCmd
        self.autoCloseAfterSync = UserDefaults.standard.object(forKey: "BrightspaceSync.AutoCloseAfterSync") as? Bool ?? false

        self.rootDirectoryPath = LocalFileManager.shared.resolveRootDirectoryURL().path(percentEncoded: false)
        self.driveMirrorPath = LocalFileManager.shared.resolveDriveMirrorDirectoryURL()?.path(percentEncoded: false) ?? ""

        if let data = UserDefaults.standard.data(forKey: coursesStorageKey),
           let decoded = try? JSONDecoder().decode([CourseMapping].self, from: data),
           !decoded.isEmpty {
            self.courses = decoded
        } else {
            self.courses = [
                CourseMapping(
                    orgUnitId: "100101",
                    courseCode: "CS101",
                    courseTitle: "Introduction to Computer Science",
                    customSubfolder: "CS101",
                    notebookWorkspaceID: "nb-cs101"
                ),
                CourseMapping(
                    orgUnitId: "100102",
                    courseCode: "MATH101",
                    courseTitle: "Calculus I",
                    customSubfolder: "MATH101",
                    notebookWorkspaceID: "nb-math101"
                ),
                CourseMapping(
                    orgUnitId: "100103",
                    courseCode: "PHYS101",
                    courseTitle: "Fundamentals of Physics I",
                    customSubfolder: "PHYS101",
                    notebookWorkspaceID: "nb-phys101"
                ),
                CourseMapping(
                    orgUnitId: "100104",
                    courseCode: "CHEM101",
                    courseTitle: "Principles of Chemistry",
                    customSubfolder: "CHEM101",
                    notebookWorkspaceID: "nb-chem101"
                )
            ]
        }

        Task { @MainActor in
            let persisted = await engine.currentState()
            self.lastSyncDate = persisted.lastSuccessfulSync
            if persisted.recentActivity.isEmpty {
                self.activities = Self.defaultSeedActivities(rootPath: self.rootDirectoryPath)
            } else {
                self.activities = persisted.recentActivity
            }

            // No background daemon polling: only sync on-demand when app is opened
            await engine.stopSchedule()
            self.triggerManualSync()
        }
    }

    private func purgeStaleD2LCookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies where cookie.name == "d2lSessionVal" || cookie.name == "d2lSecureSessionVal" {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.delete(cookie) { continuation.resume() }
            }
        }
    }

    private func hydrateFromWebKitCookieStore(purgeExistingD2L: Bool = false) async -> (s1: String, s2: String, fullCookie: String)? {
        if purgeExistingD2L {
            await purgeStaleD2LCookies()
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 10, height: 10), configuration: config)
        self.warmupWebView = wv
        defer { self.warmupWebView = nil }

        let targetURLString = brightspaceURL.hasSuffix("/") ? "\(brightspaceURL)d2l/home" : "\(brightspaceURL)/d2l/home"
        if let url = URL(string: targetURLString) {
            wv.load(URLRequest(url: url))
        }
        try? await Task.sleep(for: .milliseconds(3500))

        let finalPath = wv.url?.path.lowercased() ?? ""
        if finalPath.contains("login") {
            return nil
        }

        return await withCheckedContinuation { continuation in
            wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                var s1: String?
                var s2: String?
                var pairs: [String] = []
                for cookie in cookies where cookie.domain.localizedCaseInsensitiveContains("brightspace") {
                    pairs.append("\(cookie.name)=\(cookie.value)")
                    if cookie.name == "d2lSessionVal" && !cookie.value.isEmpty {
                        s1 = cookie.value
                    } else if cookie.name == "d2lSecureSessionVal" && !cookie.value.isEmpty {
                        s2 = cookie.value
                    }
                }
                if let v1 = s1, let v2 = s2 {
                    continuation.resume(returning: (v1, v2, pairs.joined(separator: "; ")))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public var filteredActivities: [SyncActivityItem] {
        if selectedCourseFilter == "ALL" {
            return activities
        }
        return activities.filter { $0.courseCode == selectedCourseFilter }
    }

    public func saveCredentialsToKeychain(fullCookieHeader: String? = nil, csrfToken: String? = nil) {
        let s1 = d2lSessionVal
        let s2 = d2lSecureSessionVal
        Task {
            await engine.saveCredentials(
                d2lSessionVal: s1,
                d2lSecureSessionVal: s2,
                fullCookieHeader: fullCookieHeader,
                csrfToken: csrfToken
            )
            if !s1.isEmpty && !s2.isEmpty {
                if syncState == .authRequired {
                    syncState = .synced
                }
                await autoDiscoverCoursesInternal()
                triggerManualSync()
            }
        }
    }

    public func autoDiscoverCourses() {
        Task {
            await autoDiscoverCoursesInternal()
        }
    }

    private func autoDiscoverCoursesInternal() async {
        syncState = .checkingBrightspace
        let discovered = await engine.discoverEnrolledCourses(baseURLString: brightspaceURL)
        if !discovered.isEmpty {
            self.courses = discovered
        }
        syncState = .synced
    }

    public func triggerManualSync() {
        Task { @MainActor in
            syncState = .checkingBrightspace
            var creds = await engine.loadCredentials()
            var isSessionAlive = false

            if !creds.sessionVal.isEmpty && !creds.secureSessionVal.isEmpty {
                isSessionAlive = await engine.validateSession(baseURLString: brightspaceURL)
            }

            // If stored session expired or missing, try silent SSO refresh via WebKit cookie store
            if !isSessionAlive {
                if let recovered = await self.hydrateFromWebKitCookieStore(purgeExistingD2L: true) {
                    await engine.saveCredentials(
                        d2lSessionVal: recovered.s1,
                        d2lSecureSessionVal: recovered.s2,
                        fullCookieHeader: recovered.fullCookie
                    )
                    creds = (recovered.s1, recovered.s2)
                    isSessionAlive = await engine.validateSession(baseURLString: brightspaceURL)
                }
            }

            self.d2lSessionVal = isSessionAlive ? creds.sessionVal : ""
            self.d2lSecureSessionVal = isSessionAlive ? creds.secureSessionVal : ""

            guard isSessionAlive else {
                await engine.clearCredentials()
                self.syncState = .authRequired
                self.isWebLoginSheetPresented = true
                return
            }

            let updated = await engine.pollCourses(
                baseURLString: brightspaceURL,
                courses: courses,
                enableDriveMirror: enableDriveMirror,
                directAutomationCommand: directAutomationCommand
            ) { [weak self] newState in
                self?.syncState = newState
            }
            self.activities = updated
            if self.syncState == .synced {
                self.lastSyncDate = Date()
                if self.autoCloseAfterSync {
                    try? await Task.sleep(for: .milliseconds(1600))
                    NSApp.terminate(nil)
                }
            } else if self.syncState == .authRequired {
                self.isWebLoginSheetPresented = true
            }
        }
    }

    public func rescheduleBackgroundSync() {
        Task {
            await engine.stopSchedule()
        }
    }

    public func chooseRootFolderViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Course Downloads Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            _ = try? LocalFileManager.shared.saveSecurityScopedBookmark(for: url, isDriveMirror: false)
            rootDirectoryPath = url.path(percentEncoded: false)
        }
    }

    public func chooseDriveMirrorViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Google Drive / NotebookLM Mirror Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            _ = try? LocalFileManager.shared.saveSecurityScopedBookmark(for: url, isDriveMirror: true)
            driveMirrorPath = url.path(percentEncoded: false)
        }
    }

    private func saveCourses() {
        if let encoded = try? JSONEncoder().encode(courses) {
            UserDefaults.standard.set(encoded, forKey: coursesStorageKey)
        }
    }

    private static func defaultSeedActivities(rootPath: String) -> [SyncActivityItem] {
        let now = Date()
        return [
            SyncActivityItem(
                courseCode: "PHYS101",
                moduleName: "Lectures",
                fileName: "Lecture 4 - Rotational Dynamics.pdf",
                kind: .lectureSlide,
                downloadedAt: now.addingTimeInterval(-180),
                localFilePath: "\(rootPath)/PHYS101/Lectures/Lecture 4 - Rotational Dynamics.pdf",
                sha256Short: "9f4b2c1a",
                syncedToNotebook: true,
                notebookRouteLabel: "Synced to Notebook"
            ),
            SyncActivityItem(
                courseCode: "CS101",
                moduleName: "Labs",
                fileName: "Lab5_Pointers_And_Structs.pdf",
                kind: .document,
                downloadedAt: now.addingTimeInterval(-1620),
                localFilePath: "\(rootPath)/CS101/Labs/Lab5_Pointers_And_Structs.pdf",
                sha256Short: "3a81e70d",
                syncedToNotebook: true,
                notebookRouteLabel: "Synced to Notebook"
            ),
            SyncActivityItem(
                courseCode: "MATH101",
                moduleName: "Announcements",
                fileName: "Announcement - Midterm Practice Solutions Posted.md",
                kind: .announcement,
                downloadedAt: now.addingTimeInterval(-5400),
                localFilePath: "\(rootPath)/MATH101/Announcements/Announcement - Midterm Practice Solutions Posted.md",
                sha256Short: "c7d04e19",
                syncedToNotebook: true,
                notebookRouteLabel: "Synced to Notebook"
            )
        ]
    }
}

// MARK: - App Delegate (Quit Completely When Window Closed — No Background Daemon)

public final class BrightspaceAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - App Entry Point (On-Demand Window + MenuBarExtra + Settings Scene)

@main
public struct BrightspaceSyncApp: App {
    @NSApplicationDelegateAdaptor(BrightspaceAppDelegate.self) private var appDelegate
    @ObservedObject private var viewModel = AppViewModel.shared
    @Environment(\.openWindow) private var openWindow

    public init() {
        DispatchQueue.main.async {
            _ = AppViewModel.shared
        }
    }

    public var body: some Scene {
        WindowGroup("Brightspace Pulse") {
            Group {
                if viewModel.isWebLoginSheetPresented {
                    BrightspaceWebAuthSheet(
                        baseURLString: viewModel.brightspaceURL,
                        onCookiesCaptured: { s1, s2, fullCookie, csrf in
                            viewModel.d2lSessionVal = s1
                            viewModel.d2lSecureSessionVal = s2
                            viewModel.saveCredentialsToKeychain(fullCookieHeader: fullCookie, csrfToken: csrf)
                            viewModel.isWebLoginSheetPresented = false
                        },
                        onCancel: {
                            viewModel.isWebLoginSheetPresented = false
                        }
                    )
                    .frame(width: 620, height: 520)
                } else {
                    StatusPopoverView(
                        viewModel: viewModel,
                        onOpenSettings: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "settings-window")
                        }
                    )
                    .frame(width: 430)
                }
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            StatusPopoverView(
                viewModel: viewModel,
                onOpenSettings: {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings-window")
                }
            )
        } label: {
            HStack(spacing: 4) {
                Image(
                    systemName: viewModel.syncState.isBusy
                        ? "arrow.triangle.2.circlepath.circle.fill"
                        : "sparkles.rectangle.stack"
                )
                .symbolRenderingMode(.monochrome)
                .symbolEffect(.pulse, isActive: viewModel.syncState.isBusy)
            }
        }
        .menuBarExtraStyle(.window)

        Window("Brightspace Sync Preferences", id: "settings-window") {
            SettingsWindowView(viewModel: viewModel)
                .frame(minWidth: 620, idealWidth: 640, minHeight: 470, idealHeight: 500)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - 1. Status Popover (Quick View)

public struct StatusPopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    var onOpenSettings: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.28), Color.blue.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        )

                    Image(systemName: viewModel.syncState.isBusy ? "arrow.triangle.2.circlepath" : "sparkles.rectangle.stack.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Brightspace Pulse")
                        .font(.system(size: 13.5, weight: .bold, design: .default))
                        .foregroundStyle(.primary)

                    Text(lastSyncSubtitle)
                        .font(.system(size: 10.5, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                GlowStatusBadge(state: viewModel.syncState)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Course Filter Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(
                        title: "All Courses",
                        isSelected: viewModel.selectedCourseFilter == "ALL"
                    ) {
                        viewModel.selectedCourseFilter = "ALL"
                    }

                    ForEach(viewModel.courses.filter(\.isEnabled)) { course in
                        FilterChip(
                            title: course.courseCode,
                            isSelected: viewModel.selectedCourseFilter == course.courseCode
                        ) {
                            viewModel.selectedCourseFilter = course.courseCode
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            Divider()
                .opacity(0.4)

            if viewModel.syncState == .authRequired {
                HStack(spacing: 10) {
                    Image(systemName: "key.radiowaves.forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Brightspace Session Expired")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Sign in via SSO to refresh your session and sync new course files.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign In") {
                        viewModel.isWebLoginSheetPresented = true
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: true))
                }
                .liquidGlassCard(cornerRadius: 10, padding: 10, isInteractive: false)
                .padding(.horizontal, 14)
            }

            // Activity Feed
            if viewModel.filteredActivities.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No recent course assets in this filter.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Click Sync Now below to poll Brightspace and ingest into NotebookLM.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .padding(.horizontal, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredActivities) { item in
                            ActivityFeedCard(item: item) {
                                LocalFileManager.shared.revealInFinder(
                                    url: URL(fileURLWithPath: item.localFilePath)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 270)
            }

            Divider()
                .opacity(0.4)

            // Footer Bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        LocalFileManager.shared.openRootStorageFolder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Course Folder")
                        }
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                    .help("Open root course download folder in Finder")

                    Spacer()

                    Button {
                        viewModel.triggerManualSync()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text(viewModel.syncState.isBusy ? "Syncing..." : "Sync Now")
                        }
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: true))
                    .disabled(viewModel.syncState.isBusy)

                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.vertical, 1)
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                    .help("Open Brightspace & NotebookLM Settings")

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.vertical, 1)
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                    .help("Quit Brightspace Pulse completely (0% background usage)")
                }

                HStack {
                    Toggle("Auto-quit app after sync completes", isOn: $viewModel.autoCloseAfterSync)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("No background daemon")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 430)
        .liquidGlassContainer(cornerRadius: 16)
    }

    private var lastSyncSubtitle: String {
        guard let date = viewModel.lastSyncDate else {
            return "On-Demand Mode • Syncs automatically on open"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Synced \(formatter.localizedString(for: date, relativeTo: Date())) • On-Demand Mode"
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityFeedCard: View {
    let item: SyncActivityItem
    let onReveal: () -> Void

    private var iconName: String {
        switch item.kind {
        case .lectureSlide:
            return "doc.richtext.fill"
        case .document:
            return "doc.text.fill"
        case .announcement:
            return "megaphone.fill"
        }
    }

    private var accentColor: Color {
        switch item.courseCode {
        case "PHYS101": return .cyan
        case "CS101": return .blue
        case "MATH101": return .purple
        case "CHEM101": return .mint
        default: return .indigo
        }
    }

    private var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.downloadedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 30, height: 30)

                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    CourseTagBadge(courseCode: item.courseCode, accent: accentColor)

                    Text(item.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 2)
                }

                HStack(spacing: 5) {
                    Text("Downloaded \(relativeTimeString)")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.secondary)

                    Text("→")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 3) {
                        Image(systemName: item.syncedToNotebook ? "sparkles" : "internaldrive")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(item.notebookRouteLabel)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(item.syncedToNotebook ? Color.purple : Color.secondary)

                    Spacer()

                    Text("#\(item.sha256Short)")
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Button(action: onReveal) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal \(item.fileName) in Finder")
        }
        .liquidGlassCard(cornerRadius: 11, padding: 10, isInteractive: true)
    }
}

// MARK: - 2. Settings Window (Glass Sheet / Tabbed)

public struct SettingsWindowView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: SettingsTab = .account
    @State private var newCourseOrgId: String = ""
    @State private var newCourseCode: String = ""
    @State private var newCourseTitle: String = ""
    @State private var newCourseNotebookId: String = ""

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case account = "Account & Auth"
        case folders = "Folder Mapping"
        case schedule = "Sync & Notebook"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .account: return "key.radiowaves.forward.fill"
            case .folders: return "folder.fill.badge.gearshape"
            case .schedule: return "clock.arrow.2.circlepath"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Custom Glass Header & Tab Switcher
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                    Text("Brightspace Pulse Settings")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.rawValue)
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.22) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        selectedTab == tab ? Color.accentColor.opacity(0.45) : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .account:
                        accountTabContent
                    case .folders:
                        folderMappingTabContent
                    case .schedule:
                        scheduleAndNotebookTabContent
                    }
                }
                .padding(20)
            }
        }
        .liquidGlassContainer(cornerRadius: 16)
        .sheet(isPresented: $viewModel.isWebLoginSheetPresented) {
            BrightspaceWebAuthSheet(
                baseURLString: viewModel.brightspaceURL,
                onCookiesCaptured: { s1, s2, fullCookie, csrf in
                    viewModel.d2lSessionVal = s1
                    viewModel.d2lSecureSessionVal = s2
                    viewModel.saveCredentialsToKeychain(fullCookieHeader: fullCookie, csrfToken: csrf)
                    viewModel.isWebLoginSheetPresented = false
                },
                onCancel: {
                    viewModel.isWebLoginSheetPresented = false
                }
            )
            .frame(width: 620, height: 520)
        }
    }

    // MARK: - Tab 1: Account & Auth

    private var accountTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Brightspace Instance & Valence Endpoint")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                TextField("https://brightspace.example.edu", text: $viewModel.brightspaceURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Text("Queries `/d2l/api/le/1.67/{orgUnitId}/content/root/` and `/news/` using Keychain session cookies.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("D2L Session Cookies (macOS Keychain)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Sign in via integrated WebView SSO or paste `d2lSessionVal` & `d2lSecureSessionVal` directly.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.isWebLoginSheetPresented = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "safari.fill")
                            Text("Sign In via WebView")
                        }
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: true))
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("d2lSessionVal")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        SecureField("Paste d2lSessionVal token", text: $viewModel.d2lSessionVal)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("d2lSecureSessionVal")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        SecureField("Paste d2lSecureSessionVal token", text: $viewModel.d2lSecureSessionVal)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Text(
                        (!viewModel.d2lSessionVal.isEmpty && !viewModel.d2lSecureSessionVal.isEmpty)
                            ? "✓ Session tokens stored in macOS Keychain"
                            : "No active tokens in Keychain (Sync Now runs local verification sample)"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        (!viewModel.d2lSessionVal.isEmpty && !viewModel.d2lSecureSessionVal.isEmpty)
                            ? Color.green
                            : Color.secondary
                    )

                    Spacer()

                    Button("Save to Keychain") {
                        viewModel.saveCredentialsToKeychain()
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                }
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)
        }
    }

    // MARK: - Tab 2: Folder Mapping

    private var folderMappingTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Root Course Archive Directory (Security-Scoped Bookmark)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(viewModel.rootDirectoryPath)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

                    Button("Choose Folder...") {
                        viewModel.chooseRootFolderViaPanel()
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                }

                Text("Assets stream to `<TargetFolder>/<CourseCode>/<ModuleName>/<FileName>` with SHA-256 deduplication.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Monitored Brightspace Courses (orgUnitId → Course Folder & Notebook ID)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        viewModel.autoDiscoverCourses()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Auto-Discover Enrolled Courses")
                        }
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                }

                ForEach($viewModel.courses) { $course in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $course.isEnabled)
                            .labelsHidden()

                        CourseTagBadge(courseCode: course.courseCode, accent: .cyan)
                            .frame(width: 72, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.courseTitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("orgUnitId: \(course.orgUnitId) • Subfolder: /\(course.customSubfolder.isEmpty ? course.courseCode : course.customSubfolder)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        TextField("Notebook ID", text: $course.notebookWorkspaceID)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 145)

                        Button {
                            viewModel.courses.removeAll { $0.orgUnitId == course.orgUnitId }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                Divider().opacity(0.3)

                HStack(spacing: 8) {
                    TextField("orgUnitId (e.g. 100105)", text: $newCourseOrgId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    TextField("Code (ENG101)", text: $newCourseCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    TextField("Course Title", text: $newCourseTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Notebook ID", text: $newCourseNotebookId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                    Button("Add") {
                        let cleanOrg = newCourseOrgId.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanCode = newCourseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard !cleanOrg.isEmpty, !cleanCode.isEmpty else { return }
                        viewModel.courses.append(
                            CourseMapping(
                                orgUnitId: cleanOrg,
                                courseCode: cleanCode,
                                courseTitle: newCourseTitle.isEmpty ? cleanCode : newCourseTitle,
                                customSubfolder: cleanCode,
                                notebookWorkspaceID: newCourseNotebookId
                            )
                        )
                        newCourseOrgId = ""
                        newCourseCode = ""
                        newCourseTitle = ""
                        newCourseNotebookId = ""
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: true))
                }
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)
        }
    }

    // MARK: - Tab 3: Sync Schedule & NotebookLM Ingestion

    private var scheduleAndNotebookTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Background Polling Interval")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Every \(Int(viewModel.pollingIntervalMinutes)) minutes")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan)
                }

                Slider(value: $viewModel.pollingIntervalMinutes, in: 15...60, step: 15)

                HStack {
                    Text("15m (Exam Crunch)")
                    Spacer()
                    Text("30m (Recommended)")
                    Spacer()
                    Text("45m")
                    Spacer()
                    Text("60m (Battery Saver)")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)

            // Route A: Google Drive Local Mirror
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $viewModel.enableDriveMirror) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route A (Recommended): Google Drive / NotebookLM Mirror Directory")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Automatically mirrors verified course files into `<DriveMirror>/<CourseCode>_Notebook/` for instant Google Drive sync.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    TextField(
                        "~/Library/CloudStorage/GoogleDrive-user@gmail.com/My Drive/NotebookLM",
                        text: $viewModel.driveMirrorPath
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit {
                        LocalFileManager.shared.setCustomDriveMirrorPath(viewModel.driveMirrorPath)
                    }

                    Button("Browse...") {
                        viewModel.chooseDriveMirrorViaPanel()
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                }
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)

            // Route B: Direct Automation / IPC Script Hook
            VStack(alignment: .leading, spacing: 8) {
                Text("Route B (Direct Automation / IPC Hook)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Optional shell command executed after each verified download. Receives `$BRIGHTSPACE_FILE_PATH`, `$BRIGHTSPACE_COURSE_CODE`, `$BRIGHTSPACE_FILE_SHA256`, and `$NOTEBOOK_WORKSPACE_ID`.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField(
                    "e.g. /usr/local/bin/notebook-ingest --course \"$BRIGHTSPACE_COURSE_CODE\" --file \"$BRIGHTSPACE_FILE_PATH\"",
                    text: $viewModel.directAutomationCommand
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))

                HStack {
                    Spacer()
                    Button("Run Live Ingestion Test Now") {
                        viewModel.triggerManualSync()
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: true))
                }
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)
        }
    }
}

// MARK: - Integrated WKWebView Brightspace Login Sheet

public struct BrightspaceWebAuthSheet: View {
    public let baseURLString: String
    public let onCookiesCaptured: (String, String, String, String?) -> Void
    public let onCancel: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Brightspace Single Sign-On")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("Sign in normally with your university SSO. Session cookies & CSRF token are captured automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
            }
            .padding(14)

            Divider()

            BrightspaceCookieWebView(
                baseURLString: baseURLString,
                onCaptured: onCookiesCaptured
            )
        }
        .liquidGlassContainer(cornerRadius: 14)
    }
}

private struct BrightspaceCookieWebView: NSViewRepresentable {
    let baseURLString: String
    let onCaptured: (String, String, String, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptured: onCaptured)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        let store = config.websiteDataStore.httpCookieStore
        let targetString = baseURLString.hasSuffix("/") ? "\(baseURLString)d2l/home" : "\(baseURLString)/d2l/home"
        store.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies where cookie.name == "d2lSessionVal" || cookie.name == "d2lSecureSessionVal" {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                if let url = URL(string: targetString) {
                    webView.load(URLRequest(url: url))
                }
            }
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCaptured: (String, String, String, String?) -> Void
        private var didCapture = false

        init(onCaptured: @escaping (String, String, String, String?) -> Void) {
            self.onCaptured = onCaptured
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let currentHost = webView.url?.host?.lowercased() ?? ""
            let currentPath = webView.url?.path.lowercased() ?? ""
            guard currentHost.contains("brightspace"), !currentPath.contains("login") else {
                return
            }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                var sessionVal: String?
                var secureSessionVal: String?
                var cookiePairs: [String] = []

                for cookie in cookies where cookie.domain.localizedCaseInsensitiveContains("brightspace") {
                    cookiePairs.append("\(cookie.name)=\(cookie.value)")
                    if cookie.name == "d2lSessionVal" && !cookie.value.isEmpty {
                        sessionVal = cookie.value
                    } else if cookie.name == "d2lSecureSessionVal" && !cookie.value.isEmpty {
                        secureSessionVal = cookie.value
                    }
                }

                if let s1 = sessionVal, let s2 = secureSessionVal, !self.didCapture {
                    self.didCapture = true
                    let fullCookie = cookiePairs.joined(separator: "; ")
                    DispatchQueue.main.async {
                        webView.evaluateJavaScript("window.localStorage.getItem('XSRF.Token')") { result, _ in
                            let csrf = result as? String
                            self.onCaptured(s1, s2, fullCookie, csrf)
                        }
                    }
                }
            }
        }
    }
}
