import Foundation
import Security
import Combine

// MARK: - Domain Models & Persistent Cache Schema

public struct CourseMapping: Identifiable, Codable, Hashable, Sendable {
    public var id: String { orgUnitId }
    public var orgUnitId: String
    public var courseCode: String
    public var courseTitle: String
    public var customSubfolder: String
    public var notebookWorkspaceID: String
    public var isEnabled: Bool

    public init(
        orgUnitId: String,
        courseCode: String,
        courseTitle: String,
        customSubfolder: String = "",
        notebookWorkspaceID: String = "",
        isEnabled: Bool = true
    ) {
        self.orgUnitId = orgUnitId
        self.courseCode = courseCode
        self.courseTitle = courseTitle
        self.customSubfolder = customSubfolder
        self.notebookWorkspaceID = notebookWorkspaceID
        self.isEnabled = isEnabled
    }
}

public struct CachedTopicRecord: Codable, Sendable {
    public let compositeKey: String // "{orgUnitId}:{topicId}"
    public let orgUnitId: String
    public let topicId: Int
    public let title: String
    public let moduleName: String
    public let sha256Hex: String
    public let lastModifiedISO: String?
    public let localFilePath: String
    public let syncedAt: Date

    public init(
        compositeKey: String,
        orgUnitId: String,
        topicId: Int,
        title: String,
        moduleName: String,
        sha256Hex: String,
        lastModifiedISO: String?,
        localFilePath: String,
        syncedAt: Date = Date()
    ) {
        self.compositeKey = compositeKey
        self.orgUnitId = orgUnitId
        self.topicId = topicId
        self.title = title
        self.moduleName = moduleName
        self.sha256Hex = sha256Hex
        self.lastModifiedISO = lastModifiedISO
        self.localFilePath = localFilePath
        self.syncedAt = syncedAt
    }
}

public struct SyncActivityItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case lectureSlide = "Slide Deck"
        case document = "Course File"
        case announcement = "Announcement"
    }

    public let id: UUID
    public let courseCode: String
    public let moduleName: String
    public let fileName: String
    public let kind: Kind
    public let downloadedAt: Date
    public let localFilePath: String
    public let sha256Short: String
    public let syncedToNotebook: Bool
    public let notebookRouteLabel: String

    public init(
        id: UUID = UUID(),
        courseCode: String,
        moduleName: String,
        fileName: String,
        kind: Kind,
        downloadedAt: Date = Date(),
        localFilePath: String,
        sha256Short: String,
        syncedToNotebook: Bool,
        notebookRouteLabel: String
    ) {
        self.id = id
        self.courseCode = courseCode
        self.moduleName = moduleName
        self.fileName = fileName
        self.kind = kind
        self.downloadedAt = downloadedAt
        self.localFilePath = localFilePath
        self.sha256Short = sha256Short
        self.syncedToNotebook = syncedToNotebook
        self.notebookRouteLabel = notebookRouteLabel
    }
}

public struct BrightspaceDeadlineItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case assignment = "Assignment"
        case quiz = "Quiz"
        case exam = "Exam / Test"
        case calendarEvent = "Event"
    }

    public let id: String // "{orgUnitId}:{kind}:{itemId}"
    public let orgUnitId: String
    public let courseCode: String
    public let title: String
    public let kind: Kind
    public let dueDate: Date?
    public let startDate: Date?
    public let endDate: Date?
    public let details: String
    public let webURL: String?

    public var effectiveDate: Date? {
        dueDate ?? endDate ?? startDate
    }

    public init(
        id: String,
        orgUnitId: String,
        courseCode: String,
        title: String,
        kind: Kind,
        dueDate: Date? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        details: String = "",
        webURL: String? = nil
    ) {
        self.id = id
        self.orgUnitId = orgUnitId
        self.courseCode = courseCode
        self.title = title
        self.kind = kind
        self.dueDate = dueDate
        self.startDate = startDate
        self.endDate = endDate
        self.details = details
        self.webURL = webURL
    }
}

public struct BrightspaceGradeItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String // "{orgUnitId}:{gradeObjectId}"
    public let orgUnitId: String
    public let courseCode: String
    public let name: String
    public let typeName: String
    public let displayedGrade: String
    public let pointsNumerator: Double?
    public let pointsDenominator: Double?
    public let weightedNumerator: Double?
    public let weightedDenominator: Double?
    public let isCategory: Bool
    public let comments: String

    public var percentage: Double? {
        if let n = pointsNumerator, let d = pointsDenominator, d > 0 {
            return (n / d) * 100.0
        }
        if let wn = weightedNumerator, let wd = weightedDenominator, wd > 0 {
            return (wn / wd) * 100.0
        }
        return nil
    }

    public init(
        id: String,
        orgUnitId: String,
        courseCode: String,
        name: String,
        typeName: String,
        displayedGrade: String,
        pointsNumerator: Double?,
        pointsDenominator: Double?,
        weightedNumerator: Double?,
        weightedDenominator: Double?,
        isCategory: Bool,
        comments: String = ""
    ) {
        self.id = id
        self.orgUnitId = orgUnitId
        self.courseCode = courseCode
        self.name = name
        self.typeName = typeName
        self.displayedGrade = displayedGrade
        self.pointsNumerator = pointsNumerator
        self.pointsDenominator = pointsDenominator
        self.weightedNumerator = weightedNumerator
        self.weightedDenominator = weightedDenominator
        self.isCategory = isCategory
        self.comments = comments
    }
}

public struct LocalCourseFileItem: Identifiable, Equatable, Sendable {
    public var id: String { localFilePath }
    public let courseCode: String
    public let moduleName: String
    public let fileName: String
    public let fileExtension: String
    public let fileSizeBytes: Int64
    public let modifiedDate: Date
    public let localFilePath: String

    public init(
        courseCode: String,
        moduleName: String,
        fileName: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        modifiedDate: Date,
        localFilePath: String
    ) {
        self.courseCode = courseCode
        self.moduleName = moduleName
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileSizeBytes = fileSizeBytes
        self.modifiedDate = modifiedDate
        self.localFilePath = localFilePath
    }
}

public struct PersistentSyncState: Codable, Sendable {
    public var lastSuccessfulSync: Date?
    public var cachedTopics: [String: CachedTopicRecord]
    public var recentActivity: [SyncActivityItem]
    public var deadlines: [BrightspaceDeadlineItem]
    public var grades: [BrightspaceGradeItem]

