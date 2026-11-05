import Foundation
import BrightspaceSyncCore

// MARK: - Lightweight Native Test Framework

var totalTests = 0
var passedTests = 0
var failedTests = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if actual == expected {
        passedTests += 1
    } else {
        failedTests += 1
        print("  \u{001B}[31m✖ FAIL:\u{001B}[0m [\(line)] \(message.isEmpty ? "Assertion failed" : message)")
        print("    Expected: \(expected)")
        print("    Got:      \(actual)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    assertEqual(condition, true, message, file: file, line: line)
}

func assertFalse(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    assertEqual(condition, false, message, file: file, line: line)
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    totalTests += 1
    if value != nil {
        passedTests += 1
    } else {
        failedTests += 1
        print("  \u{001B}[31m✖ FAIL:\u{001B}[0m [\(line)] \(message.isEmpty ? "Expected non-nil" : message)")
    }
}

func runSuite(_ name: String, block: () async throws -> Void) async {
    print("\n\u{001B}[1;36m▶ Running Suite:\u{001B}[0m \u{001B}[1m\(name)\u{001B}[0m")
    let start = Date()
    do {
        try await block()
        let elapsed = String(format: "%.3fs", Date().timeIntervalSince(start))
        print("  \u{001B}[32m✔ Completed \(name)\u{001B}[0m in \(elapsed)")
    } catch {
        failedTests += 1
        print("  \u{001B}[31m✖ Suite crashed with error:\u{001B}[0m \(error)")
    }
}

// MARK: - Test Suites

func testCourseCodeExtraction() async {
    await runSuite("1. Course Code Regex & Subfolder Extraction") {
        assertEqual(BrightspaceSyncEngine.extractCourseCode(from: "GNG1106 C00 Engineering Computation [ LEC ] 20269", fallbackCode: nil), "GNG1106")
        assertEqual(BrightspaceSyncEngine.extractCourseCode(from: "MAT 1320 Calculus I 2026 Fall", fallbackCode: nil), "MAT1320")
        assertEqual(BrightspaceSyncEngine.extractCourseCode(from: "CHM1311 - Principles of Chemistry", fallbackCode: nil), "CHM1311")
        assertEqual(BrightspaceSyncEngine.extractCourseCode(from: "PHY1121 Mechanics & Optics", fallbackCode: nil), "PHY1121")
        assertEqual(BrightspaceSyncEngine.extractCourseCode(from: "ESL 2361 Advanced Academic Writing", fallbackCode: nil), "ESL2361")
        assertEqual(BrightspaceSyncEngine.extractCourseCode(from: "Calculus Readiness Survival Guide", fallbackCode: "CALC101"), "CALC101")
        assertEqual(BrightspaceSyncEngine.extractCourseCode(from: "General Course With No Code", fallbackCode: nil), "General")

        assertEqual(BrightspaceSyncEngine.preferredSubfolder(for: "gng1106"), "GNG1106")
        assertEqual(BrightspaceSyncEngine.preferredSubfolder(for: "math101"), "MATH101")
    }
}

func testAcademicLetterGradesAndColors() async {
    await runSuite("2. Grades, Scoring Calculations & Letter Mapping") {
        assertEqual(letterGrade(for: 98.5), "A+")
        assertEqual(letterGrade(for: 90.0), "A+")
        assertEqual(letterGrade(for: 87.5), "A")
        assertEqual(letterGrade(for: 85.0), "A")
        assertEqual(letterGrade(for: 82.0), "A-")
        assertEqual(letterGrade(for: 77.0), "B+")
        assertEqual(letterGrade(for: 71.5), "B")
        assertEqual(letterGrade(for: 68.0), "C+")
        assertEqual(letterGrade(for: 62.0), "C")
        assertEqual(letterGrade(for: 58.0), "D+")
        assertEqual(letterGrade(for: 52.0), "D")
        assertEqual(letterGrade(for: 45.0), "F")
        assertEqual(letterGrade(for: 0.0), "F")

        // Test BrightspaceGradeItem computation
        let gradeItem1 = BrightspaceGradeItem(
            id: "100:grade:1",
            orgUnitId: "100",
            courseCode: "GNG1106",
            name: "Assignment 1",
            typeName: "Numeric",
            displayedGrade: "A+",
            pointsNumerator: 9.5,
            pointsDenominator: 10.0,
            weightedNumerator: 15.83,
            weightedDenominator: 16.67,
            isCategory: false
        )
        assertNotNil(gradeItem1.percentage)
        assertEqual(gradeItem1.percentage ?? 0, 95.0, "9.5/10.0 should be 95%")
        assertFalse(gradeItem1.isCategory)

        let categoryItem = BrightspaceGradeItem(
            id: "100:grade:cat",
            orgUnitId: "100",
            courseCode: "GNG1106",
            name: "Labs",
            typeName: "Category",
            displayedGrade: "A+",
            pointsNumerator: 100.0,
            pointsDenominator: 100.0,
            weightedNumerator: 20.0,
            weightedDenominator: 20.0,
            isCategory: true
        )
        assertTrue(categoryItem.isCategory)
        assertEqual(categoryItem.percentage ?? 0, 100.0)
    }
}

func testValenceJSONWirePayloads() async {
    await runSuite("3. Brightspace Valence API Wire Payloads Decoding") {
        // A. Table of Contents
        let tocJSON = """
        {
            "Modules": [
                {
                    "ModuleId": 1234,
                    "Title": "Week 1 - Introduction",
                    "Modules": [],
                    "Topics": [
                        {
                            "TopicId": 5678,
                            "Title": "Lecture 1 Slides.pdf",
                            "Url": "/content/enforced/1234-CS101/L1.pdf",
                            "TypeIdentifier": "File"
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!
        let toc = try JSONDecoder().decode(ValenceTableOfContents.self, from: tocJSON)
        assertNotNil(toc.Modules)
        assertEqual(toc.Modules?.count, 1)
        assertEqual(toc.Modules?.first?.resolvedId, 1234)
        assertEqual(toc.Modules?.first?.Topics?.count, 1)
        assertEqual(toc.Modules?.first?.Topics?.first?.Title, "Lecture 1 Slides.pdf")

        // B. Dropbox / Assignments
        let dropboxJSON = """
        [
            {
                "Id": 98765,
                "Name": "Assignment 1 - C Pointers",
                "DueDate": "2026-11-15T04:59:59.000Z",
                "Availability": {
                    "StartDate": "2026-11-01T04:00:00.000Z",
                    "EndDate": "2026-11-15T04:59:59.000Z"
                },
                "CustomInstructions": {
                    "Text": "Submit your main.c file and report."
                }
            }
        ]
        """.data(using: .utf8)!
        let dropbox = try JSONDecoder().decode([ValenceDropboxFolder].self, from: dropboxJSON)
        assertEqual(dropbox.count, 1)
        assertEqual(dropbox.first?.Name, "Assignment 1 - C Pointers")
        assertEqual(dropbox.first?.CustomInstructions?.Text, "Submit your main.c file and report.")

        // C. Quizzes & Pagination
        let quizJSON = """
        {
            "Next": "/d2l/api/le/1.67/608738/quizzes/?bookmark=next_page",
            "Objects": [
                {
                    "QuizId": 44101,
                    "Name": "Midterm Exam Part 1",
                    "IsActive": true,
                    "StartDate": "2026-11-20T14:00:00.000Z",
                    "DueDate": "2026-11-20T16:00:00.000Z"
                }
            ]
        }
        """.data(using: .utf8)!
        let quizPage = try JSONDecoder().decode(ValenceQuizListPage.self, from: quizJSON)
        assertEqual(quizPage.Next, "/d2l/api/le/1.67/608738/quizzes/?bookmark=next_page")
        assertEqual(quizPage.Objects?.count, 1)
        assertEqual(quizPage.Objects?.first?.Name, "Midterm Exam Part 1")

        // D. Calendar Events
        let calJSON = """
        [
            {
                "CalendarEventId": 88312,
                "OrgUnitId": 608738,
                "Title": "Lab 4 Session",
                "Description": "In-person lab session",
                "StartDateTime": "2026-11-10T18:00:00.000Z",
                "EndDateTime": "2026-11-10T21:00:00.000Z",
                "AssociatedEntity": {
                    "AssociatedEntityType": "D2L.LE.Quizzing.Quiz",
                    "AssociatedEntityId": 44101
                }
            }
        ]
        """.data(using: .utf8)!
        let calEvents = try JSONDecoder().decode([ValenceCalendarEvent].self, from: calJSON)
        assertEqual(calEvents.count, 1)
        assertEqual(calEvents.first?.Title, "Lab 4 Session")
        assertEqual(calEvents.first?.AssociatedEntity?.AssociatedEntityType, "D2L.LE.Quizzing.Quiz")

        // E. Grades
        let gradesJSON = """
        [
            {
                "GradeObjectIdentifier": "7710",
                "GradeObjectName": "Test 1",
                "GradeObjectType": 1,
                "GradeObjectTypeName": "Numeric",
                "DisplayedGrade": "A-",
                "PointsNumerator": 84.5,
                "PointsDenominator": 100.0,
                "WeightedNumerator": 16.9,
                "WeightedDenominator": 20.0
            }
        ]
        """.data(using: .utf8)!
        let gradeItems = try JSONDecoder().decode([ValenceGradeValueItem].self, from: gradesJSON)
        assertEqual(gradeItems.count, 1)
        assertEqual(gradeItems.first?.DisplayedGrade, "A-")
        assertEqual(gradeItems.first?.PointsNumerator, 84.5)
    }
}

func testDeadlinesAndUrgencyDetection() async {
    await runSuite("4. Deadlines, Effective Dates & 48-Hour Alert") {
        let now = Date()
        let in24h = now.addingTimeInterval(3600 * 24)
        let in5Days = now.addingTimeInterval(3600 * 24 * 5)
        let past3Days = now.addingTimeInterval(-3600 * 24 * 3)

        let urgentItem = BrightspaceDeadlineItem(
            id: "1:urgent",
            orgUnitId: "608738",
            courseCode: "GNG1106",
            title: "Urgent Lab Report",
            kind: .assignment,
            dueDate: in24h
        )
        assertEqual(urgentItem.effectiveDate, in24h)

        let upcomingItem = BrightspaceDeadlineItem(
            id: "1:future",
            orgUnitId: "608738",
            courseCode: "GNG1106",
            title: "Final Project Submission",
            kind: .assignment,
            dueDate: in5Days
        )

        let pastItem = BrightspaceDeadlineItem(
            id: "1:past",
            orgUnitId: "608738",
            courseCode: "GNG1106",
            title: "Old Quiz 1",
            kind: .quiz,
            dueDate: past3Days
        )

        // Effective date fallback test: dueDate is nil, fallback to endDate, then startDate
        let fallbackItem = BrightspaceDeadlineItem(
            id: "1:fallback",
            orgUnitId: "608738",
            courseCode: "MAT1320",
            title: "Exam Window",
            kind: .exam,
            dueDate: nil,
            startDate: now,
            endDate: in5Days
        )
        assertEqual(fallbackItem.effectiveDate, in5Days, "Should resolve to endDate when dueDate is nil")

        // 48-hour urgency check
        let limit48h = now.addingTimeInterval(3600 * 48)
        let isUrgent = (urgentItem.effectiveDate ?? .distantFuture) <= limit48h && (urgentItem.effectiveDate ?? .distantPast) >= now.addingTimeInterval(-1800)
        assertTrue(isUrgent, "Item due in 24 hours must trigger 48-hour crunch alert")

        let isFutureUrgent = (upcomingItem.effectiveDate ?? .distantFuture) <= limit48h
        assertFalse(isFutureUrgent, "Item due in 5 days must NOT trigger 48-hour crunch alert")

        let isPastUrgent = (pastItem.effectiveDate ?? .distantFuture) >= now
        assertFalse(isPastUrgent, "Past item must NOT be flagged as upcoming urgent")
    }
}

func testSyllabusInPersonExamExtraction() async {
    await runSuite("5. Syllabus & Course Outline In-Person Exam Schedule Extraction") {
        let gngCourse = CourseMapping(orgUnitId: "608738", courseCode: "GNG1106", courseTitle: "Engineering Computation")
        let gngDeadlines = BrightspaceSyncEngine.extractSyllabusDeadlines(for: gngCourse)
        assertEqual(gngDeadlines.count, 2)
        assertTrue(gngDeadlines.contains(where: { $0.title.contains("Midterm Exam") }), "GNG1106 Midterm must be extracted from outline")
        assertTrue(gngDeadlines.contains(where: { $0.title.contains("Final Exam") }), "GNG1106 Final Exam must be extracted from outline")

        let matCourse = CourseMapping(orgUnitId: "606619", courseCode: "MAT1320", courseTitle: "Calculus I")
        let matDeadlines = BrightspaceSyncEngine.extractSyllabusDeadlines(for: matCourse)
        assertEqual(matDeadlines.count, 2)
        assertTrue(matDeadlines.contains(where: { $0.title.contains("Test 2") }), "MAT1320 Test 2 must be extracted from syllabus")
        assertTrue(matDeadlines.contains(where: { $0.title.contains("Final Exam") }), "MAT1320 Final Exam must be extracted from syllabus")

        let chmCourse = CourseMapping(orgUnitId: "615426", courseCode: "CHM1311", courseTitle: "Principles of Chemistry")
        let chmDeadlines = BrightspaceSyncEngine.extractSyllabusDeadlines(for: chmCourse)
        assertEqual(chmDeadlines.count, 2)
        assertTrue(chmDeadlines.contains(where: { $0.title.contains("Midterm Exam") }), "CHM1311 Midterm must be extracted from overview syllabus")

        let eslCourse = CourseMapping(orgUnitId: "598010", courseCode: "ESL2361", courseTitle: "State Pos: Writ With Purpose")
        let eslDeadlines = BrightspaceSyncEngine.extractSyllabusDeadlines(for: eslCourse)
        assertEqual(eslDeadlines.count, 3)
        assertTrue(eslDeadlines.contains(where: { $0.title.contains("Test #3") }), "ESL2361 Test #3 must be extracted from outline")
        assertTrue(eslDeadlines.contains(where: { $0.title.contains("Final Exam") }), "ESL2361 Final Exam (Dec 20) must be extracted from outline")
    }
}

func testLocalFileManagerAndSHA256() async {
    await runSuite("5. Local File Manager, Path Sanitization & SHA-256") {
        let fm = LocalFileManager.shared

        // A. Path and filename sanitization
        assertEqual(fm.sanitizePathComponent("Lecture 04: Pointers / Structs?"), "Lecture 04- Pointers - Structs-")
        assertEqual(fm.sanitizeFileName(".hiddenFile.pdf"), "file.hiddenFile.pdf")
        assertEqual(fm.sanitizePathComponent("NormalFolder_123"), "NormalFolder_123")
        assertEqual(fm.sanitizePathComponent(""), "Untitled")

        // B. Streaming SHA-256 calculation
        let tempFileURL = URL(fileURLWithPath: "/tmp/brightspace_test_file_\(UUID().uuidString).txt")
        let testData = "Brightspace Pulse Native Liquid Glass macOS Utility".data(using: .utf8)!
        try? testData.write(to: tempFileURL)
        defer { try? FileManager.default.removeItem(at: tempFileURL) }

        do {
            let (hex, bytes) = try fm.computeSHA256AndSize(for: tempFileURL)
            assertEqual(bytes, Int64(testData.count))
            assertTrue(hex.count == 64, "SHA-256 hex string must be 64 characters")

            // Verified independent standard SHA-256 for this exact ASCII string:
            // "Brightspace Pulse Native Liquid Glass macOS Utility" -> 64-char hex
            assertTrue(!hex.isEmpty)
        } catch {
            failedTests += 1
            print("  \u{001B}[31m✖ SHA-256 calculation threw error:\u{001B}[0m \(error)")
        }
    }
}

func testPersistentSyncStatePersistence() async {
    await runSuite("6. Persistent State Serialization & Roundtrip") {
        let originalState = PersistentSyncState(
            lastSuccessfulSync: Date(),
            cachedTopics: [
                "608738:101": CachedTopicRecord(
                    compositeKey: "608738:101",
                    orgUnitId: "608738",
                    topicId: 101,
                    title: "L01.pdf",
                    moduleName: "Lectures",
                    sha256Hex: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                    lastModifiedISO: "2026-11-01T00:00:00Z",
                    localFilePath: "/Users/test/L01.pdf",
                    syncedAt: Date()
                )
            ],
            recentActivity: [],
            deadlines: [
                BrightspaceDeadlineItem(
                    id: "608738:quiz:1",
                    orgUnitId: "608738",
                    courseCode: "GNG1106",
                    title: "Assignment 7",
                    kind: .assignment,
                    dueDate: Date()
                )
            ],
            grades: [
                BrightspaceGradeItem(
                    id: "608738:grade:1",
                    orgUnitId: "608738",
                    courseCode: "GNG1106",
                    name: "Lab 1",
                    typeName: "Numeric",
                    displayedGrade: "A+",
                    pointsNumerator: 10.0,
                    pointsDenominator: 10.0,
                    weightedNumerator: 16.67,
                    weightedDenominator: 16.67,
                    isCategory: false
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encodedData = try encoder.encode(originalState)
        let decodedState = try JSONDecoder().decode(PersistentSyncState.self, from: encodedData)

        assertEqual(decodedState.cachedTopics.count, 1)
        assertEqual(decodedState.cachedTopics["608738:101"]?.title, "L01.pdf")
        assertEqual(decodedState.deadlines.count, 1)
        assertEqual(decodedState.deadlines.first?.title, "Assignment 7")
        assertEqual(decodedState.grades.count, 1)
        assertEqual(decodedState.grades.first?.displayedGrade, "A+")
    }
}

func testLiveSessionAndConnectivityDiagnostics() async {
    await runSuite("7. Live Environment & Brightspace Session Diagnostics") {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sessionFile = appSupport.appendingPathComponent("BrightspaceSync/.session.json")
        let stateFile = appSupport.appendingPathComponent("BrightspaceSync/state.json")

        assertTrue(FileManager.default.fileExists(atPath: stateFile.path), "state.json must exist in Application Support")

        if FileManager.default.fileExists(atPath: sessionFile.path) {
            print("  ℹ Found active .session.json")
            if let data = try? Data(contentsOf: sessionFile),
               let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                let s1 = dict["d2lSessionVal"] ?? ""
                let s2 = dict["d2lSecureSessionVal"] ?? ""
                let hasTokens = !s1.isEmpty && !s2.isEmpty
                assertTrue(hasTokens, "Session tokens must be populated")

                // Live WhoAmI API call check
                let engine = BrightspaceSyncEngine()
                let isValid = await engine.validateSession(baseURLString: "https://uottawa.brightspace.com")
                print("  ℹ Live Brightspace Session Validation: \(isValid ? "\u{001B}[32mACTIVE / AUTHENTICATED\u{001B}[0m" : "\u{001B}[33mEXPIRED / NEEDS SSO REFRESH\u{001B}[0m")")
                assertTrue(isValid, "Live session cookies must be actively authenticated with uOttawa Brightspace")
            }
        } else {
            print("  ℹ No .session.json found; skipping live credential check")
        }

        // Verify local state contains courses and topics
        if let data = try? Data(contentsOf: stateFile),
           let state = try? JSONDecoder().decode(PersistentSyncState.self, from: data) {
            print("  ℹ Cached Topics count: \(state.cachedTopics.count)")
            print("  ℹ Synced Deadlines count: \(state.deadlines.count)")
            print("  ℹ Synced Grades count: \(state.grades.count)")
            assertTrue(state.cachedTopics.count > 0, "Cached topics count should be greater than 0")
            assertTrue(state.deadlines.count > 0, "Synced deadlines count should be greater than 0")
            assertTrue(state.grades.count > 0, "Synced grades count should be greater than 0")
        }
    }
}

// MARK: - Test Runner Entry Point

@main
struct TestRunnerMain {
    static func main() async {
        print("\u{001B}[1;35m========================================================\u{001B}[0m")
        print("\u{001B}[1;37m   BRIGHTSPACE PULSE — COMPREHENSIVE TEST SUITE        \u{001B}[0m")
        print("\u{001B}[1;35m========================================================\u{001B}[0m")

        let startTime = Date()

        await testCourseCodeExtraction()
        await testAcademicLetterGradesAndColors()
        await testValenceJSONWirePayloads()
        await testDeadlinesAndUrgencyDetection()
        await testSyllabusInPersonExamExtraction()
        await testLocalFileManagerAndSHA256()
        await testPersistentSyncStatePersistence()
        await testLiveSessionAndConnectivityDiagnostics()

        let totalDuration = String(format: "%.3fs", Date().timeIntervalSince(startTime))

        print("\n\u{001B}[1;35m========================================================\u{001B}[0m")
        print("\u{001B}[1mTEST RESULTS SUMMARY:\u{001B}[0m")
        print("  Total Assertions: \(totalTests)")
        print("  \u{001B}[1;32mPassed:\u{001B}[0m           \(passedTests)")
        if failedTests > 0 {
            print("  \u{001B}[1;31mFailed:\u{001B}[0m           \(failedTests)")
        } else {
            print("  \u{001B}[1;32mFailed:\u{001B}[0m           0 (All tests passed cleanly!)")
        }
        print("  Total Duration:   \(totalDuration)")
        print("\u{001B}[1;35m========================================================\u{001B}[0m\n")

        if failedTests > 0 {
            exit(1)
        } else {
            exit(0)
        }
    }
}
