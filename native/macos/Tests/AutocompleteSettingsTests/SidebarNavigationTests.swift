import XCTest
@testable import AutocompleteSettings

@MainActor
final class SidebarNavigationTests: XCTestCase {
    func testSidebarListsRewritesAsItsOwnDestinationAndKeepsAccountAnchored() {
        XCTAssertEqual(SidebarSection.primary, [.general, .writing, .rewrites, .applications, .context])
        XCTAssertFalse(SidebarSection.primary.contains(.account), "Account is anchored below the list, not inside it")
        XCTAssertFalse(SidebarSection.primary.contains(.library), "Library stays hidden while deferred")
        XCTAssertEqual(SidebarSection.primary.map(\.symbolName).count, Set(SidebarSection.primary.map(\.symbolName)).count)
    }

    func testRewritesTitleIsUserFacingInBothLanguages() {
        XCTAssertEqual(L10n(language: .en)[SidebarSection.rewrites.titleKey], "Rewrites")
        XCTAssertEqual(L10n(language: .es)[SidebarSection.rewrites.titleKey], "Reescrituras")
    }

    func testNavigatingToRewritesKeepsUnsavedRewriteDraft() {
        let store = SettingsStore(transport: FakeTransport())
        store.receive(line: Fixtures.stateLine)
        store.editTransforms { $0.enabled = true }
        XCTAssertTrue(store.hasUnsavedTransformChanges)

        store.navigate(.section(.rewrites))
        XCTAssertEqual(store.selection, .rewrites)
        store.navigate(.section(.writing))
        XCTAssertEqual(store.selection, .writing)
        XCTAssertTrue(store.hasUnsavedTransformChanges, "Moving between destinations never discards a staged rewrite draft")
        XCTAssertTrue(store.hasUnsavedChanges, "Close and quit guards still see the rewrite draft")
    }
}