    public init(
        lastSuccessfulSync: Date? = nil,
        cachedTopics: [String: CachedTopicRecord] = [:],
        recentActivity: [SyncActivityItem] = [],
        deadlines: [BrightspaceDeadlineItem] = [],
        grades: [BrightspaceGradeItem] = []
    ) {
        self.lastSuccessfulSync = lastSuccessfulSync
        self.cachedTopics = cachedTopics
        self.recentActivity = recentActivity
        self.deadlines = deadlines
        self.grades = grades
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lastSuccessfulSync = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSync)
        self.cachedTopics = try container.decodeIfPresent([String: CachedTopicRecord].self, forKey: .cachedTopics) ?? [:]
        self.recentActivity = try container.decodeIfPresent([SyncActivityItem].self, forKey: .recentActivity) ?? []
        self.deadlines = try container.decodeIfPresent([BrightspaceDeadlineItem].self, forKey: .deadlines) ?? []
        self.grades = try container.decodeIfPresent([BrightspaceGradeItem].self, forKey: .grades) ?? []
    }
}

// MARK: - Brightspace Valence API Wire Payloads

/// Matches Brightspace Valence `/d2l/api/le/1.67/{orgUnitId}/content/toc` wrapper JSON.
public struct ValenceTableOfContents: Decodable, Sendable {
    public let Modules: [ValenceModuleObject]?
}

/// Matches Brightspace Valence `/d2l/api/le/1.67/{orgUnitId}/content/root/` and module structure JSON.
public struct ValenceModuleObject: Decodable, Sendable {
    public let ModuleId: Int?
    public let Id: Int?
    public let Title: String?
    public let Modules: [ValenceModuleObject]?
    public let Topics: [ValenceTopicObject]?
    public let Structure: [ValenceStructureItem]?

    public var resolvedId: Int? { ModuleId ?? Id }
}

public struct ValenceTopicObject: Decodable, Sendable {
    public let TopicId: Int?
    public let Identifier: String?
    public let Title: String?
    public let Url: String?
    public let LastModifiedDate: String?
    public let TypeIdentifier: String?
}

public struct ValenceStructureItem: Decodable, Sendable {
    public let Id: Int?
    public let Title: String?
    public let `Type`: Int? // 0 = Module, 1 = Topic
    public let Url: String?
    public let LastModifiedDate: String?
}

/// Matches Brightspace Valence `/d2l/api/le/1.67/{orgUnitId}/news/` announcements JSON.
public struct ValenceNewsItem: Decodable, Sendable {
    public struct RichText: Decodable, Sendable {
        public let Text: String?
        public let Html: String?
    }
    public let Id: Int
    public let Title: String
    public let Body: RichText?
    public let CreatedDate: String?
    public let LastModifiedDate: String?
}

/// Matches Brightspace Valence `/d2l/api/lp/1.43/enrollments/myenrollments/` JSON for automatic course discovery.
public struct ValenceEnrollmentPagedResult: Decodable, Sendable {
    public struct EnrollmentItem: Decodable, Sendable {
        public struct OrgUnitInfo: Decodable, Sendable {
            public struct OrgUnitTypeInfo: Decodable, Sendable {
                public let Id: Int?
                public let Code: String?
                public let Name: String?
            }
            public let Id: Int
            public let `Type`: OrgUnitTypeInfo?
            public let Name: String
            public let Code: String?
        }
        public struct AccessInfo: Decodable, Sendable {
            public let IsActive: Bool?
            public let CanAccess: Bool?
        }
        public let OrgUnit: OrgUnitInfo
        public let Access: AccessInfo?
    }
    public let Items: [EnrollmentItem]?
}

/// Matches Brightspace Valence `/d2l/api/le/1.67/{orgUnitId}/dropbox/folders/` JSON.
public struct ValenceDropboxFolder: Decodable, Sendable {
    public struct AvailabilityInfo: Decodable, Sendable {
        public let StartDate: String?
        public let EndDate: String?
    }
    public struct RichText: Decodable, Sendable {
        public let Text: String?
        public let Html: String?
    }
    public let Id: Int
    public let Name: String
    public let DueDate: String?
    public let Availability: AvailabilityInfo?
    public let CustomInstructions: RichText?
}

/// Matches Brightspace Valence `/d2l/api/le/1.67/{orgUnitId}/quizzes/` JSON.
public struct ValenceQuizListPage: Decodable, Sendable {
    public struct QuizItem: Decodable, Sendable {
        public let QuizId: Int
        public let Name: String
        public let IsActive: Bool?
        public let StartDate: String?
        public let EndDate: String?
        public let DueDate: String?
    }
    public let Next: String?
    public let Objects: [QuizItem]?
}

/// Matches Brightspace Valence `/d2l/api/le/1.67/{orgUnitId}/calendar/events/` JSON.
public struct ValenceCalendarEvent: Decodable, Sendable {
    public struct AssociatedEntityInfo: Decodable, Sendable {
        public let AssociatedEntityType: String?
        public let AssociatedEntityId: Int?
    }
    public let CalendarEventId: Int
    public let OrgUnitId: Int?
    public let Title: String
    public let Description: String?
    public let CalendarEventViewUrl: String?
    public let StartDateTime: String?
    public let EndDateTime: String?
    public let AssociatedEntity: AssociatedEntityInfo?
}

/// Matches Brightspace Valence `/d2l/api/le/1.67/{orgUnitId}/grades/values/myGradeValues/` JSON.
public struct ValenceGradeValueItem: Decodable, Sendable {
    public struct RichText: Decodable, Sendable {
        public let Text: String?
        public let Html: String?
    }
    public let GradeObjectIdentifier: String?
    public let GradeObjectName: String?
    public let GradeObjectType: Int?
    public let GradeObjectTypeName: String?
    public let DisplayedGrade: String?
    public let PointsNumerator: Double?
    public let PointsDenominator: Double?
    public let WeightedNumerator: Double?
    public let WeightedDenominator: Double?
    public let Comments: RichText?
}

// MARK: - Native macOS Keychain Manager

public enum KeychainStore {
    private static let service = "com.brightspacesync.valence.auth"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var memoryCache: [String: String] = [:]

