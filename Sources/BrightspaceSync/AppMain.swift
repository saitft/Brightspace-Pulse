import SwiftUI
import AppKit
import WebKit
import BrightspaceSyncCore


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

// MARK: - App Entry Point (Full Native macOS Desktop Workspace + MenuBarExtra)

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
                    .frame(minWidth: 720, idealWidth: 780, minHeight: 560, idealHeight: 620)
                } else {
                    BrightspaceDesktopWorkspaceView(viewModel: viewModel)
                        .frame(minWidth: 940, idealWidth: 1020, minHeight: 620, idealHeight: 680)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            StatusPopoverView(
                viewModel: viewModel,
                onOpenSettings: {
                    viewModel.selectedSection = .settings
                    NSApp.activate(ignoringOtherApps: true)
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
                .frame(minWidth: 620, idealWidth: 660, minHeight: 480, idealHeight: 520)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Native macOS Liquid Glass Desktop Workspace (Sidebar + 3 Core Hubs + Settings)

public struct BrightspaceDesktopWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel

    public var body: some View {
        HStack(spacing: 0) {
            // Left Translucent Sidebar
            workspaceSidebar
                .frame(width: 238)

            Divider()
                .opacity(0.35)

            // Right Main Workspace Content
            VStack(spacing: 0) {
                workspaceTopHeader
                Divider().opacity(0.35)

                if viewModel.syncState == .authRequired {
                    authRequiredBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                Group {
                    switch viewModel.selectedSection {
                    case .upcoming:
                        UpcomingDeadlinesView(viewModel: viewModel)
                    case .files:
                        CourseFilesBrowserView(viewModel: viewModel)
                    case .grades:
                        GradesDashboardView(viewModel: viewModel)
                    case .settings:
                        SettingsWindowView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .liquidGlassContainer(cornerRadius: 16)
    }

    // MARK: - Sidebar

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            // App Branding Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.35), Color.indigo.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        )

                    Image(systemName: viewModel.syncState.isBusy ? "arrow.triangle.2.circlepath" : "sparkles.rectangle.stack.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Brightspace Pulse")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Live Academic Hub")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)

            // Primary Navigation Sections
            VStack(alignment: .leading, spacing: 4) {
                Text("WORKSPACE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)

                ForEach(WorkspaceSection.allCases) { section in
                    SidebarNavRow(
                        title: section.rawValue,
                        icon: section.icon,
                        badge: badgeText(for: section),
                        badgeColor: section == .upcoming && !viewModel.urgentDeadlinesWithin48Hours.isEmpty ? .orange : .cyan,
                        isSelected: viewModel.selectedSection == section
                    ) {
                        viewModel.selectedSection = section
                    }
                }
            }
            .padding(.horizontal, 8)

            Divider()
                .opacity(0.3)
                .padding(.horizontal, 14)

            // Courses Filter List
            VStack(alignment: .leading, spacing: 4) {
                Text("COURSES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        SidebarCourseRow(
                            code: "All Courses",
                            subtitle: "\(viewModel.uniqueEnabledCourseCodes.count) active",
                            color: .cyan,
                            isSelected: viewModel.selectedCourseFilter == "ALL"
                        ) {
                            viewModel.selectedCourseFilter = "ALL"
                        }

                        ForEach(viewModel.uniqueEnabledCourseCodes, id: \.self) { code in
                            let courseTitle = viewModel.courses.first(where: { $0.courseCode == code })?.courseTitle ?? code
                            SidebarCourseRow(
                                code: code,
                                subtitle: courseTitle,
                                color: courseColor(for: code),
                                isSelected: viewModel.selectedCourseFilter == code
                            ) {
                                viewModel.selectedCourseFilter = code
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Divider()
                .opacity(0.3)
                .padding(.horizontal, 14)

            // Bottom Sync & Quit Controls
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    viewModel.triggerManualSync()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(viewModel.syncState.isBusy ? "Syncing Brightspace..." : "Sync All Now")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(GlassActionButtonStyle(prominent: true))
                .disabled(viewModel.syncState.isBusy)

                HStack {
                    Toggle("Auto-quit after sync", isOn: $viewModel.autoCloseAfterSync)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "power")
                            Text("Quit")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Quit Brightspace Pulse completely (0% background CPU)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Color.primary.opacity(0.025))
    }

    private var workspaceTopHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(viewModel.selectedSection.rawValue)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)

                    if viewModel.selectedCourseFilter != "ALL" {
                        CourseTagBadge(
                            courseCode: viewModel.selectedCourseFilter,
                            accent: courseColor(for: viewModel.selectedCourseFilter)
                        )
                    }
                }

                Text(lastSyncSubtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlowStatusBadge(state: viewModel.syncState)

            Button {
                viewModel.isWebLoginSheetPresented = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 11))
                    Text("SSO Login")
                }
            }
            .buttonStyle(GlassActionButtonStyle(prominent: false))
            .help("Sign in or refresh your Brightspace SSO session")

            Button {
                LocalFileManager.shared.openRootStorageFolder()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text("Open Folder")
                }
            }
            .buttonStyle(GlassActionButtonStyle(prominent: false))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var authRequiredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.radiowaves.forward.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Brightspace Session Expired")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Sign in via SSO to refresh your session and pull live assignments, quizzes, files, and grades.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sign In via SSO") {
                viewModel.isWebLoginSheetPresented = true
            }
            .buttonStyle(GlassActionButtonStyle(prominent: true))
        }
        .liquidGlassCard(cornerRadius: 11, padding: 12, isInteractive: false)
    }

    private var lastSyncSubtitle: String {
        guard let date = viewModel.lastSyncDate else {
            return "On-Demand Mode • Syncs automatically on open"
        }
        let formatter = SharedFormatters.relative
        return "Last synced \(formatter.localizedString(for: date, relativeTo: Date())) • On-Demand Mode"
    }

    private func badgeText(for section: WorkspaceSection) -> String? {
        switch section {
        case .upcoming:
            let c = viewModel.upcomingDeadlinesCount
            return c > 0 ? "\(c)" : nil
        case .files:
            let c = viewModel.localFiles.count
            return c > 0 ? "\(c)" : nil
        case .grades:
            let c = viewModel.grades.count
            return c > 0 ? "\(c)" : nil
        case .settings:
            return nil
        }
    }
}

// MARK: - Section 1: Upcoming Assignments, Quizzes & Exams View

public struct UpcomingDeadlinesView: View {
    @ObservedObject var viewModel: AppViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Urgent 48h Crunch Alert Banner (if any deadline is due within 48 hours)
            if !viewModel.urgentDeadlinesWithin48Hours.isEmpty {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 34, height: 34)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("48-Hour Deadline Alert (\(viewModel.urgentDeadlinesWithin48Hours.count) Due Soon)")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.primary)
                        let names = viewModel.urgentDeadlinesWithin48Hours.map { "\($0.courseCode): \($0.title)" }.joined(separator: " • ")
                        Text(names)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .liquidGlassCard(cornerRadius: 12, padding: 12, isInteractive: false)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // Filter & Search Bar
            HStack(spacing: 8) {
                ForEach(["ALL", "Assignment", "Quiz", "Exam / Test", "Event"], id: \.self) { kind in
                    FilterChip(
                        title: kind == "ALL" ? "All Types" : "\(kind)s",
                        isSelected: viewModel.selectedDeadlineKind == kind
                    ) {
                        viewModel.selectedDeadlineKind = kind
                    }
                }

                Spacer()

                Toggle("Include Past / Completed", isOn: $viewModel.showPastDeadlines)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search deadlines...", text: $viewModel.deadlineSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .frame(width: 175)
            }
            .padding(.horizontal, 20)
            .padding(.top, viewModel.urgentDeadlinesWithin48Hours.isEmpty ? 14 : 4)

            let deadlineItems = viewModel.filteredDeadlines
            if deadlineItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.green.opacity(0.8))
                    Text(viewModel.showPastDeadlines ? "No matching items in this filter." : "No upcoming deadlines in this filter!")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Toggle 'Include Past / Completed' above to inspect previous quizzes, assignments, and tests.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(deadlineItems) { item in
                            DeadlineRowCard(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct DeadlineRowCard: View {
    let item: BrightspaceDeadlineItem

    private var accent: Color {
        courseColor(for: item.courseCode)
    }

    private var kindIcon: String {
        switch item.kind {
        case .assignment: return "doc.badge.arrow.up.fill"
        case .quiz: return "checklist.checked"
        case .exam: return "graduationcap.fill"
        case .calendarEvent: return "calendar"
        }
    }

    private var urgencyBadge: (text: String, color: Color) {
        guard let date = item.effectiveDate else {
            return ("Open / No Due Date", .secondary)
        }
        let delta = date.timeIntervalSinceNow
        if delta < 0 {
            return ("Due \(SharedFormatters.relative.localizedString(for: date, relativeTo: Date()))", .secondary)
        } else if delta <= 3600 * 48 {
            let hours = max(1, Int(delta / 3600))
            return ("Due in \(hours)h", .orange)
        } else {
            let days = max(1, Int(delta / 86400))
            return ("In \(days) days", .cyan)
        }
    }

    private var formattedDateString: String {
        guard let date = item.effectiveDate else { return "No fixed deadline posted" }
        return SharedFormatters.deadline.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: kindIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    CourseTagBadge(courseCode: item.courseCode, accent: accent)

                    Text(item.kind.rawValue.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))

                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(formattedDateString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if !item.details.isEmpty {
                        Text("• \(item.details)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            let badge = urgencyBadge
            Text(badge.text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(badge.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .contentShape(Capsule(style: .continuous))
                .background(
                    Capsule(style: .continuous)
                        .fill(badge.color.opacity(0.14))
                )

            if let urlStr = item.webURL, let url = URL(string: urlStr) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Brightspace")
            }
        }
        .liquidGlassCard(cornerRadius: 11, padding: 11, isInteractive: true)
    }
}

// MARK: - Section 2: Course Files & Announcements Browser View

public struct CourseFilesBrowserView: View {
    @ObservedObject var viewModel: AppViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All Files (\(viewModel.localFiles.count))",
                    isSelected: viewModel.selectedFileCategory == "ALL"
                ) {
                    viewModel.selectedFileCategory = "ALL"
                }

                FilterChip(
                    title: "PDFs & Slides",
                    isSelected: viewModel.selectedFileCategory == "PDF"
                ) {
                    viewModel.selectedFileCategory = "PDF"
                }

                FilterChip(
                    title: "Labs & Code",
                    isSelected: viewModel.selectedFileCategory == "LABS"
                ) {
                    viewModel.selectedFileCategory = "LABS"
                }

                FilterChip(
                    title: "Announcements",
                    isSelected: viewModel.selectedFileCategory == "ANNOUNCEMENTS"
                ) {
                    viewModel.selectedFileCategory = "ANNOUNCEMENTS"
                }

                Spacer()

                TextField("Search 240+ course files...", text: $viewModel.fileSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .frame(width: 210)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if viewModel.filteredLocalFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No local course files match this filter.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredLocalFiles) { file in
                            LocalCourseFileRowCard(file: file)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct LocalCourseFileRowCard: View {
    let file: LocalCourseFileItem

    private var accent: Color {
        courseColor(for: file.courseCode)
    }

    private var fileIcon: String {
        switch file.fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "md", "txt": return "megaphone.fill"
        case "c", "h", "py", "swift", "java": return "chevron.left.forwardslash.chevron.right"
        case "pptx", "ppt", "key": return "rectangle.on.rectangle.angled.fill"
        case "docx", "doc": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: file.fileSizeBytes, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: fileIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    CourseTagBadge(courseCode: file.courseCode, accent: accent)

                    Text(file.fileName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(file.moduleName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(formattedSize)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Open") {
                LocalFileManager.shared.openFile(url: URL(fileURLWithPath: file.localFilePath))
            }
            .buttonStyle(GlassActionButtonStyle(prominent: false))

            Button {
                LocalFileManager.shared.revealInFinder(url: URL(fileURLWithPath: file.localFilePath))
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .liquidGlassCard(cornerRadius: 11, padding: 10, isInteractive: true)
    }
}

// MARK: - Section 3: Grades & Academic Standing Dashboard View

public struct GradesDashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    public var body: some View {
        if viewModel.filteredGradesByCourse.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No released grades for this filter yet.")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Click 'Sync All Now' in the sidebar to pull the latest grades from Brightspace.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Course Standing Summary Cards Row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.filteredGradesByCourse, id: \.courseCode) { group in
                                CourseGradeSummaryCard(courseCode: group.courseCode, items: group.items)
                            }
                        }
                    }

                    // Detailed Per-Course Grade Tables
                    ForEach(viewModel.filteredGradesByCourse, id: \.courseCode) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                CourseTagBadge(courseCode: group.courseCode, accent: courseColor(for: group.courseCode))
                                Text("\(group.items.count) Graded Items")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }

                            VStack(spacing: 6) {
                                ForEach(group.items) { item in
                                    GradeItemRowCard(item: item)
                                }
                            }
                        }
                        .liquidGlassCard(cornerRadius: 13, padding: 14, isInteractive: false)
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct CourseGradeSummaryCard: View {
    let courseCode: String
    let items: [BrightspaceGradeItem]

    private var accent: Color {
        courseColor(for: courseCode)
    }

    private var courseStanding: (percentage: Double, earnedPts: Double, totalPts: Double)? {
        let cats = items.filter { $0.isCategory }
        let validCats = cats.filter { ($0.weightedDenominator ?? 0) > 0 }
        if !validCats.isEmpty {
            let num = validCats.compactMap(\.weightedNumerator).reduce(0, +)
            let den = validCats.compactMap(\.weightedDenominator).reduce(0, +)
            if den > 0 {
                return ((num / den) * 100.0, num, den)
            }
        }

        if courseCode.uppercased() == "MAT1320" {
            let assigns = items.filter { $0.name.lowercased().contains("assignment") && ($0.pointsDenominator ?? 0) > 0 }
            let test1 = items.first { $0.name.lowercased().contains("test 1") && ($0.pointsDenominator ?? 0) > 0 }
            var weightedAcc = 0.0
            var totalEvalWeight = 0.0
            if !assigns.isEmpty {
                let avg = assigns.compactMap(\.percentage).reduce(0, +) / Double(assigns.count)
                weightedAcc += (avg / 100.0) * 10.0
                totalEvalWeight += 10.0
            }
            if let t1 = test1, let p = t1.percentage {
                weightedAcc += (p / 100.0) * 20.0
                totalEvalWeight += 20.0
            }
            if totalEvalWeight > 0 {
                return ((weightedAcc / totalEvalWeight) * 100.0, weightedAcc, totalEvalWeight)
            }
        }

        let nonCat = items.filter { !$0.isCategory && ($0.pointsDenominator ?? 0) > 0 }
        guard !nonCat.isEmpty else { return nil }
        let pcts = nonCat.compactMap(\.percentage)
        guard !pcts.isEmpty else { return nil }
        let avg = pcts.reduce(0, +) / Double(pcts.count)
        return (avg, avg, 100.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CourseTagBadge(courseCode: courseCode, accent: accent)
                Spacer()
                Text("\(items.filter { !$0.isCategory }.count) items")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let standing = courseStanding {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f%%", standing.percentage))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(letterGrade(for: standing.percentage))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor(for: standing.percentage))
                }

                if standing.totalPts < 100.0 {
                    Text(String(format: "%.1f / %.1f course pts", standing.earnedPts, standing.totalPts))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Graded")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 175)
        .liquidGlassCard(cornerRadius: 12, padding: 12, isInteractive: false)
    }
}

private struct GradeItemRowCard: View {
    let item: BrightspaceGradeItem

    private var pct: Double {
        item.percentage ?? 0
    }

    private var scoreText: String {
        if let n = item.pointsNumerator, let d = item.pointsDenominator, d > 0 {
            return String(format: "%.2g / %.2g", n, d)
        }
        if let wn = item.weightedNumerator, let wd = item.weightedDenominator, wd > 0 {
            return String(format: "%.2f / %.2f wt", wn, wd)
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            if item.isCategory {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.cyan)
            } else {
                Circle()
                    .fill(gradeColor(for: pct))
                    .frame(width: 7, height: 7)
                    .padding(.leading, 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: item.isCategory ? 12.5 : 12, weight: item.isCategory ? .bold : .medium))
                        .foregroundStyle(.primary)

                    if item.isCategory {
                        Text("CATEGORY SUMMARY")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.cyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.cyan.opacity(0.14)))
                    }
                }

                if !item.comments.isEmpty {
                    Text(item.comments)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Progress Bar
            if item.percentage != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(gradeColor(for: pct))
                            .frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, pct)) / 100.0)))
                    }
                }
                .frame(width: 85, height: 6)
            }

            if !scoreText.isEmpty {
                Text(scoreText)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 95, alignment: .trailing)
            }

            Text(item.displayedGrade)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(gradeColor(for: pct))
                .frame(width: 44, alignment: .center)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(gradeColor(for: pct).opacity(0.14))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, item.isCategory ? 8 : 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.isCategory ? Color.cyan.opacity(0.07) : Color.primary.opacity(0.025))
        )
    }
}

