import Foundation
import XCTest
@testable import AutocompleteSettings

final class LibraryDraftTests: XCTestCase {
    func testKnowledgeRequiresAnchorApplicationsTitleAndText() {
        var draft = LibraryDraft(kind: .knowledge)
        XCTAssertEqual(draft.issues, [.missingTitle, .invalidAnchor, .missingApplications, .missingText])
        draft.title = "Acme"
        draft.anchor = "Ac"
        XCTAssertTrue(draft.issues.contains(.invalidAnchor))
        draft.anchor = "a-b-c"
        XCTAssertTrue(draft.issues.contains(.invalidAnchor), "Three letters must be consecutive")
        draft.anchor = "alex@example.com"
        draft.appIds = ["com.apple.mail"]
        draft.text = "Facts"
        XCTAssertTrue(draft.canSave)
        XCTAssertTrue(draft.canImport)
    }

    func testStyleOnlyNeedsTitleForImportAndTextForSave() {
        var draft = LibraryDraft(kind: .style)
        XCTAssertEqual(draft.metadataIssues, [.missingTitle])
        draft.title = "Short replies"
        XCTAssertTrue(draft.canImport)
        XCTAssertFalse(draft.canSave)
        draft.text = "Keep it short."
        XCTAssertTrue(draft.canSave)
    }

    func testTextLimit() {
        var draft = LibraryDraft(kind: .style)
        draft.title = "Long"
        draft.text = String(repeating: "a", count: LibraryInput.textLimit + 1)
        XCTAssertEqual(draft.issues, [.textTooLong])
    }

    func testDraftFromEntryRoundTripsAndDetectsDirtiness() throws {
        let entry = try Fixtures.entries()[0]
        let draft = LibraryDraft(entry: entry)
        XCTAssertEqual(draft.id, "entry-1")
        XCTAssertEqual(draft.expectedRevision, 3)
        XCTAssertEqual(draft.expiryDate, Date(timeIntervalSince1970: 1_759_276_800))
        var edited = draft
        XCTAssertEqual(edited, draft)
        edited.setApplication("com.apple.Notes", included: true)
        XCTAssertNotEqual(edited, draft)
        edited.setApplication("com.apple.Notes", included: false)
        XCTAssertEqual(edited, draft)
        XCTAssertEqual(draft.input().expiresAt, 1_759_276_800_000)
    }

    func testInputTrimsAndClampsLimits() {
        var draft = LibraryDraft(kind: .knowledge)
        draft.title = String(repeating: "t", count: 200)
        draft.anchor = String(repeating: "a", count: 300)
        draft.appIds = (0..<30).map { "app\($0)" }
        let input = draft.input()
        XCTAssertEqual(input.title.count, LibraryInput.titleLimit)
        XCTAssertEqual(input.scope.anchor.count, LibraryInput.anchorLimit)
        XCTAssertEqual(input.scope.appIds.count, LibraryInput.applicationLimit)
    }
}

final class ProductConditionTests: XCTestCase {
    func testPriorityOrder() throws {
        var status = try Fixtures.status()
        status.permissions.inputMonitoring = .granted
        status.connection = .ready
        XCTAssertEqual(ProductCondition(status: status), .readyOnRequest)

        status.automaticSuggestions = true
        XCTAssertEqual(ProductCondition(status: status), .readyAutomatic)

        status.connection = .error
        XCTAssertEqual(ProductCondition(status: status), .serviceError)
        status.connection = .offline
        XCTAssertEqual(ProductCondition(status: status), .offline)

        status.enabled = false
        XCTAssertEqual(ProductCondition(status: status), .paused(until: status.pausedUntilDate))

        status.helperState = .starting
        XCTAssertEqual(ProductCondition(status: status), .helperStarting)

        status.permissions.accessibility = .required
        XCTAssertEqual(ProductCondition(status: status), .permissionsRequired)

        status.account.state = .expired
        XCTAssertEqual(ProductCondition(status: status), .sessionExpired)
        status.account.state = .signedOut
        XCTAssertEqual(ProductCondition(status: status), .signedOut)

        status.helperState = .unavailable
        XCTAssertEqual(ProductCondition(status: status), .helperUnavailable)
    }

    func testPausedDetailUsesReturnTime() throws {
        let until = Date().addingTimeInterval(1800)
        let condition = ProductCondition.paused(until: until)
        let l10n = L10n(language: .en)
        XCTAssertTrue(condition.detail(l10n).contains(l10n.shortTime(until)))
        XCTAssertEqual(ProductCondition.paused(until: nil).detail(l10n), "Suggestions are off until you resume.")
    }
}