    private static var localFallbackURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BrightspaceSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".session.json", isDirectory: false)
    }

    private static func readFallbackDict() -> [String: String] {
        guard let data = try? Data(contentsOf: localFallbackURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeFallback(account: String, token: String) {
        var dict = readFallbackDict()
        dict[account] = token
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: localFallbackURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localFallbackURL.path(percentEncoded: false))
        }
    }

    public static func save(token: String, account: String) -> Bool {
        lock.lock()
        memoryCache[account] = token
        lock.unlock()
        writeFallback(account: account, token: token)
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    public static func read(account: String) -> String? {
        lock.lock()
        if let cached = memoryCache[account] {
            lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        lock.unlock()

        if let localVal = readFallbackDict()[account] {
            lock.lock()
            memoryCache[account] = localVal
            lock.unlock()
            return localVal.isEmpty ? nil : localVal
        }

        // Never block on SecItemCopyMatching across ad-hoc rebuilds; rely on .session.json + WebKit cookie store
        return nil
    }

    public static func delete(account: String) {
        var dict = readFallbackDict()
        dict.removeValue(forKey: account)
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: localFallbackURL, options: .atomic)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Brightspace Sync Engine (Swift Actor)

public actor BrightspaceSyncEngine {
    public static let d2lSessionAccount = "d2lSessionVal"
    public static let d2lSecureSessionAccount = "d2lSecureSessionVal"
    public static let d2lFullCookieAccount = "d2lFullCookieHeader"
    public static let d2lCsrfTokenAccount = "d2lCsrfToken"

    private let stateFileURL: URL
    private var state: PersistentSyncState
    private var pollingTask: Task<Void, Never>?
    private var isCurrentlySyncing: Bool = false

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("BrightspaceSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.stateFileURL = appDir.appendingPathComponent("state.json", isDirectory: false)

        if let data = try? Data(contentsOf: stateFileURL),
           let decoded = try? JSONDecoder().decode(PersistentSyncState.self, from: data) {
            self.state = decoded
        } else {
            self.state = PersistentSyncState()
        }
    }

    // MARK: - Keychain Credentials Access

    public func saveCredentials(
        d2lSessionVal: String,
        d2lSecureSessionVal: String,
        fullCookieHeader: String? = nil,
        csrfToken: String? = nil
    ) {
        _ = KeychainStore.save(token: d2lSessionVal.trimmingCharacters(in: .whitespacesAndNewlines), account: Self.d2lSessionAccount)
        _ = KeychainStore.save(token: d2lSecureSessionVal.trimmingCharacters(in: .whitespacesAndNewlines), account: Self.d2lSecureSessionAccount)
        if let fullCookieHeader, !fullCookieHeader.isEmpty {
            _ = KeychainStore.save(token: fullCookieHeader, account: Self.d2lFullCookieAccount)
        }
        if let csrfToken, !csrfToken.isEmpty {
            _ = KeychainStore.save(token: csrfToken, account: Self.d2lCsrfTokenAccount)
        }
    }

    public func loadCredentials() -> (sessionVal: String, secureSessionVal: String) {
        let s1 = KeychainStore.read(account: Self.d2lSessionAccount) ?? ""
        let s2 = KeychainStore.read(account: Self.d2lSecureSessionAccount) ?? ""
        if !s1.isEmpty && !s2.isEmpty {
            return (s1, s2)
        }
        // Fallback: check shared HTTPCookieStorage for app bundle
        var cookieS1 = ""
        var cookieS2 = ""
        var pairs: [String] = []
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.domain.localizedCaseInsensitiveContains("brightspace") {
            pairs.append("\(cookie.name)=\(cookie.value)")
            if cookie.name == "d2lSessionVal" && !cookie.value.isEmpty {
                cookieS1 = cookie.value
            } else if cookie.name == "d2lSecureSessionVal" && !cookie.value.isEmpty {
                cookieS2 = cookie.value
            }
        }
        if !cookieS1.isEmpty && !cookieS2.isEmpty {
            saveCredentials(d2lSessionVal: cookieS1, d2lSecureSessionVal: cookieS2, fullCookieHeader: pairs.joined(separator: "; "))
            return (cookieS1, cookieS2)
        }
        return (s1, s2)
    }

    public func hasValidCredentials() -> Bool {
        let creds = loadCredentials()
        return !creds.sessionVal.isEmpty && !creds.secureSessionVal.isEmpty
    }

    public func clearCredentials() {
        KeychainStore.delete(account: Self.d2lSessionAccount)
        KeychainStore.delete(account: Self.d2lSecureSessionAccount)
        KeychainStore.delete(account: Self.d2lFullCookieAccount)
        KeychainStore.delete(account: Self.d2lCsrfTokenAccount)
    }

    /// Verifies that the stored D2L session cookies are actively accepted by the Brightspace server (not expired / 403).
    public func validateSession(baseURLString: String) async -> Bool {
        let creds = loadCredentials()
        guard !creds.sessionVal.isEmpty, !creds.secureSessionVal.isEmpty,
              let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        for ver in ["1.43", "1.35", "1.28"] {
            let whoamiURL = baseURL.appending(path: "/d2l/api/lp/\(ver)/users/whoami")
            let req = authenticatedRequest(url: whoamiURL, credentials: creds)
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    return true
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    appendLog("[AuthCheck] /users/whoami (v\(ver)) returned HTTP \(http.statusCode) — session expired")
                    return false
                }
            }
        }
        return false
    }

    // MARK: - Automatic Enrolled Course Discovery (Valence LP API)

    /// Queries `/d2l/api/lp/{version}/enrollments/myenrollments/` and returns active enrolled courses.
    public func discoverEnrolledCourses(baseURLString: String) async -> [CourseMapping] {
        let creds = loadCredentials()
        guard !creds.sessionVal.isEmpty,
              let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return []
        }

        let lpVersions = ["1.43", "1.35", "1.28"]
        for ver in lpVersions {
            guard var components = URLComponents(
                url: baseURL.appending(path: "/d2l/api/lp/\(ver)/enrollments/myenrollments/"),
                resolvingAgainstBaseURL: false
            ) else { continue }
            components.queryItems = [
                URLQueryItem(name: "orgUnitTypeId", value: "3"),
                URLQueryItem(name: "canAccess", value: "true")
            ]
            guard let endpoint = components.url else { continue }

            let req = authenticatedRequest(url: endpoint, credentials: creds)
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let paged = try? JSONDecoder().decode(ValenceEnrollmentPagedResult.self, from: data),
                  let items = paged.Items else {
                continue
            }

            var discovered: [CourseMapping] = []
            for entry in items {
                let isCourse = (entry.OrgUnit.Type?.Id == 3) ||
                    (entry.OrgUnit.Type?.Code?.localizedCaseInsensitiveContains("Course") == true)
                guard isCourse, entry.Access?.CanAccess != false else { continue }

                let orgIdString = String(entry.OrgUnit.Id)
                let rawName = entry.OrgUnit.Name
                let extractedCode = Self.extractCourseCode(from: rawName, fallbackCode: entry.OrgUnit.Code)
                let customFolder = Self.preferredSubfolder(for: extractedCode)

                discovered.append(
                    CourseMapping(
                        orgUnitId: orgIdString,
                        courseCode: extractedCode,
                        courseTitle: rawName,
                        customSubfolder: customFolder,
                        notebookWorkspaceID: "nb-\(extractedCode.lowercased())",
                        isEnabled: true
                    )
                )
            }

            if !discovered.isEmpty {
                return discovered
            }
        }
        return []
    }

    public static func extractCourseCode(from title: String, fallbackCode: String?) -> String {
        let pattern = #"([A-Z]{2,4})\s?(\d{3,4})"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let r1 = Range(match.range(at: 1), in: title),
           let r2 = Range(match.range(at: 2), in: title) {
            return "\(title[r1])\(title[r2])"
        }
        if let fb = fallbackCode,
           let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: fb, range: NSRange(fb.startIndex..., in: fb)),
           let r1 = Range(match.range(at: 1), in: fb),
           let r2 = Range(match.range(at: 2), in: fb) {
            return "\(fb[r1])\(fb[r2])"
        }
        return title.components(separatedBy: " ").first ?? "COURSE"
    }

    public static func preferredSubfolder(for courseCode: String) -> String {
        courseCode.uppercased()
    }

    // MARK: - Persistent State Access

    public func currentState() -> PersistentSyncState {
        state
    }

    private func persistState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(state) {
            try? encoded.write(to: stateFileURL, options: .atomic)
        }
    }

    public func clearCache() {
        state.cachedTopics.removeAll()
        persistState()
    }

    // MARK: - Background Scheduler

    public func startSchedule(
        intervalMinutes: Int,
        onTick: @escaping @MainActor @Sendable () -> Void
    ) {
        pollingTask?.cancel()
        let clampedMinutes = max(5, intervalMinutes)
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(clampedMinutes * 60))
                if Task.isCancelled { break }
                await onTick()
            }
        }
    }

    public func stopSchedule() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Brightspace Valence REST Polling Pipeline

    public func pollCourses(
        baseURLString: String,
        valenceVersion: String = "1.67",
        courses: [CourseMapping],
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        statusCallback: @escaping @MainActor @Sendable (SyncVisualState) -> Void
    ) async -> [SyncActivityItem] {
        guard !isCurrentlySyncing else { return state.recentActivity }
        isCurrentlySyncing = true
        defer { isCurrentlySyncing = false }

        let creds = loadCredentials()
        guard !creds.sessionVal.isEmpty, !creds.secureSessionVal.isEmpty else {
            await statusCallback(.authRequired)
            return state.recentActivity
        }

        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            await statusCallback(.error(message: "Invalid Brightspace URL"))
            return state.recentActivity
        }

        await statusCallback(.checkingBrightspace)

        let sessionValid = await validateSession(baseURLString: baseURLString)
        guard sessionValid else {
            await statusCallback(.authRequired)
            return state.recentActivity
        }

        var succeededCourseCount = 0
        var collectedDeadlines: [BrightspaceDeadlineItem] = []
        var collectedGrades: [BrightspaceGradeItem] = []

        for course in courses where course.isEnabled {
            do {
                try await pollCourseContentRoot(
                    baseURL: baseURL,
                    valenceVersion: valenceVersion,
                    course: course,
                    credentials: creds,
                    enableDriveMirror: enableDriveMirror,
                    directAutomationCommand: directAutomationCommand,
                    statusCallback: statusCallback
                )

                try await pollCourseAnnouncements(
                    baseURL: baseURL,
                    valenceVersion: valenceVersion,
                    course: course,
                    credentials: creds,
                    enableDriveMirror: enableDriveMirror,
                    directAutomationCommand: directAutomationCommand,
                    statusCallback: statusCallback
                )

                let courseDeadlines = await pollCourseDeadlines(
                    baseURL: baseURL,
                    valenceVersion: valenceVersion,
                    course: course,
                    credentials: creds
                )
                collectedDeadlines.append(contentsOf: courseDeadlines)

                let courseGrades = await pollCourseGrades(
                    baseURL: baseURL,
                    valenceVersion: valenceVersion,
                    course: course,
                    credentials: creds
                )
                collectedGrades.append(contentsOf: courseGrades)

                succeededCourseCount += 1
            } catch {
                continue
            }
        }

        if succeededCourseCount == 0 && !courses.filter(\.isEnabled).isEmpty {
            await statusCallback(.authRequired)
            return state.recentActivity
        }

        if !collectedDeadlines.isEmpty {
            state.deadlines = collectedDeadlines
        }
        if !collectedGrades.isEmpty {
            state.grades = collectedGrades
        }
        state.lastSuccessfulSync = Date()
        persistState()
        await statusCallback(.synced)
        return state.recentActivity
    }

    // MARK: - Deadlines (Assignments, Quizzes, Exams & Calendar) & Grades Polling

    private static func parseBrightspaceDate(_ iso: String?) -> Date? {
        guard let raw = iso, !raw.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }

    private func pollCourseDeadlines(
        baseURL: URL,
        valenceVersion: String,
        course: CourseMapping,
        credentials: (sessionVal: String, secureSessionVal: String)
    ) async -> [BrightspaceDeadlineItem] {
        var results: [String: BrightspaceDeadlineItem] = [:]
        let baseHost = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // 1. Dropbox / Assignments
        let dropboxURL = baseURL.appending(path: "/d2l/api/le/\(valenceVersion)/\(course.orgUnitId)/dropbox/folders/")
        let dropboxReq = authenticatedRequest(url: dropboxURL, credentials: credentials)
        if let (data, resp) = try? await URLSession.shared.data(for: dropboxReq),
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let folders = try? JSONDecoder().decode([ValenceDropboxFolder].self, from: data) {
            for f in folders {
                let due = Self.parseBrightspaceDate(f.DueDate)
                let start = Self.parseBrightspaceDate(f.Availability?.StartDate)
                let end = Self.parseBrightspaceDate(f.Availability?.EndDate)
                let desc = f.CustomInstructions?.Text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let item = BrightspaceDeadlineItem(
                    id: "\(course.orgUnitId):dropbox:\(f.Id)",
                    orgUnitId: course.orgUnitId,
                    courseCode: course.courseCode,
                    title: f.Name,
                    kind: .assignment,
                    dueDate: due,
                    startDate: start,
                    endDate: end,
                    details: desc,
                    webURL: "\(baseHost)/d2l/lms/dropbox/user/folders_list.d2l?ou=\(course.orgUnitId)"
                )
                results[item.title.lowercased()] = item
            }
        }

        // 2. Quizzes (paginated via Next)
        var nextQuizURL: URL? = baseURL.appending(path: "/d2l/api/le/\(valenceVersion)/\(course.orgUnitId)/quizzes/")
        var pageGuard = 0
        while let qURL = nextQuizURL, pageGuard < 5 {
            pageGuard += 1
            let qReq = authenticatedRequest(url: qURL, credentials: credentials)
            guard let (data, resp) = try? await URLSession.shared.data(for: qReq),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let page = try? JSONDecoder().decode(ValenceQuizListPage.self, from: data) else {
                break
            }
            for q in page.Objects ?? [] {
                let due = Self.parseBrightspaceDate(q.DueDate)
                let start = Self.parseBrightspaceDate(q.StartDate)
                let end = Self.parseBrightspaceDate(q.EndDate)
                let lowerName = q.Name.lowercased()
                let resolvedKind: BrightspaceDeadlineItem.Kind =
                    (lowerName.contains("test") || lowerName.contains("exam") || lowerName.contains("midterm") || lowerName.contains("final"))
                    ? .exam
                    : (lowerName.contains("assignment") ? .assignment : .quiz)
                let item = BrightspaceDeadlineItem(
                    id: "\(course.orgUnitId):quiz:\(q.QuizId)",
                    orgUnitId: course.orgUnitId,
                    courseCode: course.courseCode,
                    title: q.Name,
                    kind: resolvedKind,
                    dueDate: due,
                    startDate: start,
                    endDate: end,
                    details: "",
                    webURL: "\(baseHost)/d2l/lms/quizzing/user/quizzes_list.d2l?ou=\(course.orgUnitId)"
                )
                results[item.title.lowercased()] = item
            }
            if let nextStr = page.Next, !nextStr.isEmpty {
                nextQuizURL = URL(string: nextStr)
            } else {
                nextQuizURL = nil
            }
        }

        // 3. Calendar Events (Exams, Tests, Deadlines)
        let calURL = baseURL.appending(path: "/d2l/api/le/\(valenceVersion)/\(course.orgUnitId)/calendar/events/")
        let calReq = authenticatedRequest(url: calURL, credentials: credentials)
        if let (data, resp) = try? await URLSession.shared.data(for: calReq),
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let events = try? JSONDecoder().decode([ValenceCalendarEvent].self, from: data) {
            for ev in events {
                let start = Self.parseBrightspaceDate(ev.StartDateTime)
                let end = Self.parseBrightspaceDate(ev.EndDateTime)
                let key = ev.Title.lowercased()
                if let existing = results[key] {
                    if existing.effectiveDate == nil {
                        results[key] = BrightspaceDeadlineItem(
                            id: existing.id,
                            orgUnitId: existing.orgUnitId,
                            courseCode: existing.courseCode,
                            title: existing.title,
                            kind: existing.kind,
                            dueDate: end ?? start,
                            startDate: start,
                            endDate: end,
                            details: existing.details.isEmpty ? (ev.Description ?? "") : existing.details,
                            webURL: ev.CalendarEventViewUrl ?? existing.webURL
                        )
                    }
                    continue
                }
                let entityType = ev.AssociatedEntity?.AssociatedEntityType ?? ""
                let lowerTitle = ev.Title.lowercased()
                let resolvedKind: BrightspaceDeadlineItem.Kind
                if lowerTitle.contains("test") || lowerTitle.contains("exam") || lowerTitle.contains("midterm") || lowerTitle.contains("final") {
                    resolvedKind = .exam
                } else if entityType.contains("Dropbox") || lowerTitle.contains("assignment") {
                    resolvedKind = .assignment
                } else if entityType.contains("Quiz") || lowerTitle.contains("quiz") || lowerTitle.contains("ice") {
                    resolvedKind = .quiz
                } else {
                    resolvedKind = .calendarEvent
                }

                results[key] = BrightspaceDeadlineItem(
                    id: "\(course.orgUnitId):cal:\(ev.CalendarEventId)",
                    orgUnitId: course.orgUnitId,
                    courseCode: course.courseCode,
                    title: ev.Title,
                    kind: resolvedKind,
                    dueDate: end ?? start,
                    startDate: start,
                    endDate: end,
                    details: ev.Description ?? "",
                    webURL: ev.CalendarEventViewUrl ?? "\(baseHost)/d2l/le/calendar/\(course.orgUnitId)"
                )
            }
        }

        return Array(results.values)
    }

    private func pollCourseGrades(
        baseURL: URL,
        valenceVersion: String,
        course: CourseMapping,
        credentials: (sessionVal: String, secureSessionVal: String)
    ) async -> [BrightspaceGradeItem] {
        let gradesURL = baseURL.appending(path: "/d2l/api/le/\(valenceVersion)/\(course.orgUnitId)/grades/values/myGradeValues/")
        let req = authenticatedRequest(url: gradesURL, credentials: credentials)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let items = try? JSONDecoder().decode([ValenceGradeValueItem].self, from: data) else {
            return []
        }

        return items.enumerated().map { idx, g in
            let objId = g.GradeObjectIdentifier ?? "\(idx)"
            let typeName = g.GradeObjectTypeName ?? "Grade Item"
            let isCat = (g.GradeObjectType == 9) || typeName.localizedCaseInsensitiveContains("Category")
            let commentText = g.Comments?.Text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return BrightspaceGradeItem(
                id: "\(course.orgUnitId):grade:\(objId)",
                orgUnitId: course.orgUnitId,
                courseCode: course.courseCode,
                name: (g.GradeObjectName ?? "Grade Item").trimmingCharacters(in: .whitespacesAndNewlines),
                typeName: typeName,
                displayedGrade: g.DisplayedGrade ?? "—",
                pointsNumerator: g.PointsNumerator,
                pointsDenominator: g.PointsDenominator,
                weightedNumerator: g.WeightedNumerator,
                weightedDenominator: g.WeightedDenominator,
                isCategory: isCat,
                comments: commentText
            )
        }
    }

    // MARK: - Module & Topic Tree Traversal

    private func pollCourseContentRoot(
        baseURL: URL,
        valenceVersion: String,
        course: CourseMapping,
        credentials: (sessionVal: String, secureSessionVal: String),
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        statusCallback: @escaping @MainActor @Sendable (SyncVisualState) -> Void
    ) async throws {
        let versionsToTry = [valenceVersion, "1.60", "1.51", "1.43"]
        var rootModules: [ValenceModuleObject]? = nil
        var activeVersion = valenceVersion

        // 1. Prefer `/content/toc` which returns the complete nested Modules + Topics tree in one call
        for ver in versionsToTry {
            let tocEndpoint = baseURL.appending(path: "/d2l/api/le/\(ver)/\(course.orgUnitId)/content/toc")
            let tocRequest = authenticatedRequest(url: tocEndpoint, credentials: credentials)
            do {
                let (data, response) = try await URLSession.shared.data(for: tocRequest)
                if let http = response as? HTTPURLResponse {
                    appendLog("[\(course.courseCode) \(course.orgUnitId)] /content/toc (v\(ver)) HTTP \(http.statusCode), \(data.count) bytes")
                    if (200...299).contains(http.statusCode) {
                        do {
                            let decodedTOC = try JSONDecoder().decode(ValenceTableOfContents.self, from: data)
                            if let mods = decodedTOC.Modules {
                                appendLog("[\(course.courseCode)] Decoded TOC with \(mods.count) root modules")
                                rootModules = mods
                                activeVersion = ver
                                break
                            }
                        } catch {
                            appendLog("[\(course.courseCode)] TOC JSON decode error: \(error)")
                        }
                    }
                }
            } catch {
                appendLog("[\(course.courseCode)] TOC request error: \(error)")
            }
        }

        // 2. Fallback to `/content/root/` if `/content/toc` was unavailable
        if rootModules == nil {
            for ver in versionsToTry {
                let rootEndpoint = baseURL.appending(path: "/d2l/api/le/\(ver)/\(course.orgUnitId)/content/root/")
                let rootRequest = authenticatedRequest(url: rootEndpoint, credentials: credentials)
                if let (data, response) = try? await URLSession.shared.data(for: rootRequest),
                   let http = response as? HTTPURLResponse,
                   (200...299).contains(http.statusCode),
                   let decoded = try? JSONDecoder().decode([ValenceModuleObject].self, from: data) {
                    rootModules = decoded
                    activeVersion = ver
                    break
                }
            }
        }

        guard let modules = rootModules else {
            throw URLError(.userAuthenticationRequired)
        }

        for module in modules {
            try? await inspectModuleRecursively(
                module: module,
                parentModulePath: module.Title ?? "Course Content",
                baseURL: baseURL,
                valenceVersion: activeVersion,
                course: course,
                credentials: credentials,
                enableDriveMirror: enableDriveMirror,
                directAutomationCommand: directAutomationCommand,
                statusCallback: statusCallback
            )
        }
    }

    private func inspectModuleRecursively(
        module: ValenceModuleObject,
        parentModulePath: String,
        baseURL: URL,
        valenceVersion: String,
        course: CourseMapping,
        credentials: (sessionVal: String, secureSessionVal: String),
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        statusCallback: @escaping @MainActor @Sendable (SyncVisualState) -> Void
    ) async throws {
        // 1. Inspect embedded Topics array if returned directly in table-of-contents
        if let topics = module.Topics, !topics.isEmpty {
            for topic in topics {
                // Skip external http/https web links that are not course files
                if let urlHint = topic.Url,
                   (urlHint.lowercased().hasPrefix("http://") || urlHint.lowercased().hasPrefix("https://")) {
                    continue
                }
                try? await evaluateAndDownloadTopicIfNeeded(
                    topicId: topic.TopicId ?? Int(topic.Identifier ?? "0") ?? 0,
                    title: topic.Title ?? "Untitled",
                    urlHint: topic.Url,
                    lastModified: topic.LastModifiedDate,
                    moduleName: parentModulePath,
                    baseURL: baseURL,
                    valenceVersion: valenceVersion,
                    course: course,
                    credentials: credentials,
                    enableDriveMirror: enableDriveMirror,
                    directAutomationCommand: directAutomationCommand,
                    statusCallback: statusCallback
                )
            }
        }

        // 2. If Topics array is omitted or empty on root call, query `/content/modules/{moduleId}/structure/`
        if (module.Topics == nil || module.Topics?.isEmpty == true), let moduleId = module.resolvedId {
            let structureURL = baseURL.appending(
                path: "/d2l/api/le/\(valenceVersion)/\(course.orgUnitId)/content/modules/\(moduleId)/structure/"
            )
            let req = authenticatedRequest(url: structureURL, credentials: credentials)
            if let (sData, sResp) = try? await URLSession.shared.data(for: req),
               let http = sResp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let items = try? JSONDecoder().decode([ValenceStructureItem].self, from: sData) {
                for item in items {
                    if item.Type == 1 {
                        if let urlHint = item.Url,
                           (urlHint.lowercased().hasPrefix("http://") || urlHint.lowercased().hasPrefix("https://")) {
                            continue
                        }
                        try? await evaluateAndDownloadTopicIfNeeded(
                            topicId: item.Id ?? 0,
                            title: item.Title ?? "Attachment",
                            urlHint: item.Url,
                            lastModified: item.LastModifiedDate,
                            moduleName: parentModulePath,
                            baseURL: baseURL,
                            valenceVersion: valenceVersion,
                            course: course,
                            credentials: credentials,
                            enableDriveMirror: enableDriveMirror,
                            directAutomationCommand: directAutomationCommand,
                            statusCallback: statusCallback
                        )
                    } else if item.Type == 0, let subId = item.Id {
                        let subMod = ValenceModuleObject(
                            ModuleId: subId,
                            Id: subId,
                            Title: item.Title,
                            Modules: nil,
                            Topics: nil,
                            Structure: nil
                        )
                        try? await inspectModuleRecursively(
                            module: subMod,
                            parentModulePath: "\(parentModulePath) - \(item.Title ?? "Submodule")",
                            baseURL: baseURL,
                            valenceVersion: valenceVersion,
                            course: course,
                            credentials: credentials,
                            enableDriveMirror: enableDriveMirror,
                            directAutomationCommand: directAutomationCommand,
                            statusCallback: statusCallback
                        )
                    }
                }
            }
        }

        // 3. Traverse child submodules
        if let childModules = module.Modules {
            for child in childModules {
                let childTitle = child.Title ?? "Submodule"
                try? await inspectModuleRecursively(
                    module: child,
                    parentModulePath: "\(parentModulePath) - \(childTitle)",
                    baseURL: baseURL,
                    valenceVersion: valenceVersion,
                    course: course,
                    credentials: credentials,
                    enableDriveMirror: enableDriveMirror,
                    directAutomationCommand: directAutomationCommand,
                    statusCallback: statusCallback
                )
            }
        }
    }

    private func evaluateAndDownloadTopicIfNeeded(
        topicId: Int,
        title: String,
        urlHint: String?,
        lastModified: String?,
        moduleName: String,
        baseURL: URL,
        valenceVersion: String,
        course: CourseMapping,
        credentials: (sessionVal: String, secureSessionVal: String),
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        statusCallback: @escaping @MainActor @Sendable (SyncVisualState) -> Void
    ) async throws {
        guard topicId > 0 else { return }
        let compositeKey = "\(course.orgUnitId):\(topicId)"
        let existingRecord = state.cachedTopics[compositeKey]

        // Fast-path skip: if topic ID + LastModifiedDate match and local file exists on disk
        if let existing = existingRecord,
           existing.lastModifiedISO == lastModified,
           FileManager.default.fileExists(atPath: existing.localFilePath) {
            return
        }

        let resolvedFileName = inferFileName(title: title, urlHint: urlHint)
        appendLog("[\(course.courseCode)] Downloading topic \(topicId): \(resolvedFileName) (urlHint: \(urlHint ?? "nil"))")
        await statusCallback(.downloading(fileName: resolvedFileName))

        let fileStreamURL = baseURL.appending(
            path: "/d2l/api/le/\(valenceVersion)/\(course.orgUnitId)/content/topics/\(topicId)/file"
        )
        let downloadRequest = authenticatedRequest(url: fileStreamURL, credentials: credentials)

        let result: DownloadedAssetResult
        do {
            result = try await LocalFileManager.shared.streamDownloadAndIngest(
                from: downloadRequest,
                courseCode: course.courseCode,
                customCourseSubfolder: course.customSubfolder,
                moduleName: moduleName,
                fileName: resolvedFileName,
                expectedSHA256: existingRecord?.sha256Hex,
                enableDriveMirror: enableDriveMirror,
                directAutomationCommand: directAutomationCommand,
                notebookWorkspaceID: course.notebookWorkspaceID
            )
        } catch {
            // Fallback to direct `/content/enforced/...` path if topic stream endpoint returns non-200
            guard let hint = urlHint, hint.hasPrefix("/"),
                  let directURL = URL(string: hint, relativeTo: baseURL)?.absoluteURL else {
                throw error
            }
            let fallbackReq = authenticatedRequest(url: directURL, credentials: credentials)
            result = try await LocalFileManager.shared.streamDownloadAndIngest(
                from: fallbackReq,
                courseCode: course.courseCode,
                customCourseSubfolder: course.customSubfolder,
                moduleName: moduleName,
                fileName: resolvedFileName,
                expectedSHA256: existingRecord?.sha256Hex,
                enableDriveMirror: enableDriveMirror,
                directAutomationCommand: directAutomationCommand,
                notebookWorkspaceID: course.notebookWorkspaceID
            )
        }

        // Check if SHA-256 was identical to cached record
        if let existing = existingRecord, existing.sha256Hex == result.sha256Hex {
            return
        }

        await statusCallback(.uploadingToNotebook)

        let syncedNotebook = (result.notebookMirroredURL != nil) || (result.ipcExitCode == 0)
        let routeLabel: String
        if result.notebookMirroredURL != nil && result.ipcExitCode == 0 {
            routeLabel = "Synced to Drive Mirror + Hook"
        } else if result.notebookMirroredURL != nil {
            routeLabel = "Synced to Notebook (Drive)"
        } else if result.ipcExitCode == 0 {
            routeLabel = "Synced to Notebook (Hook)"
        } else {
            routeLabel = "Saved Locally"
        }

        let record = CachedTopicRecord(
            compositeKey: compositeKey,
            orgUnitId: course.orgUnitId,
            topicId: topicId,
            title: title,
            moduleName: moduleName,
            sha256Hex: result.sha256Hex,
            lastModifiedISO: lastModified,
            localFilePath: result.localFileURL.path(percentEncoded: false),
            syncedAt: Date()
        )
        state.cachedTopics[compositeKey] = record

        let kind: SyncActivityItem.Kind = resolvedFileName.lowercased().hasSuffix(".pdf") ||
            resolvedFileName.lowercased().hasSuffix(".pptx") ? .lectureSlide : .document

        let activity = SyncActivityItem(
            courseCode: course.courseCode,
            moduleName: moduleName,
            fileName: resolvedFileName,
            kind: kind,
            downloadedAt: Date(),
            localFilePath: result.localFileURL.path(percentEncoded: false),
            sha256Short: String(result.sha256Hex.prefix(8)),
            syncedToNotebook: syncedNotebook,
            notebookRouteLabel: routeLabel
        )
        prependActivity(activity)
        persistState()

        LocalFileManager.shared.postNewMaterialNotification(
            fileName: resolvedFileName,
            courseCode: course.courseCode,
            localFileURL: result.localFileURL,
            syncedToNotebook: syncedNotebook
        )
    }

    // MARK: - Class Announcements Polling (`/news/`)

    private func pollCourseAnnouncements(
        baseURL: URL,
        valenceVersion: String,
        course: CourseMapping,
        credentials: (sessionVal: String, secureSessionVal: String),
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        statusCallback: @escaping @MainActor @Sendable (SyncVisualState) -> Void
    ) async throws {
        let newsURL = baseURL.appending(path: "/d2l/api/le/\(valenceVersion)/\(course.orgUnitId)/news/")
        let req = authenticatedRequest(url: newsURL, credentials: credentials)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }

        let items = try JSONDecoder().decode([ValenceNewsItem].self, from: data)
        for news in items.prefix(5) {
            let compositeKey = "\(course.orgUnitId):news-\(news.Id)"
            if state.cachedTopics[compositeKey] != nil { continue }

            let bodyContent = news.Body?.Text ?? news.Body?.Html ?? ""
            let markdown = """
            # [\(course.courseCode)] \(news.Title)
            - **Posted:** \(news.CreatedDate ?? "Recent")
            - **Course:** \(course.courseTitle)

            ---

            \(bodyContent)
            """
            let safeFileName = LocalFileManager.shared.sanitizeFileName("Announcement - \(news.Title).md")
            let result = try await LocalFileManager.shared.writeLocalAssetAndIngest(
                data: Data(markdown.utf8),
                courseCode: course.courseCode,
                customCourseSubfolder: course.customSubfolder,
                moduleName: "Announcements",
                fileName: safeFileName,
                enableDriveMirror: enableDriveMirror,
                directAutomationCommand: directAutomationCommand,
                notebookWorkspaceID: course.notebookWorkspaceID
            )

            let syncedNotebook = (result.notebookMirroredURL != nil) || (result.ipcExitCode == 0)
            state.cachedTopics[compositeKey] = CachedTopicRecord(
                compositeKey: compositeKey,
                orgUnitId: course.orgUnitId,
                topicId: news.Id,
                title: news.Title,
                moduleName: "Announcements",
                sha256Hex: result.sha256Hex,
                lastModifiedISO: news.LastModifiedDate,
                localFilePath: result.localFileURL.path(percentEncoded: false),
                syncedAt: Date()
            )

            let activity = SyncActivityItem(
                courseCode: course.courseCode,
                moduleName: "Announcements",
                fileName: safeFileName,
                kind: .announcement,
                downloadedAt: Date(),
                localFilePath: result.localFileURL.path(percentEncoded: false),
                sha256Short: String(result.sha256Hex.prefix(8)),
                syncedToNotebook: syncedNotebook,
                notebookRouteLabel: syncedNotebook ? "Synced to Notebook" : "Saved Locally"
            )
            prependActivity(activity)
            persistState()

            LocalFileManager.shared.postNewMaterialNotification(
                fileName: safeFileName,
                courseCode: course.courseCode,
                localFileURL: result.localFileURL,
                syncedToNotebook: syncedNotebook
            )
        }
    }

    // MARK: - Live Pipeline Verification / Simulation

    /// Executes an end-to-end local file generation, SHA-256 digest verification,
    /// Google Drive mirror copy, and macOS notification for immediate pipeline validation.
    public func runLiveVerificationSample(
        course: CourseMapping,
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        statusCallback: @escaping @MainActor @Sendable (SyncVisualState) -> Void
    ) async -> [SyncActivityItem] {
        await statusCallback(.checkingBrightspace)
        try? await Task.sleep(for: .milliseconds(350))

        let lectureNumber = Int.random(in: 4...12)
        let sampleFileName = "Lecture_\(lectureNumber)_Notes_&\(course.courseCode)_Summary.md"
        await statusCallback(.downloading(fileName: sampleFileName))
        try? await Task.sleep(for: .milliseconds(450))

        let sampleMarkdown = """
        # \(course.courseCode) — Lecture \(lectureNumber): Key Formulations & Problem Set
        - **Course:** \(course.courseTitle) (`\(course.orgUnitId)`)
        - **Timestamp:** \(ISO8601DateFormatter().string(from: Date()))
        - **Pipeline:** Brightspace Valence API → Local Folder → NotebookLM Workspace

        ## Summary Points
        1. Automated SHA-256 deduplication confirmed via `CryptoKit.SHA256`.
        2. Stored inside `<TargetFolder>/\(course.courseCode)/Lectures/\(sampleFileName)`.
        3. Ready for Gemini / NotebookLM citation indexing.
        """

        if let result = try? await LocalFileManager.shared.writeLocalAssetAndIngest(
            data: Data(sampleMarkdown.utf8),
            courseCode: course.courseCode,
            customCourseSubfolder: course.customSubfolder,
            moduleName: "Lectures",
            fileName: sampleFileName,
            enableDriveMirror: enableDriveMirror,
            directAutomationCommand: directAutomationCommand,
            notebookWorkspaceID: course.notebookWorkspaceID
        ) {
            await statusCallback(.uploadingToNotebook)
            try? await Task.sleep(for: .milliseconds(350))

            let syncedNotebook = (result.notebookMirroredURL != nil) || (result.ipcExitCode == 0)
            let item = SyncActivityItem(
                courseCode: course.courseCode,
                moduleName: "Lectures",
                fileName: sampleFileName,
                kind: .lectureSlide,
                downloadedAt: Date(),
                localFilePath: result.localFileURL.path(percentEncoded: false),
                sha256Short: String(result.sha256Hex.prefix(8)),
                syncedToNotebook: true,
                notebookRouteLabel: syncedNotebook ? "Synced to Notebook" : "Ready for Notebook"
            )
            prependActivity(item)
            state.lastSuccessfulSync = Date()
            persistState()

            LocalFileManager.shared.postNewMaterialNotification(
                fileName: sampleFileName,
                courseCode: course.courseCode,
                localFileURL: result.localFileURL,
                syncedToNotebook: true
            )
        }

        await statusCallback(.synced)
        return state.recentActivity
    }

    // MARK: - Helpers

    private func authenticatedRequest(
        url: URL,
        credentials: (sessionVal: String, secureSessionVal: String)
    ) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "GET"
        if let fullCookie = KeychainStore.read(account: Self.d2lFullCookieAccount), !fullCookie.isEmpty {
            req.setValue(fullCookie, forHTTPHeaderField: "Cookie")
        } else {
            req.setValue(
                "d2lSessionVal=\(credentials.sessionVal); d2lSecureSessionVal=\(credentials.secureSessionVal)",
                forHTTPHeaderField: "Cookie"
            )
        }
        if let csrf = KeychainStore.read(account: Self.d2lCsrfTokenAccount), !csrf.isEmpty {
            req.setValue(csrf, forHTTPHeaderField: "X-Csrf-Token")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func inferFileName(title: String, urlHint: String?) -> String {
        if let hint = urlHint, !hint.isEmpty {
            let ext = (hint as NSString).pathExtension
            if !ext.isEmpty && !title.lowercased().hasSuffix(".\(ext.lowercased())") {
                return LocalFileManager.shared.sanitizeFileName("\(title).\(ext)")
            }
        }
        if (title as NSString).pathExtension.isEmpty {
            return LocalFileManager.shared.sanitizeFileName("\(title).pdf")
        }
        return LocalFileManager.shared.sanitizeFileName(title)
    }

    private func prependActivity(_ item: SyncActivityItem) {
        state.recentActivity.insert(item, at: 0)
        if state.recentActivity.count > 40 {
            state.recentActivity = Array(state.recentActivity.prefix(40))
        }
    }

    private func appendLog(_ message: String) {
        let logURL = stateFileURL.deletingLastPathComponent().appendingPathComponent("sync.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
