import XCTest
@testable import AutocompleteHelper

final class ReadOnlySourceTraversalTests: XCTestCase {
    func testVisibleMessagesBeyondTheFirstPageRemainReachable() {
        var readAll = false
        let roots = ReadOnlySourceTraversal.visibleChildren(
            reported: [90, 91, 92], all: { readAll = true; return Array(0..<100) })
        let result = ReadOnlySourceTraversal.collect(roots: roots, maximumSources: 3,
            shouldContinue: { true }, inspect: { _ in .source })
        XCTAssertEqual(result, [90, 91, 92])
        XCTAssertFalse(readAll)
    }

    func testEmptyVisibleChildrenDoesNotReadOffscreenHistory() {
        var readAll = false
        let children: [Int] = ReadOnlySourceTraversal.visibleChildren(
            reported: [], all: { readAll = true; return [1, 2] })
        XCTAssertTrue(children.isEmpty)
        XCTAssertFalse(readAll)
    }

    func testMissingVisibleChildrenUsesBoundedStructuralChildren() {
        let children = ReadOnlySourceTraversal.visibleChildren(
            reported: nil, all: { Array(0..<100) })
        XCTAssertEqual(children, Array(0..<32))
    }

    func testNearestMessageDescendantIsNotStarvedByWideSiblingList() {
        var visits = 0
        let roots = ["conversation"] + (1..<32).map { "wrapper-\($0)" }
        let result = ReadOnlySourceTraversal.collect(roots: roots, maximumSources: 1, shouldContinue: { true }) { node in
            visits += 1
            if node == "conversation" { return .container(["message"]) }
            if node == "message" { return .source }
            return .prune
        }
        XCTAssertEqual(result, ["message"])
        XCTAssertLessThanOrEqual(visits, 3)
    }

    func testDeepFirstBranchCannotMonopolizeNearSiblingEvidence() {
        var visits = 0
        let result = ReadOnlySourceTraversal.collect(roots: [0, 1000], maximumSources: 1, shouldContinue: { true }) { node in
            visits += 1
            return node == 1000 ? .source : .container([node + 1])
        }
        XCTAssertEqual(result, [1000])
        XCTAssertLessThanOrEqual(visits, 3)
    }

    func testDeadlineStopsBeforeReadingAnyMoreSourceNodes() {
        var reads = 0
        let result = ReadOnlySourceTraversal.collect(roots: [0, 100], maximumSources: 6,
            shouldContinue: { reads < 2 }) { node in
                reads += 1
                return .container([node + 1])
            }
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(reads, 2)
    }

    func testSiblingBudgetStartsAtTheFocusedBranchInLongContainers() {
        let siblings = Array(0..<100)
        let roots = ReadOnlySourceTraversal.nearestSiblings(siblings, to: 90, limit: 32)
        XCTAssertEqual(Array(roots.prefix(4)), [89, 91, 88, 92])
        XCTAssertEqual(roots.count, 32)
        XCTAssertFalse(roots.contains(90))
        XCTAssertFalse(roots.contains(0))
        let sources = ReadOnlySourceTraversal.collect(roots: roots, maximumSources: 1, shouldContinue: { true }) {
            $0 == 89 ? .source : .prune
        }
        XCTAssertEqual(sources, [89])
    }

    func testSiblingSelectionRequiresTheCurrentBranchAndHonorsEdges() {
        XCTAssertEqual(ReadOnlySourceTraversal.nearestSiblings([0, 1, 2, 3], to: 0, limit: 2), [1, 2])
        XCTAssertEqual(ReadOnlySourceTraversal.nearestSiblings([0, 1, 2, 3], to: 3, limit: 2), [2, 1])
        XCTAssertEqual(ReadOnlySourceTraversal.nearestSiblings([0, 1, 2], to: 9, limit: 2), [])
        XCTAssertEqual(ReadOnlySourceTraversal.nearestSiblings([0, 1, 2], to: 1, limit: 0), [])
    }

    func testComposerLayoutWrappersDoNotHideTheConversation() {
        let result = ReadOnlySourceTraversal.collectNearest(maximumSources: 6, shouldContinue: { true }, rootsForRing: { ring in
            if ring == 7 { return ["visible message"] }
            return ring < 7 ? [] : nil
        }, inspect: { _ in .source })
        XCTAssertEqual(result, ["visible message"])
    }

    func testDeeperAncestryDoesNotIncreaseTotalNodeWork() {
        var visits = 0
        let result = ReadOnlySourceTraversal.collectNearest(maximumSources: 6, shouldContinue: { true }, rootsForRing: { ring in [ring * 100] }) { node in
            visits += 1
            return .container([node + 1])
        }
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(visits, 128)
    }

    func testDocumentBoundaryStopsSearchBeforeOtherConversations() {
        var outerRingVisited = false
        let result = ReadOnlySourceTraversal.collectNearest(maximumSources: 6, shouldContinue: { true }, rootsForRing: { ring -> [String]? in
            if ring == 5 { return nil }
            if ring > 5 { outerRingVisited = true; return ["other conversation"] }
            return []
        }, inspect: { _ in .source })
        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(outerRingVisited)
    }

    func testNearbyHintDoesNotEndSearchBeforeConversationContainer() {
        let result = ReadOnlySourceTraversal.collectNearest(maximumSources: 6, shouldContinue: { true }, rootsForRing: { ring in
            switch ring {
            case 0: ["formatting hint"]
            case 1: []
            case 2: ["current message"]
            default: nil
            }
        }, inspect: { _ in .source })
        XCTAssertEqual(result, ["formatting hint", "current message"])
    }

    func testSourceLimitIsSharedAcrossAncestorRings() {
        var inspected = 0
        let result = ReadOnlySourceTraversal.collectNearest(maximumSources: 2, shouldContinue: { true }, rootsForRing: { ring in [ring] }) { _ in
            inspected += 1
            return .source
        }
        XCTAssertEqual(result, [0, 1])
        XCTAssertEqual(inspected, 2)
    }

    func testGroupedMessagesAreFoundWithoutEnteringEditableOrWindowBranches() {
        let tree = ["group": ["message"], "editor": ["private draft"], "window": ["unrelated"]]
        var visited: [String] = []
        let result = ReadOnlySourceTraversal.collect(roots: ["group", "editor", "window"], maximumSources: 6, shouldContinue: { true }) { node in
            visited.append(node)
            if node == "editor" || node == "window" { return .prune }
            if let children = tree[node] { return .container(children) }
            return .source
        }
        XCTAssertEqual(result, ["message"])
        XCTAssertFalse(visited.contains("private draft"))
        XCTAssertFalse(visited.contains("unrelated"))
    }

    func testMessageSurvivesOrdinaryNestedLayoutContainers() {
        let result = ReadOnlySourceTraversal.collect(roots: [0], maximumSources: 6, shouldContinue: { true }) { node in
            node == 8 ? .source : .container([node + 1])
        }
        XCTAssertEqual(result, [8])
    }

    func testTraversalBoundsNodesAndCycles() {
        var visits = 0
        let result = ReadOnlySourceTraversal.collect(roots: [0], maximumSources: 6, shouldContinue: { true }) { node in
            visits += 1
            return .container([node, node + 1])
        }
        XCTAssertTrue(result.isEmpty)
        XCTAssertLessThanOrEqual(visits, 32)
    }
}
