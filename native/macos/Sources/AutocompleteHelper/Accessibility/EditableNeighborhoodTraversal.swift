import Foundation

/// Incremental, bounded traversal of the sibling subtrees exposed while
/// walking out from a focused editable. Ancestor proximity always wins over
/// raw tree depth, so a deeply wrapped field in the same form is inspected
/// before unrelated controls from a more distant container.
struct EditableNeighborhoodTraversal<Node: Hashable> {
    struct Seed {
        let node: Node
        let ancestorRing: Int
        let branchPriority: Int
    }

    struct Visit {
        let children: [Node]
        let shouldPrune: Bool
    }

    struct ScanResult {
        let visitedNodes: [Node]
        let isComplete: Bool
    }

    private struct Entry {
        let node: Node
        let ancestorRing: Int
        let branchPriority: Int
        let depth: Int
        let sequence: Int
    }

    private var frontier: [Entry]
    private var visited: Set<Node> = []
    private var nextSequence: Int

    init(seeds: [Seed]) {
        frontier = seeds.enumerated().map { index, seed in
            Entry(
                node: seed.node,
                ancestorRing: seed.ancestorRing,
                branchPriority: seed.branchPriority,
                depth: 0,
                sequence: index
            )
        }
        nextSequence = seeds.count
    }

    mutating func scan(
        maximumVisits: Int,
        shouldContinue: () -> Bool = { true },
        visit: (Node) -> Visit
    ) -> ScanResult {
        guard maximumVisits > 0 else {
            return ScanResult(visitedNodes: [], isComplete: frontier.isEmpty)
        }

        var slice: [Node] = []
        while slice.count < maximumVisits, shouldContinue(), let entry = popNext() {
            guard visited.insert(entry.node).inserted else { continue }
            slice.append(entry.node)

            let result = visit(entry.node)
            guard !result.shouldPrune else { continue }
            for child in result.children {
                frontier.append(
                    Entry(
                        node: child,
                        ancestorRing: entry.ancestorRing,
                        branchPriority: entry.branchPriority,
                        depth: entry.depth + 1,
                        sequence: nextSequence
                    )
                )
                nextSequence += 1
            }
        }
        discardVisitedFrontierEntries()
        return ScanResult(visitedNodes: slice, isComplete: frontier.isEmpty)
    }

    private mutating func popNext() -> Entry? {
        discardVisitedFrontierEntries()
        guard !frontier.isEmpty else { return nil }
        let index = frontier.indices.min { lhs, rhs in
            isHigherPriority(frontier[lhs], than: frontier[rhs])
        }!
        return frontier.remove(at: index)
    }

    private mutating func discardVisitedFrontierEntries() {
        frontier.removeAll { visited.contains($0.node) }
    }

    private func isHigherPriority(_ lhs: Entry, than rhs: Entry) -> Bool {
        if lhs.ancestorRing != rhs.ancestorRing {
            return lhs.ancestorRing < rhs.ancestorRing
        }
        if lhs.branchPriority != rhs.branchPriority {
            return lhs.branchPriority < rhs.branchPriority
        }
        if lhs.depth != rhs.depth {
            return lhs.depth < rhs.depth
        }
        return lhs.sequence < rhs.sequence
    }
}
