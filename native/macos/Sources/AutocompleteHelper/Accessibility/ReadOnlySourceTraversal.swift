/// A bounded structural walk. Sources retain their shared-container provenance;
/// traversal order never asserts that a sibling is the intended reply target.
enum ReadOnlySourceTraversal {
    /// AXVisibleChildren identifies the current viewport without walking old
    /// messages first. An empty supported value is authoritative. Hosts that do
    /// not expose it retain the bounded structural walk and visibility checks.
    static func visibleChildren<Node>(reported: [Node]?, all: () -> [Node]) -> [Node] {
        Array((reported ?? all()).prefix(32))
    }

    /// Spend the sibling budget next to the verified branch, not at the start
    /// of a potentially long document. Proximity is structural, not authorship
    /// or proof of the intended reply target. A detached branch fails closed.
    static func nearestSiblings<Node: Equatable>(_ children: [Node], to branch: Node, limit: Int) -> [Node] {
        guard limit > 0, let anchor = children.firstIndex(of: branch) else { return [] }
        var result: [Node] = []
        var distance = 1
        while result.count < limit && (anchor - distance >= 0 || anchor + distance < children.count) {
            if anchor - distance >= 0 { result.append(children[anchor - distance]) }
            if result.count < limit, anchor + distance < children.count {
                result.append(children[anchor + distance])
            }
            distance += 1
        }
        return result
    }

    enum Inspection<Node> {
        case source
        case container([Node])
        case prune
    }

    static func collectNearest<Node: Hashable>(
        maximumSources: Int, shouldContinue: () -> Bool,
        rootsForRing: (Int) -> [Node]?,
        inspect: (Node) -> Inspection<Node>
    ) -> [Node] {
        var sources: [Node] = []
        var remainingVisits = 128
        // Layout wrappers are not a semantic boundary. Follow the bounded
        // ancestry to the caller's document/window boundary while preserving
        // the original total work budget (four rings of 32 inspected nodes).
        for ring in 0..<32 {
            guard sources.count < maximumSources,
                  remainingVisits > 0, shouldContinue(),
                  let roots = rootsForRing(ring) else { break }
            // A nearby label or formatting hint is evidence, not proof that
            // the conversation has been found. Keep the same total source
            // budget while examining the enclosing containers.
            sources += collect(
                roots: roots,
                maximumSources: maximumSources - sources.count,
                shouldContinue: { remainingVisits > 0 && shouldContinue() },
                inspect: { node in
                    remainingVisits -= 1
                    return inspect(node)
                }
            )
        }
        return sources
    }

    static func collect<Node: Hashable>(
        roots: [Node], maximumSources: Int,
        shouldContinue: () -> Bool,
        inspect: (Node) -> Inspection<Node>
    ) -> [Node] {
        var frontier = roots.prefix(32).enumerated().map {
            (node: $0.element, distance: $0.offset, order: $0.offset)
        }
        var nextOrder = frontier.count
        var visited: Set<Node> = []
        var sources: [Node] = []
        while !frontier.isEmpty, visited.count < 32,
              sources.count < maximumSources, shouldContinue() {
            let entry = frontier.removeFirst()
            guard visited.insert(entry.node).inserted else { continue }
            switch inspect(entry.node) {
            case .source: sources.append(entry.node)
            case .prune: break
            case let .container(children):
                // Balance nearby siblings with their descendants. Breadth-first
                // exhausts a wide sibling list before entering any container;
                // depth-first can spend the budget inside one layout branch.
                // Distance is structural work, never authorship or chronology.
                for (offset, child) in children.prefix(32).enumerated()
                    where !visited.contains(child) {
                    frontier.append((child, entry.distance + offset + 1, nextOrder))
                    nextOrder += 1
                }
                frontier.sort {
                    $0.distance == $1.distance ? $0.order < $1.order : $0.distance < $1.distance
                }
                frontier = Array(frontier.prefix(32))
            }
        }
        return sources
    }
}
