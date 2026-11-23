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
                        onCookiesCaptured: { s1, s2, fullCookie, csrf, activeURL in
                            viewModel.brightspaceURL = activeURL
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
                AppIconBadge(size: 36, isBusy: viewModel.syncState.isBusy)

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
                    let progress = viewModel.semesterProgressSummary
                    VStack(alignment: .leading, spacing: 3) {
                        SidebarCourseRow(
                            code: "All Courses",
                            subtitle: "\(viewModel.uniqueEnabledCourseCodes.count) active • \(progress.totalCompleted)/\(progress.totalDeliverables) done",
                            completionBadge: progress.totalDeliverables > 0 ? String(format: "%.0f%%", progress.overallPercentage) : nil,
                            color: .cyan,
                            isSelected: viewModel.selectedCourseFilter == "ALL"
                        ) {
                            viewModel.selectedCourseFilter = "ALL"
                        }

                        ForEach(viewModel.uniqueEnabledCourseCodes, id: \.self) { code in
                            let courseTitle = viewModel.courses.first(where: { $0.courseCode == code })?.courseTitle ?? code
                            let cSummary = progress.courseSummaries.first(where: { $0.courseCode == code })
                            SidebarCourseRow(
                                code: code,
                                subtitle: courseTitle,
                                completionBadge: cSummary.map { String(format: "%.0f%%", $0.completionPercentage) },
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
        let progress = viewModel.semesterProgressSummary

        VStack(alignment: .leading, spacing: 10) {
            // 1. Course & Semester Completion Progress Dashboard
            if progress.totalDeliverables > 0 {
                SemesterProgressHeroCard(
                    summary: progress,
                    selectedCourseFilter: viewModel.selectedCourseFilter,
                    selectedStatusFilter: viewModel.selectedStatusFilter,
                    onSelectCourse: { code in
                        if viewModel.selectedCourseFilter == code {
                            viewModel.selectedCourseFilter = "ALL"
                        } else {
                            viewModel.selectedCourseFilter = code
                        }
                    },
                    onSelectStatus: { status in
                        viewModel.selectedStatusFilter = status
                        viewModel.showPastDeadlines = (status == .fullSemester)
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // 2. Urgent 48h Crunch Alert Banner (only items that still Need Attention)
            if !viewModel.urgentDeadlinesWithin48Hours.isEmpty {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Image(systemName: "flame.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("48-Hour Deadline Alert (\(viewModel.urgentDeadlinesWithin48Hours.count) Need Attention)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                        let names = viewModel.urgentDeadlinesWithin48Hours.map { "\($0.courseCode): \($0.title)" }.joined(separator: " • ")
                        Text(names)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    Spacer()

                    Button {
                        viewModel.selectedStatusFilter = .needsAttention
                        viewModel.showPastDeadlines = false
                    } label: {
                        Text("Focus Pending")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
                }
                .liquidGlassCard(cornerRadius: 11, padding: 10, isInteractive: false)
                .padding(.horizontal, 20)
            }

            // 3. Status Filter & Type Filter Toolbar
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("STATUS")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 2)

                    StatusFilterPill(
                        title: "All Upcoming",
                        icon: "calendar.badge.clock",
                        accent: .cyan,
                        isSelected: viewModel.selectedStatusFilter == .allUpcoming && !viewModel.showPastDeadlines
                    ) {
                        viewModel.selectedStatusFilter = .allUpcoming
                        viewModel.showPastDeadlines = false
                    }

                    StatusFilterPill(
                        title: "Needs Attention (\(progress.totalNeedsAttention))",
                        icon: "exclamationmark.circle.fill",
                        accent: .orange,
                        isSelected: viewModel.selectedStatusFilter == .needsAttention && !viewModel.showPastDeadlines
                    ) {
                        viewModel.selectedStatusFilter = .needsAttention
                        viewModel.showPastDeadlines = false
                    }

                    StatusFilterPill(
                        title: "Completed (\(progress.totalCompleted))",
                        icon: "checkmark.circle.fill",
                        accent: .green,
                        isSelected: viewModel.selectedStatusFilter == .completed && !viewModel.showPastDeadlines
                    ) {
                        viewModel.selectedStatusFilter = .completed
                        viewModel.showPastDeadlines = false
                    }

                    StatusFilterPill(
                        title: "Full Semester (\(progress.totalDeliverables))",
                        icon: "list.bullet.rectangle.portrait",
                        accent: .purple,
                        isSelected: viewModel.selectedStatusFilter == .fullSemester || viewModel.showPastDeadlines
                    ) {
                        viewModel.selectedStatusFilter = .fullSemester
                        viewModel.showPastDeadlines = true
                    }

                    Spacer()

                    TextField("Search deadlines...", text: $viewModel.deadlineSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .frame(width: 185)
                }

                HStack(spacing: 6) {
                    Text("TYPE")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 10)

                    ForEach(["ALL", "Assignment", "Quiz", "Exam / Test", "Event"], id: \.self) { kind in
                        FilterChip(
                            title: kind == "ALL" ? "All Types" : "\(kind)s",
                            isSelected: viewModel.selectedDeadlineKind == kind
                        ) {
                            viewModel.selectedDeadlineKind = kind
                        }
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)

            // 4. Deadlines List
            let deadlineItems = viewModel.filteredDeadlines
            if deadlineItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.green.opacity(0.85))
                    Text(emptyStateHeadline)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(emptyStateSubtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(deadlineItems) { item in
                            let isDone = viewModel.isDeadlineCompleted(item)
                            DeadlineRowCard(
                                item: item,
                                isCompleted: isDone,
                                onToggleCompletion: {
                                    viewModel.toggleDeadlineCompletion(item)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var emptyStateHeadline: String {
        switch viewModel.selectedStatusFilter {
        case .needsAttention:
            return "All caught up! Nothing needs your attention right now."
        case .completed:
            return "No completed items match this filter yet."
        case .allUpcoming, .fullSemester:
            return "No matching deadlines in this filter."
        }
    }

    private var emptyStateSubtitle: String {
        switch viewModel.selectedStatusFilter {
        case .needsAttention:
            return "Switch to 'Completed' or 'All Upcoming' above to view your finished coursework."
        case .completed:
            return "Click 'Needs Attention' on any upcoming quiz or assignment card to mark it as Completed."
        case .allUpcoming, .fullSemester:
            return "Try switching course or type filters above."
        }
    }
}

// MARK: - Semester & Per-Course Progress Hero Dashboard

private struct SemesterProgressHeroCard: View {
    let summary: SemesterProgressSummary
    let selectedCourseFilter: String
    let selectedStatusFilter: DeadlineStatusFilter
    let onSelectCourse: (String) -> Void
    let onSelectStatus: (DeadlineStatusFilter) -> Void

    private var progressColor: Color {
        if summary.overallPercentage >= 85 { return .green }
        if summary.overallPercentage >= 60 { return .cyan }
        return .orange
    }

    private var scopeTitle: String {
        selectedCourseFilter == "ALL"
            ? "SEMESTER PROGRESS TRACKER • HOW FAR YOU'VE COME"
            : "\(selectedCourseFilter) COURSE PROGRESS • HOW FAR YOU'VE COME"
    }

    private var milestoneNarrative: String {
        let pctStr = String(format: "%.0f%%", summary.overallPercentage)
        if selectedCourseFilter == "ALL" {
            if summary.totalNeedsAttention == 0 {
                return "You've completed 100% (\(summary.totalCompleted)/\(summary.totalDeliverables)) of tracked coursework across all courses!"
            }
            return "You've completed \(pctStr) of your semester (\(summary.totalCompleted) of \(summary.totalDeliverables) deliverables done) • \(summary.totalNeedsAttention) left needing attention."
        } else {
            if summary.totalNeedsAttention == 0 {
                return "You've completed 100% (\(summary.totalCompleted)/\(summary.totalDeliverables)) of \(selectedCourseFilter)!"
            }
            return "You've completed \(pctStr) of \(selectedCourseFilter) (\(summary.totalCompleted) of \(summary.totalDeliverables) deliverables done) • \(summary.totalNeedsAttention) still need attention."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Row: Overall Progress & Quick Status Summary Pills
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(progressColor)
                        Text(scopeTitle)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.0f%% Completed", summary.overallPercentage))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("(\(summary.totalCompleted) / \(summary.totalDeliverables) done)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(progressColor)

                        if summary.completedUpcomingCount > 0 {
                            Text("+\(summary.completedUpcomingCount) finished early")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                        }
                    }

                    Text(milestoneNarrative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Interactive Summary Counters
                HStack(spacing: 8) {
                    Button {
                        onSelectStatus(selectedStatusFilter == .needsAttention ? .allUpcoming : .needsAttention)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(summary.totalNeedsAttention)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text("Need Attention")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                        }
                        .foregroundStyle(summary.totalNeedsAttention > 0 ? Color.orange : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.orange.opacity(selectedStatusFilter == .needsAttention ? 0.22 : 0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.orange.opacity(selectedStatusFilter == .needsAttention ? 0.55 : 0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Filter to items that still need your attention")

                    Button {
                        onSelectStatus(selectedStatusFilter == .completed ? .allUpcoming : .completed)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(summary.totalCompleted)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text("Completed")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                        }
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.green.opacity(selectedStatusFilter == .completed ? 0.22 : 0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.green.opacity(selectedStatusFilter == .completed ? 0.55 : 0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("View all completed coursework")
                }
            }

            // Full-Width Overall Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [progressColor.opacity(0.85), progressColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * CGFloat(min(100, max(0, summary.overallPercentage)) / 100.0)))
                }
            }
            .frame(height: 7)

            // Per-Course Completion Cards Row ("How much of each course you completed")
            if !summary.courseSummaries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(summary.courseSummaries) { course in
                            CourseCompletionCard(
                                course: course,
                                isSelected: selectedCourseFilter == course.courseCode,
                                onSelect: {
                                    onSelectCourse(course.courseCode)
                                }
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .liquidGlassCard(cornerRadius: 13, padding: 13, isInteractive: false)
    }
}

private struct CourseCompletionCard: View {
    let course: CourseProgressSummary
    let isSelected: Bool
    let onSelect: () -> Void

    private var accent: Color {
        courseColor(for: course.courseCode)
    }

    private var barColor: Color {
        course.needsAttentionCount == 0 ? .green : accent
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    CourseTagBadge(courseCode: course.courseCode, accent: accent)
                    Spacer()
                    Text(String(format: "%.0f%%", course.completionPercentage))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(course.needsAttentionCount == 0 ? Color.green : Color.primary)
                }

                // Mini Course Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                        Capsule(style: .continuous)
                            .fill(barColor)
                            .frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, course.completionPercentage)) / 100.0)))
                    }
                }
                .frame(height: 5)

                HStack(spacing: 4) {
                    Text("\(course.completedCount)/\(course.totalCount) done")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    if course.needsAttentionCount == 0 {
                        Text("All done ✓")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(course.needsAttentionCount) left")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 156, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.16) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.55) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("You completed \(String(format: "%.0f%%", course.completionPercentage)) of \(course.courseCode) (\(course.completedCount) of \(course.totalCount) items). Click to filter by \(course.courseCode).")
    }
}

private struct StatusFilterPill: View {
    let title: String
    let icon: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? accent : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .contentShape(Capsule(style: .continuous))
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? accent.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.48) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DeadlineRowCard: View {
    let item: BrightspaceDeadlineItem
    let isCompleted: Bool
    let onToggleCompletion: () -> Void

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

    private var isUrgent48h: Bool {
        guard !isCompleted, let date = item.effectiveDate else { return false }
        let delta = date.timeIntervalSinceNow
        return delta >= -1800 && delta <= 3600 * 48
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
            return ("Due in \(hours)h", isCompleted ? .secondary : .orange)
        } else {
            let days = max(1, Int(delta / 86400))
            return ("In \(days) days", isCompleted ? .secondary : .cyan)
        }
    }

    private var formattedDateString: String {
        guard let date = item.effectiveDate else { return "No fixed deadline posted" }
        return SharedFormatters.deadline.string(from: date)
    }

    var body: some View {
        HStack(spacing: 11) {
            // Left Quick-Toggle Checkmark Button
            Button(action: onToggleCompletion) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? Color.green.opacity(0.18) : Color.orange.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isCompleted ? Color.green : Color.orange)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isCompleted ? "Marked as Completed — click to mark as Needs Attention" : "Needs Attention — click to mark as Completed")

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((isCompleted ? Color.green : accent).opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: kindIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCompleted ? Color.green : accent)
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
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted, color: .secondary.opacity(0.6))
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

            // Countdown / Relative Date Badge
            let badge = urgencyBadge
            Text(badge.text)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(badge.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(badge.color.opacity(0.12))
                )

            // Interactive Status Button: "Needs Attention" (Default) <-> "Completed"
            Button(action: onToggleCompletion) {
                HStack(spacing: 5) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(isCompleted ? "Completed" : "Needs Attention")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isCompleted ? Color.green : (isUrgent48h ? Color.orange : Color.amberAccent))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Capsule(style: .continuous))
                .background(
                    Capsule(style: .continuous)
                        .fill(isCompleted ? Color.green.opacity(0.16) : Color.orange.opacity(0.15))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isCompleted ? Color.green.opacity(0.45) : Color.orange.opacity(0.40),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .help(isCompleted ? "Click to switch back to Needs Attention" : "Click to mark as Completed")

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
        .liquidGlassCard(cornerRadius: 11, padding: 10, isInteractive: true)
    }
}

private extension Color {
    static let amberAccent = Color(red: 0.98, green: 0.62, blue: 0.15)
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
                    // Cumulative GPA (CGPA) & Academic Standing Hero Banner
                    if let summary = viewModel.cumulativeGPASummary {
                        CGPAHeroCard(summary: summary, selectedCourse: viewModel.selectedCourseFilter)
                    }

                    // Section Divider Label
                    HStack(spacing: 6) {
                        Text("COURSE BREAKDOWN")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("\(viewModel.filteredGradesByCourse.count) Courses Graded")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.top, 2)

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

// MARK: - CGPA & Academic Standing Hero Card (uOttawa 10.0 & 4.0 Scale)

private struct CGPAHeroCard: View {
    let summary: CumulativeGPASummary
    let selectedCourse: String

    @State private var showDetails: Bool = false

    private var isSingleCourseFiltered: Bool {
        selectedCourse != "ALL"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Row: Title, uOttawa Scale Tag, Academic Standing Pill & Disclosure
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(summary.standingColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: isSingleCourseFiltered ? "graduationcap.fill" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(summary.standingColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isSingleCourseFiltered ? "\(selectedCourse) Academic Standing" : "Cumulative GPA (CGPA)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("uOttawa 10.0 Scale")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }

                    Text(summary.standingTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(summary.standingColor)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        showDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showDetails ? "chevron.up.circle.fill" : "info.circle")
                            .font(.system(size: 11.5))
                        Text(showDetails ? "Hide Scale" : "Scale Details")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Capsule())
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }

            // Middle Metrics Row: Large 10.0 CGPA + 4.0 GPA + Cumulative Average
            HStack(spacing: 24) {
                // Metric 1: uOttawa CGPA (10.0 scale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSingleCourseFiltered ? "COURSE GPA" : "OFFICIAL CGPA")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(String(format: "%.2f", summary.cgpa10))
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("/ 10.0")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(summary.letterGrade)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(for: summary.averagePercentage))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(gradeColor(for: summary.averagePercentage).opacity(0.16))
                            )
                    }
                }

                Divider()
                    .frame(height: 38)
                    .opacity(0.3)

                // Metric 2: Standard 4.0 Scale
                VStack(alignment: .leading, spacing: 2) {
                    Text("STANDARD 4.0 SCALE")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.2f", summary.cgpa4))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("/ 4.00")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                    .frame(height: 38)
                    .opacity(0.3)

                // Metric 3: Cumulative Average Percentage
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEIGHTED AVERAGE")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f%%", summary.averagePercentage))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(for: summary.averagePercentage))
                    }
                }

                Spacer()

                // Metric 4: Courses Contributing
                VStack(alignment: .trailing, spacing: 2) {
                    Text("COURSES")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Text("\(summary.gradedCoursesCount) Graded")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }

            // Visual Progress Meter on 10.0 Scale
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)

                        let fraction = max(0.0, min(1.0, summary.cgpa10 / 10.0))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan, summary.standingColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * fraction), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("0.0 (F)")
                    Spacer()
                    Text("5.0 (Pass)")
                    Spacer()
                    Text("7.0 (B+)")
                    Spacer()
                    Text("8.5 (Dean's List)")
                    Spacer()
                    Text("10.0 (A+)")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            }

            // Contributing Course Breakdown Chips
            if !summary.courseStandings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(summary.courseStandings) { standing in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(courseColor(for: standing.courseCode))
                                    .frame(width: 6, height: 6)

                                Text(standing.courseCode)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.primary)

                                if standing.isSatisfactoryOnly {
                                    Text("S (Pass)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.mint)
                                } else {
                                    Text(String(format: "%.1f", standing.gradePoint10))
                                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                                        .foregroundStyle(gradeColor(for: standing.percentage))

                                    Text("(\(standing.letterGrade) • \(String(format: "%.0f%%", standing.percentage)))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                            )
                        }
                    }
                }
            }

            // Expandable uOttawa Scale Reference Details
            if showDetails {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().opacity(0.25)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Official uOttawa Senate 10.0 Grading Scheme:")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("• A+ = 10.0 (90–100%)  • A = 9.0 (85–89%)  • A- = 8.0 (80–84%)\n• B+ = 7.0 (75–79%)   • B = 6.0 (70–74%)   • C+ = 5.0 (65–69%)\n• C  = 4.0 (60–64%)   • D+ = 3.0 (55–59%)  • D = 2.0 (50–54%)")
                                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Honours & Standing Rules:")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("• Dean's Honour List: Term GPA ≥ 8.50 with ≥9 credits\n• Engineering Good Standing: Cumulative GPA ≥ 5.00\n• Non-numerical S/NS courses are excluded from GPA")
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .liquidGlassCard(cornerRadius: 14, padding: 16, isInteractive: false)
    }
}

