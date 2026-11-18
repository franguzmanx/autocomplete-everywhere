import XCTest
@testable import AutocompleteHelper

final class EditableNeighborhoodTraversalTests: XCTestCase {
    private struct Node: Equatable {
        let id: Int
        let children: [Int]
        let isEditable: Bool
    }

    func testFindsAnEditableBehindDeepWrappersWithoutADepthLimit() {
        let nodes = Dictionary(uniqueKeysWithValues: (0...8).map { index in
            (
                index,
                Node(
                    id: index,
                    children: index < 8 ? [index + 1] : [],
                    isEditable: index == 8
                )
            )
        })
        var traversal = EditableNeighborhoodTraversal(
            seeds: [.init(node: 0, ancestorRing: 0, branchPriority: 0)]
        )

        let result = traversal.scan(maximumVisits: 32) { id in
            let node = nodes[id]!
            return .init(children: node.children, shouldPrune: node.isEditable)
        }

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.visitedNodes, Array(0...8))
    }

    func testBudgetExhaustionIsPartialAndResumesWithoutRepeatingNodes() {
        let nodes = Dictionary(uniqueKeysWithValues: (0...12).map { index in
            (index, Node(id: index, children: index < 12 ? [index + 1] : [], isEditable: false))
        })
        var traversal = EditableNeighborhoodTraversal(
            seeds: [.init(node: 0, ancestorRing: 0, branchPriority: 0)]
        )

        let first = traversal.scan(maximumVisits: 5) { id in
            .init(children: nodes[id]!.children, shouldPrune: false)
        }
        let second = traversal.scan(maximumVisits: 20) { id in
            .init(children: nodes[id]!.children, shouldPrune: false)
        }

        XCTAssertFalse(first.isComplete)
        XCTAssertEqual(first.visitedNodes, [0, 1, 2, 3, 4])
        XCTAssertTrue(second.isComplete)
        XCTAssertEqual(second.visitedNodes, Array(5...12))
    }

    func testCloserAncestorRingWinsOverShallowerDistantBranch() {
        var traversal = EditableNeighborhoodTraversal(
            seeds: [
                .init(node: 100, ancestorRing: 3, branchPriority: 0),
                .init(node: 1, ancestorRing: 0, branchPriority: 0),
            ]
        )

        let result = traversal.scan(maximumVisits: 4) { id in
            switch id {
            case 1: .init(children: [2], shouldPrune: false)
            case 2: .init(children: [3], shouldPrune: false)
            default: .init(children: [], shouldPrune: false)
            }
        }

        XCTAssertEqual(result.visitedNodes, [1, 2, 3, 100])
    }

    func testPruningAnEditableSkipsItsStaticDescendants() {
        var traversal = EditableNeighborhoodTraversal(
            seeds: [.init(node: 1, ancestorRing: 0, branchPriority: 0)]
        )

        let result = traversal.scan(maximumVisits: 8) { id in
            id == 1
                ? .init(children: [2, 3], shouldPrune: true)
                : .init(children: [], shouldPrune: false)
        }

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.visitedNodes, [1])
    }

    func testPauseConditionPreservesTheFrontierForTheNextSlice() {
        var traversal = EditableNeighborhoodTraversal(
            seeds: [.init(node: 1, ancestorRing: 0, branchPriority: 0)]
        )
        var allowedVisits = 2

        let first = traversal.scan(
            maximumVisits: 20,
            shouldContinue: {
                defer { allowedVisits -= 1 }
                return allowedVisits > 0
            }
        ) { id in
            .init(children: id < 4 ? [id + 1] : [], shouldPrune: false)
        }
        let second = traversal.scan(maximumVisits: 20) { id in
            .init(children: id < 4 ? [id + 1] : [], shouldPrune: false)
        }

        XCTAssertFalse(first.isComplete)
        XCTAssertEqual(first.visitedNodes, [1, 2])
        XCTAssertTrue(second.isComplete)
        XCTAssertEqual(second.visitedNodes, [3, 4])
    }

    func testCyclesAreVisitedOnce() {
        var traversal = EditableNeighborhoodTraversal(
            seeds: [.init(node: 1, ancestorRing: 0, branchPriority: 0)]
        )

        let result = traversal.scan(maximumVisits: 8) { id in
            .init(children: id == 1 ? [2] : [1], shouldPrune: false)
        }

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.visitedNodes, [1, 2])
    }
}