// MARK: - Shared Helper Navigation Components

private struct SidebarNavRow: View {
    let title: String
    let icon: String
    let badge: String?
    let badgeColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.cyan : Color.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(badgeColor.opacity(0.16)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarCourseRow: View {
    let code: String
    let subtitle: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(code)
                        .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? color.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact MenuBar Popover (Quick View)

public struct StatusPopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    var onOpenSettings: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.cyan)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Brightspace Pulse")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("\(viewModel.upcomingDeadlinesCount) Upcoming • \(viewModel.localFiles.count) Files • \(viewModel.grades.count) Grades")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                GlowStatusBadge(state: viewModel.syncState)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider().opacity(0.4)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredActivities.prefix(8)) { item in
                        ActivityFeedCard(item: item) {
                            LocalFileManager.shared.revealInFinder(
                                url: URL(fileURLWithPath: item.localFilePath)
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(maxHeight: 240)

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                Button("Open Desktop Hub") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(GlassActionButtonStyle(prominent: false))

                Spacer()

                Button(viewModel.syncState.isBusy ? "Syncing..." : "Sync Now") {
                    viewModel.triggerManualSync()
                }
                .buttonStyle(GlassActionButtonStyle(prominent: true))
                .disabled(viewModel.syncState.isBusy)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .foregroundStyle(.red)
                }
                .buttonStyle(GlassActionButtonStyle(prominent: false))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 420)
        .liquidGlassContainer(cornerRadius: 16)
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
                .contentShape(Capsule(style: .continuous))
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
        case .lectureSlide: return "doc.richtext.fill"
        case .document: return "doc.text.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    private var accentColor: Color {
        courseColor(for: item.courseCode)
    }

