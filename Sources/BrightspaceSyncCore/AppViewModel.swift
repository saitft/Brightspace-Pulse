import SwiftUI
import AppKit
import WebKit

// MARK: - Main Navigation Sections

public enum WorkspaceSection: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming & Exams"
    case files = "Course Files"
    case grades = "Grades"
    case settings = "Settings & Auth"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .upcoming: return "calendar.badge.clock"
        case .files: return "folder.fill"
        case .grades: return "chart.bar.xaxis.ascending"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - Main-Actor Observable Coordinator

@MainActor
public final class AppViewModel: ObservableObject {
    public static let shared = AppViewModel()

    @Published public var selectedSection: WorkspaceSection = .upcoming
    @Published public var syncState: SyncVisualState = .synced
    @Published public var activities: [SyncActivityItem] = []
    @Published public var deadlines: [BrightspaceDeadlineItem] = []
    @Published public var grades: [BrightspaceGradeItem] = []
    @Published public var localFiles: [LocalCourseFileItem] = []

    @Published public var selectedCourseFilter: String = "ALL"
    @Published public var lastSyncDate: Date? = nil

    // Filter & Search States
    @Published public var showPastDeadlines: Bool = false
    @Published public var selectedDeadlineKind: String = "ALL"
    @Published public var deadlineSearchQuery: String = ""

