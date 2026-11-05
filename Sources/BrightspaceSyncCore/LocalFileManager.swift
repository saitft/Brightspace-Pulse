import Foundation
import AppKit
import CryptoKit
import UserNotifications

// MARK: - Downloaded Asset Outcome

public struct DownloadedAssetResult: Sendable {
    public let localFileURL: URL
    public let sha256Hex: String
    public let byteCount: Int64
    public let notebookMirroredURL: URL?
    public let ipcExitCode: Int32?
}

// MARK: - Local File & Ingestion Coordinator

public final class LocalFileManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = LocalFileManager()

    private let rootBookmarkKey = "BrightspaceSync.RootFolderBookmark"
    private let rootPathDisplayKey = "BrightspaceSync.RootFolderPathDisplay"
    private let driveMirrorBookmarkKey = "BrightspaceSync.DriveMirrorBookmark"
    private let driveMirrorPathDisplayKey = "BrightspaceSync.DriveMirrorPathDisplay"

    public static let notificationCategoryID = "COURSE_MATERIAL_DOWNLOADED"
    public static let revealInFinderActionID = "REVEAL_IN_FINDER_ACTION"

    private let fileCoordinatorQueue = DispatchQueue(label: "com.brightspacesync.filemanager", qos: .utility)
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private override init() {
        super.init()
        configureNotificationsIfBundled()
    }

    // MARK: - Security-Scoped Bookmarks (Root Target Folder & Google Drive Mirror)

    /// Persists a user-selected directory URL as a macOS security-scoped bookmark.
    @discardableResult
    public func saveSecurityScopedBookmark(for url: URL, isDriveMirror: Bool = false) throws -> Data {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let bookmarkKey = isDriveMirror ? driveMirrorBookmarkKey : rootBookmarkKey
        let displayKey = isDriveMirror ? driveMirrorPathDisplayKey : rootPathDisplayKey

        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: displayKey)
        return bookmarkData
    }

    /// Resolves the stored security-scoped bookmark, refreshing it if marked stale.
    public func resolveRootDirectoryURL() -> URL {
        if let resolved = resolveBookmark(bookmarkKey: rootBookmarkKey, displayKey: rootPathDisplayKey) {
            return resolved
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Downloads/BrightspacePulse", isDirectory: true)
    }

    /// Resolves the optional Google Drive / NotebookLM local mirror folder.
    public func resolveDriveMirrorDirectoryURL() -> URL? {
        if let resolved = resolveBookmark(bookmarkKey: driveMirrorBookmarkKey, displayKey: driveMirrorPathDisplayKey) {
            return resolved
        }
        if let savedPath = UserDefaults.standard.string(forKey: driveMirrorPathDisplayKey),
           !savedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (savedPath as NSString).expandingTildeInPath, isDirectory: true)
        }
        let defaultMirror = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/BrightspacePulse/NotebookLM_Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: defaultMirror, withIntermediateDirectories: true)
        return defaultMirror
    }

    public func setCustomDriveMirrorPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: driveMirrorPathDisplayKey)
    }

    private func resolveBookmark(bookmarkKey: String, displayKey: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            if let rawPath = UserDefaults.standard.string(forKey: displayKey), !rawPath.isEmpty {
                return URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath, isDirectory: true)
            }
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                _ = try? saveSecurityScopedBookmark(for: url, isDriveMirror: bookmarkKey == driveMirrorBookmarkKey)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Stream Download + Structured Folder Hierarchy + SHA-256 Digest

    /// Streams a remote Brightspace file to `<TargetFolder>/<CourseCode>/<ModuleName>/<FileName>`,
    /// verifies its SHA-256 digest against an optional known hash, and runs the NotebookLM ingestion layer.
    public func streamDownloadAndIngest(
        from request: URLRequest,
        courseCode: String,
        customCourseSubfolder: String?,
        moduleName: String,
        fileName: String,
        expectedSHA256: String?,
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        notebookWorkspaceID: String?
    ) async throws -> DownloadedAssetResult {
        let (tempFileURL, response) = try await urlSession.download(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: tempFileURL)
            throw URLError(.badServerResponse)
        }

        // Compute streaming SHA-256 hash on the downloaded temporary file
        let (sha256Hex, byteCount) = try computeSHA256AndSize(for: tempFileURL)

        let rootURL = resolveRootDirectoryURL()
        let didAccessRoot = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessRoot { rootURL.stopAccessingSecurityScopedResource() }
        }

        let cleanCourseFolder = sanitizePathComponent(customCourseSubfolder?.isEmpty == false ? customCourseSubfolder! : courseCode)
        let cleanModuleFolder = sanitizePathComponent(moduleName.isEmpty ? "General" : moduleName)
        let cleanFileName = sanitizeFileName(fileName)

        let destinationDir = rootURL
            .appendingPathComponent(cleanCourseFolder, isDirectory: true)
            .appendingPathComponent(cleanModuleFolder, isDirectory: true)

        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let destinationFileURL = destinationDir.appendingPathComponent(cleanFileName, isDirectory: false)

        // If identical SHA-256 already exists on disk, skip overwrite and remove temp file
        if let expected = expectedSHA256,
           expected.lowercased() == sha256Hex.lowercased(),
           FileManager.default.fileExists(atPath: destinationFileURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: tempFileURL)
            return DownloadedAssetResult(
                localFileURL: destinationFileURL,
                sha256Hex: sha256Hex,
                byteCount: byteCount,
                notebookMirroredURL: nil,
                ipcExitCode: nil
            )
        }

        if FileManager.default.fileExists(atPath: destinationFileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationFileURL)
        }
        try FileManager.default.moveItem(at: tempFileURL, to: destinationFileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destinationFileURL.path(percentEncoded: false))

        // Route A: Google Drive Mirror / NotebookLM Source Folder
        var mirroredURL: URL? = nil
        if enableDriveMirror, let mirrorRoot = resolveDriveMirrorDirectoryURL() {
            let didAccessMirror = mirrorRoot.startAccessingSecurityScopedResource()
            defer {
                if didAccessMirror { mirrorRoot.stopAccessingSecurityScopedResource() }
            }

            let cleanCode = sanitizePathComponent(courseCode)
            let courseNotebookDir = mirrorRoot
                .appendingPathComponent("\(cleanCode)_Notebook", isDirectory: true)
            try? FileManager.default.createDirectory(at: courseNotebookDir, withIntermediateDirectories: true)

            let targetMirrorFile = courseNotebookDir.appendingPathComponent(cleanFileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: targetMirrorFile.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: targetMirrorFile)
            }
            do {
                try FileManager.default.copyItem(at: destinationFileURL, to: targetMirrorFile)
                mirroredURL = targetMirrorFile
                updateNativeNotebookIndex(
                    in: courseNotebookDir,
                    courseCode: cleanCode,
                    moduleName: cleanModuleFolder,
                    fileName: cleanFileName,
                    sha256Hex: sha256Hex,
                    notebookWorkspaceID: notebookWorkspaceID
                )
            } catch {
                // Keep non-fatal if mirror folder is temporarily unavailable
            }
        }

        // Route B: Direct Automation Script / IPC Hook
        var ipcExit: Int32? = nil
        if let command = directAutomationCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            ipcExit = await executeDirectIngestionHook(
                command: command,
                fileURL: destinationFileURL,
                courseCode: courseCode,
                moduleName: moduleName,
                sha256Hex: sha256Hex,
                notebookWorkspaceID: notebookWorkspaceID
            )
        }

        return DownloadedAssetResult(
            localFileURL: destinationFileURL,
            sha256Hex: sha256Hex,
            byteCount: byteCount,
            notebookMirroredURL: mirroredURL,
            ipcExitCode: ipcExit
        )
    }

    /// Writes local simulated or announcement markdown content into the structured course folder
    /// and executes the same NotebookLM ingestion pipeline.
    public func writeLocalAssetAndIngest(
        data: Data,
        courseCode: String,
        customCourseSubfolder: String?,
        moduleName: String,
        fileName: String,
        enableDriveMirror: Bool,
        directAutomationCommand: String?,
        notebookWorkspaceID: String?
    ) async throws -> DownloadedAssetResult {
        let rootURL = resolveRootDirectoryURL()
        let didAccessRoot = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessRoot { rootURL.stopAccessingSecurityScopedResource() }
        }

        let cleanCourseFolder = sanitizePathComponent(customCourseSubfolder?.isEmpty == false ? customCourseSubfolder! : courseCode)
        let cleanModuleFolder = sanitizePathComponent(moduleName.isEmpty ? "General" : moduleName)
        let cleanFileName = sanitizeFileName(fileName)

        let destinationDir = rootURL
            .appendingPathComponent(cleanCourseFolder, isDirectory: true)
            .appendingPathComponent(cleanModuleFolder, isDirectory: true)

        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let destinationFileURL = destinationDir.appendingPathComponent(cleanFileName, isDirectory: false)
        try data.write(to: destinationFileURL, options: .atomic)

        let digest = SHA256.hash(data: data)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        var mirroredURL: URL? = nil
        if enableDriveMirror, let mirrorRoot = resolveDriveMirrorDirectoryURL() {
            let didAccessMirror = mirrorRoot.startAccessingSecurityScopedResource()
            defer {
                if didAccessMirror { mirrorRoot.stopAccessingSecurityScopedResource() }
            }
            let courseNotebookDir = mirrorRoot.appendingPathComponent("\(cleanCourseFolder)_Notebook", isDirectory: true)
            try? FileManager.default.createDirectory(at: courseNotebookDir, withIntermediateDirectories: true)
            let targetMirrorFile = courseNotebookDir.appendingPathComponent(cleanFileName, isDirectory: false)
            try? FileManager.default.removeItem(at: targetMirrorFile)
            try? FileManager.default.copyItem(at: destinationFileURL, to: targetMirrorFile)
            mirroredURL = targetMirrorFile
        }

        var ipcExit: Int32? = nil
        if let command = directAutomationCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            ipcExit = await executeDirectIngestionHook(
                command: command,
                fileURL: destinationFileURL,
                courseCode: courseCode,
                moduleName: moduleName,
                sha256Hex: sha256Hex,
                notebookWorkspaceID: notebookWorkspaceID
            )
        }

        return DownloadedAssetResult(
            localFileURL: destinationFileURL,
            sha256Hex: sha256Hex,
            byteCount: Int64(data.count),
            notebookMirroredURL: mirroredURL,
            ipcExitCode: ipcExit
        )
    }

    // MARK: - Streaming SHA-256 Computation

    public func computeSHA256AndSize(for fileURL: URL) throws -> (String, Int64) {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        var totalBytes: Int64 = 0

        while autoreleasepool(invoking: {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                return false
            }
            hasher.update(data: chunk)
            totalBytes += Int64(chunk.count)
            return true
        }) {}

        let digest = hasher.finalize()
        let hexString = digest.map { String(format: "%02x", $0) }.joined()
        return (hexString, totalBytes)
    }

    // MARK: - Route B: Direct Automation / IPC Execution

    private func executeDirectIngestionHook(
        command: String,
        fileURL: URL,
        courseCode: String,
        moduleName: String,
        sha256Hex: String,
        notebookWorkspaceID: String?
    ) async -> Int32 {
        await withCheckedContinuation { continuation in
            fileCoordinatorQueue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                var env = ProcessInfo.processInfo.environment
                env["BRIGHTSPACE_FILE_PATH"] = fileURL.path(percentEncoded: false)
                env["BRIGHTSPACE_COURSE_CODE"] = courseCode
                env["BRIGHTSPACE_MODULE_NAME"] = moduleName
                env["BRIGHTSPACE_FILE_SHA256"] = sha256Hex
                env["NOTEBOOK_WORKSPACE_ID"] = notebookWorkspaceID ?? ""
                process.environment = env

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }

    // MARK: - Finder Integration

    @MainActor
    public func revealInFinder(url: URL) {
        let rootURL = resolveRootDirectoryURL()
        let didAccess = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { rootURL.stopAccessingSecurityScopedResource() }
        }

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(rootURL)
        }
    }

    @MainActor
    public func openFile(url: URL) {
        let rootURL = resolveRootDirectoryURL()
        let didAccess = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { rootURL.stopAccessingSecurityScopedResource() }
        }
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.open(url)
        } else {
            revealInFinder(url: url)
        }
    }

    @MainActor
    public func openRootStorageFolder() {
        let rootURL = resolveRootDirectoryURL()
        let didAccess = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { rootURL.stopAccessingSecurityScopedResource() }
        }
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(rootURL)
    }

    public func scanAllLocalCourseFiles(courses: [CourseMapping]) -> [LocalCourseFileItem] {
        let rootURL = resolveRootDirectoryURL()
        let didAccess = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { rootURL.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        var results: [LocalCourseFileItem] = []
        var visitedPaths: Set<String> = []

        var folderMap: [(courseCode: String, folderURL: URL)] = []
        for c in courses {
            let sub = c.customSubfolder.isEmpty ? c.courseCode : c.customSubfolder
            let url = rootURL.appendingPathComponent(sanitizePathComponent(sub), isDirectory: true)
            folderMap.append((c.courseCode, url))
            if sub != c.courseCode {
                let altURL = rootURL.appendingPathComponent(sanitizePathComponent(c.courseCode), isDirectory: true)
                folderMap.append((c.courseCode, altURL))
            }
        }

        for (code, courseDir) in folderMap {
            let dirPath = courseDir.path(percentEncoded: false)
            guard !visitedPaths.contains(dirPath), fm.fileExists(atPath: dirPath) else { continue }
            visitedPaths.insert(dirPath)

            guard let enumerator = fm.enumerator(
                at: courseDir,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                      vals.isRegularFile == true else { continue }
                let relComponents = fileURL.pathComponents.dropFirst(courseDir.pathComponents.count)
                let moduleName = relComponents.count > 1 ? relComponents.dropLast().joined(separator: " / ") : "General"
                results.append(
                    LocalCourseFileItem(
                        courseCode: code,
                        moduleName: moduleName,
                        fileName: fileURL.lastPathComponent,
                        fileExtension: fileURL.pathExtension.lowercased(),
                        fileSizeBytes: Int64(vals.fileSize ?? 0),
                        modifiedDate: vals.contentModificationDate ?? Date.distantPast,
                        localFilePath: fileURL.path(percentEncoded: false)
                    )
                )
            }
        }

        return results.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    // MARK: - Rich macOS Notifications (UNUserNotificationCenter)

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private func configureNotificationsIfBundled() {
        guard canUseUserNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let revealAction = UNNotificationAction(
            identifier: Self.revealInFinderActionID,
            title: "Reveal in Finder",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryID,
            actions: [revealAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func postNewMaterialNotification(
        fileName: String,
        courseCode: String,
        localFileURL: URL,
        syncedToNotebook: Bool
    ) {
        guard canUseUserNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "New Course Material"
        let suffix = syncedToNotebook ? " and synced to Notebook." : "."
        content.body = "Downloaded \(fileName) into \(courseCode)\(suffix)"
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategoryID
        content.userInfo = ["filePath": localFileURL.path(percentEncoded: false)]

        let request = UNNotificationRequest(
            identifier: "brightspace-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.revealInFinderActionID ||
            response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let path = response.notification.request.content.userInfo["filePath"] as? String {
            let fileURL = URL(fileURLWithPath: path)
            Task { @MainActor in
                self.revealInFinder(url: fileURL)
            }
        }
        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // MARK: - Path Sanitization Helpers

    private func updateNativeNotebookIndex(
        in notebookDir: URL,
        courseCode: String,
        moduleName: String,
        fileName: String,
        sha256Hex: String,
        notebookWorkspaceID: String?
    ) {
        let indexURL = notebookDir.appendingPathComponent("00_\(courseCode)_NotebookLM_Index.md", isDirectory: false)
        let shortHash = String(sha256Hex.prefix(12))
        var existing = (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
        if existing.isEmpty {
            existing = """
            # \(courseCode) — NotebookLM Source Index
            - **Workspace ID:** `\(notebookWorkspaceID ?? "default")`
            - **Auto-Updated By:** Brightspace Pulse (macOS Menu Bar Utility)

            | Timestamp | Module | File Name | SHA-256 |
            |---|---|---|---|

            """
        }
        guard !existing.contains(shortHash) else { return }
        let ts = ISO8601DateFormatter().string(from: Date())
        existing.append("| \(ts) | \(moduleName) | `\(fileName)` | `\(shortHash)` |\n")
        try? existing.write(to: indexURL, atomically: true, encoding: .utf8)
    }

    public func sanitizePathComponent(_ raw: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = raw
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    public func sanitizeFileName(_ raw: String) -> String {
        let cleaned = sanitizePathComponent(raw)
        return cleaned.hasPrefix(".") ? "file\(cleaned)" : cleaned
    }
}