    private var relativeTimeString: String {
        let formatter = SharedFormatters.relative
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
                }
            }

            Button(action: onReveal) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .liquidGlassCard(cornerRadius: 11, padding: 10, isInteractive: true)
    }
}

// MARK: - Section 4: Settings View

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
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

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
    }

    private var accountTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Brightspace Instance & Valence Endpoint")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                TextField("https://brightspace.example.edu", text: $viewModel.brightspaceURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Text("Queries content, announcements, dropbox assignments, quizzes, calendar events, and grades.")
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
                            ? "✓ Active session tokens verified"
                            : "Session expired or missing — click Sign In via WebView"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        (!viewModel.d2lSessionVal.isEmpty && !viewModel.d2lSecureSessionVal.isEmpty)
                            ? Color.green
                            : Color.orange
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
            }
            .liquidGlassCard(cornerRadius: 12, padding: 14, isInteractive: false)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Monitored Brightspace Courses")
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

                        CourseTagBadge(courseCode: course.courseCode, accent: courseColor(for: course.courseCode))
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

    private var scheduleAndNotebookTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Route B (Direct Automation / IPC Hook)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                TextField(
                    "e.g. /usr/local/bin/notebook-ingest --course \"$BRIGHTSPACE_COURSE_CODE\" --file \"$BRIGHTSPACE_FILE_PATH\"",
                    text: $viewModel.directAutomationCommand
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
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


// MARK: - Shared Cached Formatters (avoid per-row allocation)

enum SharedFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    static let deadline: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE, MMM d • h:mm a"
        return df
    }()
}
