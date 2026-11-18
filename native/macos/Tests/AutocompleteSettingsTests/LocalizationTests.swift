import Foundation
import XCTest
@testable import AutocompleteSettings

final class LocalizationTests: XCTestCase {
    func testEveryKeyHasBothLanguages() {
        for key in L10nKey.allCases {
            let strings = L10n.strings(for: key)
            XCTAssertFalse(strings.en.trimmingCharacters(in: .whitespaces).isEmpty, "Missing English for \(key)")
            XCTAssertFalse(strings.es.trimmingCharacters(in: .whitespaces).isEmpty, "Missing Spanish for \(key)")
        }
    }

    func testPlaceholdersMatchAcrossLanguages() {
        for key in L10nKey.allCases {
            let strings = L10n.strings(for: key)
            XCTAssertEqual(
                placeholders(in: strings.en),
                placeholders(in: strings.es),
                "Placeholder mismatch for \(key)"
            )
        }
    }

    func testSpanishDiffersFromEnglishForTranslatableStrings() {
        let identicalAllowed: Set<L10nKey> = [.neutral, .formal,
            .windowTitle, .sectionGeneral, .languageEnglish, .languageSpanish, .exerciseKeys,
        ]
        var identical: [L10nKey] = []
        for key in L10nKey.allCases where !identicalAllowed.contains(key) {
            let strings = L10n.strings(for: key)
            if strings.en == strings.es { identical.append(key) }
        }
        XCTAssertTrue(identical.isEmpty, "Untranslated keys: \(identical)")
    }

    /// Storage keeps the transform name; the user only ever reads "rewrite".
    func testVisibleStringsNeverSayTransform() {
        for key in L10nKey.allCases {
            let strings = L10n.strings(for: key)
            XCTAssertFalse(strings.en.localizedCaseInsensitiveContains("transform"), "English \(key) says transform")
            XCTAssertFalse(strings.es.localizedCaseInsensitiveContains("transform"), "Spanish \(key) says transform")
        }
    }

    func testFormatSubstitutesArguments() {
        let english = L10n(language: .en)
        XCTAssertEqual(english.format(.updatedOn, "Sep 5, 2026"), "Updated Sep 5, 2026")
        XCTAssertEqual(english.format(.characterCount, "12", "12,000"), "12 of 12,000 characters")
        let spanish = L10n(language: .es)
        XCTAssertEqual(spanish.format(.deleteConfirmTitle, "Acme"), "¿Eliminar «Acme»?")
    }

    func testLocaleFollowsLanguage() {
        XCTAssertEqual(L10n(language: .es).locale.language.languageCode, .spanish)
        XCTAssertEqual(L10n(language: .en).locale.language.languageCode, .english)
    }

    func testConditionTitlesAreLocalized() throws {
        var status = try Fixtures.status()
        status.account.state = .signedOut
        let condition = ProductCondition(status: status)
        XCTAssertEqual(condition, .signedOut)
        XCTAssertEqual(condition.title(L10n(language: .en)), "Signed out")
        XCTAssertEqual(condition.title(L10n(language: .es)), "Sesión cerrada")
    }

    private func placeholders(in text: String) -> Set<String> {
        var found: Set<String> = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: #"\{\d\}"#, options: .regularExpression, range: searchRange) {
            found.insert(String(text[range]))
            searchRange = range.upperBound..<text.endIndex
        }
        return found
    }
}