    @Published public var selectedFileCategory: String = "ALL"
    @Published public var fileSearchQuery: String = ""

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
        didSet {
            saveCourses()
            refreshLocalFilesIndex()
        }
    }

    // Session Cookie Inputs
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

        // 1. Instant Synchronous Cache Hydration (0ms Startup Latency)
        let persisted = BrightspaceSyncEngine.loadCachedStateSynchronously()
        self.lastSyncDate = persisted.lastSuccessfulSync
        self.deadlines = persisted.deadlines
        self.grades = persisted.grades
        if persisted.recentActivity.isEmpty {
            self.activities = Self.defaultSeedActivities(rootPath: self.rootDirectoryPath)
        } else {
            self.activities = persisted.recentActivity
        }

        // 2. Scan Local Files Asynchronously (Non-blocking)
        refreshLocalFilesIndex()

        // 3. Detached Non-blocking Background Sync
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.triggerManualSync()
        }
    }

    public var uniqueEnabledCourseCodes: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for c in courses where c.isEnabled {
            if !seen.contains(c.courseCode) {
                seen.insert(c.courseCode)
                result.append(c.courseCode)
            }
        }
        return result
    }

    public func refreshLocalFilesIndex() {
        let currentCourses = self.courses
        Task.detached(priority: .userInitiated) {
            let scanned = LocalFileManager.shared.scanAllLocalCourseFiles(courses: currentCourses)
            await MainActor.run {
                self.localFiles = scanned
            }
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

        // 1. Fast-path: query existing persistent cookie store directly without spinning up WKWebView (<5ms)
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
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
            return (v1, v2, pairs.joined(separator: "; "))
        }

        // 2. Slow-path fallback: if cookies were not present in store, load a lightweight webview
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 10, height: 10), configuration: config)
        self.warmupWebView = wv
        defer { self.warmupWebView = nil }

        let targetURLString = brightspaceURL.hasSuffix("/") ? "\(brightspaceURL)d2l/home" : "\(brightspaceURL)/d2l/home"
        if let url = URL(string: targetURLString) {
            wv.load(URLRequest(url: url))
        }

        // Poll for up to 1.5 seconds in 100ms intervals (returns the millisecond cookies appear)
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(100))
            let currentCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
            var slowS1: String?
            var slowS2: String?
            var slowPairs: [String] = []
            for c in currentCookies where c.domain.localizedCaseInsensitiveContains("brightspace") {
                slowPairs.append("\(c.name)=\(c.value)")
                if c.name == "d2lSessionVal" && !c.value.isEmpty { slowS1 = c.value }
                else if c.name == "d2lSecureSessionVal" && !c.value.isEmpty { slowS2 = c.value }
            }
            if let v1 = slowS1, let v2 = slowS2 {
                return (v1, v2, slowPairs.joined(separator: "; "))
            }
        }

        return nil
    }

    // MARK: - Filtered Collections for Each Workspace Section

    public var upcomingDeadlinesCount: Int {
        let cutoff = Date().addingTimeInterval(-3600 * 6)
        return deadlines.filter { item in
            guard let d = item.effectiveDate else { return false }
            return d >= cutoff
        }.count
    }

    public var urgentDeadlinesWithin48Hours: [BrightspaceDeadlineItem] {
        let now = Date()
        let limit = now.addingTimeInterval(3600 * 48)
        return deadlines
            .filter { item in
                guard let d = item.effectiveDate else { return false }
                return d >= now.addingTimeInterval(-1800) && d <= limit
            }
            .sorted { ($0.effectiveDate ?? .distantFuture) < ($1.effectiveDate ?? .distantFuture) }
    }

    public var filteredDeadlines: [BrightspaceDeadlineItem] {
        let now = Date()
        return deadlines
            .filter { item in
                if selectedCourseFilter != "ALL" && item.courseCode != selectedCourseFilter {
                    return false
                }
                if selectedDeadlineKind != "ALL" && item.kind.rawValue != selectedDeadlineKind {
                    return false
                }
                if !showPastDeadlines {
                    if let d = item.effectiveDate {
                        if d < now.addingTimeInterval(-3600 * 12) { return false }
                    } else {
                        return false
                    }
                }
                if !deadlineSearchQuery.isEmpty {
                    let q = deadlineSearchQuery.lowercased()
                    return item.title.lowercased().contains(q) || item.courseCode.lowercased().contains(q)
                }
                return true
            }
            .sorted { a, b in
                switch (a.effectiveDate, b.effectiveDate) {
                case let (d1?, d2?):
                    return showPastDeadlines ? (d1 > d2) : (d1 < d2)
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.title < b.title
                }
            }
    }

    public var filteredLocalFiles: [LocalCourseFileItem] {
        localFiles.filter { item in
            if selectedCourseFilter != "ALL" && item.courseCode != selectedCourseFilter {
                return false
            }
            if selectedFileCategory == "PDF" && item.fileExtension != "pdf" && item.fileExtension != "pptx" {
                return false
            }
            if selectedFileCategory == "ANNOUNCEMENTS" && !item.moduleName.localizedCaseInsensitiveContains("Announcement") {
                return false
            }
            if selectedFileCategory == "LABS" && !item.moduleName.localizedCaseInsensitiveContains("Lab") && !item.fileName.localizedCaseInsensitiveContains("lab") && item.fileExtension != "c" && item.fileExtension != "py" {
                return false
            }
            if !fileSearchQuery.isEmpty {
                let q = fileSearchQuery.lowercased()
                return item.fileName.lowercased().contains(q) ||
                    item.moduleName.lowercased().contains(q) ||
                    item.courseCode.lowercased().contains(q)
            }
            return true
        }
    }

    public var filteredGradesByCourse: [(courseCode: String, items: [BrightspaceGradeItem])] {
        let codes = selectedCourseFilter == "ALL" ? uniqueEnabledCourseCodes : [selectedCourseFilter]
        var groups: [(String, [BrightspaceGradeItem])] = []
        for code in codes {
            let matching = grades.filter { $0.courseCode == code }
            if !matching.isEmpty {
                groups.append((code, matching))
            }
        }
        return groups
    }

    public var cumulativeGPASummary: CumulativeGPASummary? {
        let groups = filteredGradesByCourse
        guard !groups.isEmpty else { return nil }

        var standings: [CourseStandingInfo] = []
        for g in groups {
            if let st = calculateCourseStanding(courseCode: g.courseCode, items: g.items) {
                standings.append(st)
            }
        }

        guard !standings.isEmpty else { return nil }

        // Filter for courses with numeric grading (uOttawa Senate excludes non-numerical S/NS from GPA calculations)
        let numeric = standings.filter { !$0.isSatisfactoryOnly }
        let target = numeric.isEmpty ? standings : numeric

        let avg10 = target.map(\.gradePoint10).reduce(0, +) / Double(target.count)
        let avg4 = target.map(\.gradePoint4).reduce(0, +) / Double(target.count)
        let avgPct = target.map(\.percentage).reduce(0, +) / Double(target.count)
        let standing = academicStanding(for: avg10)

        return CumulativeGPASummary(
            cgpa10: avg10,
            cgpa4: avg4,
            averagePercentage: avgPct,
            letterGrade: letterGrade(for: avgPct),
            standingTitle: standing.title,
            standingColor: standing.color,
            gradedCoursesCount: target.count,
            totalCoursesEvaluated: standings.count,
            courseStandings: standings
        )
    }

    public var filteredActivities: [SyncActivityItem] {
        if selectedCourseFilter == "ALL" {
            return activities
        }
        return activities.filter { $0.courseCode == selectedCourseFilter }
    }

    // MARK: - Actions

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

            if !isSessionAlive {
                if let recovered = await self.hydrateFromWebKitCookieStore(purgeExistingD2L: false) {
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

            let newState = await engine.currentState()
            self.activities = updated
            self.deadlines = newState.deadlines
            self.grades = newState.grades
            self.refreshLocalFilesIndex()

            if self.syncState == .synced {
                self.lastSyncDate = newState.lastSuccessfulSync ?? Date()
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
            refreshLocalFilesIndex()
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


// MARK: - Academic Helper Functions

public func courseColor(for code: String) -> Color {
    let palette: [Color] = [.cyan, .blue, .purple, .mint, .orange, .indigo, .teal]
    let sum = code.uppercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
}

public func gradeColor(for pct: Double) -> Color {
    if pct >= 85 { return .green }
    if pct >= 70 { return .cyan }
    if pct >= 55 { return .orange }
    return .red
}

public func letterGrade(for pct: Double) -> String {
    switch pct {
    case 90...: return "A+"
    case 85..<90: return "A"
    case 80..<85: return "A-"
    case 75..<80: return "B+"
    case 70..<75: return "B"
    case 65..<70: return "C+"
    case 60..<65: return "C"
    case 55..<60: return "D+"
    case 50..<55: return "D"
    default: return "F"
    }
}

// MARK: - uOttawa & Standard GPA / CGPA Conversions

/// Converts percentage to uOttawa official 10.0 scale grade points (Senate regulations)
public func gradePoint10(for pct: Double) -> Double {
    switch pct {
    case 90...: return 10.0
    case 85..<90: return 9.0
    case 80..<85: return 8.0
    case 75..<80: return 7.0
    case 70..<75: return 6.0
    case 65..<70: return 5.0
    case 60..<65: return 4.0
    case 55..<60: return 3.0
    case 50..<55: return 2.0
    case 40..<50: return 1.0
    default: return 0.0
    }
}

/// Converts percentage to North American 4.0 scale grade points
public func gradePoint4(for pct: Double) -> Double {
    switch pct {
    case 90...: return 4.0
    case 85..<90: return 3.9
    case 80..<85: return 3.7
    case 75..<80: return 3.3
    case 70..<75: return 3.0
    case 65..<70: return 2.3
    case 60..<65: return 2.0
    case 55..<60: return 1.3
    case 50..<55: return 1.0
    default: return 0.0
    }
}

/// Academic standing assessment based on uOttawa 10.0 CGPA
public func academicStanding(for cgpa10: Double) -> (title: String, color: Color) {
    switch cgpa10 {
    case 8.5...:
        return ("Dean's Honour List (Exceptional Standing)", .green)
    case 7.0..<8.5:
        return ("Good Academic Standing (Very Good)", .cyan)
    case 5.0..<7.0:
        return ("Satisfactory Academic Standing", .mint)
    case 4.0..<5.0:
        return ("Academic Warning", .orange)
    default:
        return ("Academic Probation Alert", .red)
    }
}

// MARK: - Course Standing & Cumulative GPA Models

public struct CourseStandingInfo: Identifiable, Sendable {
    public var id: String { courseCode }
    public let courseCode: String
    public let percentage: Double
    public let earnedPts: Double
    public let totalPts: Double
    public let letterGrade: String
    public let gradePoint10: Double
    public let gradePoint4: Double
    public let isSatisfactoryOnly: Bool

    public init(
        courseCode: String,
        percentage: Double,
        earnedPts: Double,
        totalPts: Double,
        letterGrade: String,
        gradePoint10: Double,
        gradePoint4: Double,
        isSatisfactoryOnly: Bool = false
    ) {
        self.courseCode = courseCode
        self.percentage = percentage
        self.earnedPts = earnedPts
        self.totalPts = totalPts
        self.letterGrade = letterGrade
        self.gradePoint10 = gradePoint10
        self.gradePoint4 = gradePoint4
        self.isSatisfactoryOnly = isSatisfactoryOnly
    }
}

public struct CumulativeGPASummary: Sendable {
    public let cgpa10: Double
    public let cgpa4: Double
    public let averagePercentage: Double
    public let letterGrade: String
    public let standingTitle: String
    public let standingColor: Color
    public let gradedCoursesCount: Int
    public let totalCoursesEvaluated: Int
    public let courseStandings: [CourseStandingInfo]

    public init(
        cgpa10: Double,
        cgpa4: Double,
        averagePercentage: Double,
        letterGrade: String,
        standingTitle: String,
        standingColor: Color,
        gradedCoursesCount: Int,
        totalCoursesEvaluated: Int,
        courseStandings: [CourseStandingInfo]
    ) {
        self.cgpa10 = cgpa10
        self.cgpa4 = cgpa4
        self.averagePercentage = averagePercentage
        self.letterGrade = letterGrade
        self.standingTitle = standingTitle
        self.standingColor = standingColor
        self.gradedCoursesCount = gradedCoursesCount
        self.totalCoursesEvaluated = totalCoursesEvaluated
        self.courseStandings = courseStandings
    }
}

/// Evaluates course standing metrics (percentage, pts, letter, grade points) from Brightspace items
public func calculateCourseStanding(courseCode: String, items: [BrightspaceGradeItem]) -> CourseStandingInfo? {
    guard !items.isEmpty else { return nil }

    let isSOnly = items.allSatisfy { item in
        let disp = item.displayedGrade.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return disp == "S" || disp == "P"
    }

    let cats = items.filter { $0.isCategory }
    let validCats = cats.filter { ($0.weightedDenominator ?? 0) > 0 }
    var percentage: Double? = nil
    var earnedPts = 0.0
    var totalPts = 100.0

    if !validCats.isEmpty {
        let num = validCats.compactMap(\.weightedNumerator).reduce(0, +)
        let den = validCats.compactMap(\.weightedDenominator).reduce(0, +)
        if den > 0 {
            percentage = (num / den) * 100.0
            earnedPts = num
            totalPts = den
        }
    }

    if percentage == nil && courseCode.uppercased() == "MAT1320" {
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
            percentage = (weightedAcc / totalEvalWeight) * 100.0
            earnedPts = weightedAcc
            totalPts = totalEvalWeight
        }
    }

    if percentage == nil {
        let nonCat = items.filter { !$0.isCategory && ($0.pointsDenominator ?? 0) > 0 }
        let pcts = nonCat.compactMap(\.percentage)
        if !pcts.isEmpty {
            let avg = pcts.reduce(0, +) / Double(pcts.count)
            percentage = avg
            earnedPts = avg
            totalPts = 100.0
        }
    }

    guard let pct = percentage else { return nil }

    return CourseStandingInfo(
        courseCode: courseCode,
        percentage: pct,
        earnedPts: earnedPts,
        totalPts: totalPts,
        letterGrade: letterGrade(for: pct),
        gradePoint10: gradePoint10(for: pct),
        gradePoint4: gradePoint4(for: pct),
        isSatisfactoryOnly: isSOnly
    )
}