private struct CourseGradeSummaryCard: View {
    let courseCode: String
    let items: [BrightspaceGradeItem]

    private var accent: Color {
        courseColor(for: courseCode)
    }

    private var standing: CourseStandingInfo? {
        calculateCourseStanding(courseCode: courseCode, items: items)
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

            if let st = standing {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f%%", st.percentage))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(st.letterGrade)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor(for: st.percentage))
                }

                HStack(spacing: 5) {
                    if st.isSatisfactoryOnly {
                        Text("S • Pass")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.mint)
                    } else {
                        Text(String(format: "%.1f / 10.0 GPA", st.gradePoint10))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(for: st.percentage))
                    }

                    if st.totalPts < 100.0 {
                        Text("• \(String(format: "%.1f", st.earnedPts))/\(String(format: "%.0f", st.totalPts)) pts")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Graded")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 180)
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
    var completionBadge: String? = nil
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

                Spacer(minLength: 4)

                if let completionBadge {
                    Text(completionBadge)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(completionBadge == "100%" ? Color.green : color)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill((completionBadge == "100%" ? Color.green : color).opacity(0.14))
                        )
                }
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
                AppIconBadge(size: 28, isBusy: viewModel.syncState.isBusy)

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
    @State private var currentURLString: String
    @State private var reloadToken = UUID()
    public let onCookiesCaptured: (String, String, String, String?, String) -> Void
    public let onCancel: () -> Void

    public init(
        baseURLString: String,
        onCookiesCaptured: @escaping (String, String, String, String?, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._currentURLString = State(initialValue: baseURLString.isEmpty ? "https://uottawa.brightspace.com" : baseURLString)
        self.onCookiesCaptured = onCookiesCaptured
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Brightspace Single Sign-On")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("Select your institution or enter your portal URL. Session cookies & CSRF token are captured automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(GlassActionButtonStyle(prominent: false))
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // University Portal Selector & Address Bar
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    TextField("https://uottawa.brightspace.com", text: $currentURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))

                    Button {
                        reloadToken = UUID()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Load")
                        }
                    }
                    .buttonStyle(GlassActionButtonStyle(prominent: true))
                }

                HStack(spacing: 6) {
                    Text("Presets:")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)

                    ForEach([
                        ("uOttawa", "https://uottawa.brightspace.com"),
                        ("Carleton", "https://brightspace.carleton.ca"),
                        ("Waterloo", "https://learn.uwaterloo.ca"),
                        ("TMU", "https://my.torontomu.ca"),
                        ("Calgary", "https://d2l.ucalgary.ca")
                    ], id: \.0) { school, url in
                        Button(school) {
                            currentURLString = url
                            reloadToken = UUID()
                        }
                        .font(.system(size: 10, weight: currentURLString.contains(url) ? .bold : .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(currentURLString.contains(url) ? 0.12 : 0.04)))
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            BrightspaceCookieWebView(
                baseURLString: currentURLString,
                reloadToken: reloadToken,
                onCaptured: { s1, s2, fullCookie, csrf in
                    onCookiesCaptured(s1, s2, fullCookie, csrf, currentURLString)
                }
            )
        }
        .liquidGlassContainer(cornerRadius: 14)
    }
}

private struct BrightspaceCookieWebView: NSViewRepresentable {
    let baseURLString: String
    let reloadToken: UUID
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
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetString = trimmed.hasSuffix("/") ? "\(trimmed)d2l/home" : "\(trimmed)/d2l/home"
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

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetString = trimmed.hasSuffix("/") ? "\(trimmed)d2l/home" : "\(trimmed)/d2l/home"
            if let url = URL(string: targetString) {
                nsView.load(URLRequest(url: url))
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCaptured: (String, String, String, String?) -> Void
        var lastReloadToken: UUID? = nil
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


// MARK: - In-App Brand Icon (uses the bundled AppIcon.icns)

struct AppIconBadge: View {
    let size: CGFloat
    var isBusy: Bool = false

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityLabel("Brightspace Pulse")
    }
}
