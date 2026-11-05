import Dragology
import Foundation

// A small term-rewriting engine, ported from Dragology's algebra demos.

struct AlgebraTree: Equatable {
    var id: String
    var label: String
    var children: [AlgebraTree] = []
    /// For nodes a rewrite created, what they grow out of.
    var emergeOrigin: String?
    var emergeMode = EmergeMode.morph

    /// The expression as an s-expression.
    var text: String {
        guard !children.isEmpty else { return label }

        return "(" + ([label] + children.map(\.text)).joined(separator: " ") + ")"
    }

    /// Same labels and shape, ignoring ids.
    func isStructurallyEqual(to other: AlgebraTree) -> Bool {
        label == other.label
            && children.count == other.children.count
            && zip(children, other.children).allSatisfy { $0.isStructurallyEqual(to: $1) }
    }
}

/// Like a tree, but with wildcards. Patterns can mark nodes as triggers:
/// a match only counts if one of them lines up with the dragged node.
indirect enum AlgebraPattern: Sendable {
    case op(id: String, label: String, children: [AlgebraPattern], isTrigger: Bool)
    case wildcard(id: String, isTrigger: Bool)

    var isTrigger: Bool {
        switch self {
        case .op(_, _, _, let isTrigger), .wildcard(_, let isTrigger):
            return isTrigger
        }
    }

    /// Parses patterns like `(+2 #(+1 A B) C)`. `#` marks a trigger, a
    /// digit after an operator tells apart two operators of the same kind,
    /// and bare names are wildcards.
    init(parsing source: String) {
        var parser = PatternParser(source)
        self = parser.parsePattern()
    }
}

private struct PatternParser {
    private var characters: ArraySlice<Character>

    init(_ source: String) {
        characters = Array(source)[...]
    }

    private mutating func skipSpaces() {
        while let first = characters.first, first.isWhitespace {
            characters.removeFirst()
        }
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    mutating func parsePattern() -> AlgebraPattern {
        skipSpaces()

        let isTrigger = characters.first == "#"

        if isTrigger {
            characters.removeFirst()
            skipSpaces()
        }

        guard characters.first == "(" else {
            var name = ""

            while let first = characters.first, Self.isNameCharacter(first) {
                name.append(characters.removeFirst())
            }

            return .wildcard(id: name, isTrigger: isTrigger)
        }

        characters.removeFirst()
        skipSpaces()

        // An operator is one character, plus an optional number.
        let label = String(characters.removeFirst())
        var id = label

        while let first = characters.first, first.isNumber {
            id.append(characters.removeFirst())
        }

        var children: [AlgebraPattern] = []
        skipSpaces()

        while let first = characters.first, first != ")" {
            children.append(parsePattern())
            skipSpaces()
        }

        characters.removeFirst()

        return .op(id: id, label: label, children: children, isTrigger: isTrigger)
    }
}

struct AlgebraRewrite: Sendable {
    var from: AlgebraPattern
    var to: AlgebraPattern

    init(_ from: String, _ to: String) {
        self.from = AlgebraPattern(parsing: from)
        self.to = AlgebraPattern(parsing: to)
    }

    init(from: AlgebraPattern, to: AlgebraPattern) {
        self.from = from
        self.to = to
    }
}

/// What a pattern's wildcards and operators matched.
private struct AlgebraMatch {
    var wildcards: [String: AlgebraTree] = [:]
    var ops: [String: AlgebraTree] = [:]
    var isTriggered = false
}

enum AlgebraEngine {
    private static func match(
        _ pattern: AlgebraPattern,
        _ tree: AlgebraTree,
        trigger: String
    ) -> AlgebraMatch? {
        var result = AlgebraMatch()
        result.isTriggered = pattern.isTrigger && tree.id == trigger

        switch pattern {
        case .wildcard(let id, _):
            result.wildcards[id] = tree
            return result

        case .op(let id, let label, let children, _):
            guard label == tree.label, children.count == tree.children.count else { return nil }

            for (childPattern, child) in zip(children, tree.children) {
                guard let childResult = match(childPattern, child, trigger: trigger) else { return nil }

                for (key, value) in childResult.wildcards {
                    guard let existing = result.wildcards[key] else {
                        result.wildcards[key] = value
                        continue
                    }

                    // A repeated wildcard must match the same thing. Prefer
                    // the triggered copy, so the dragged node's id survives.
                    guard existing.isStructurallyEqual(to: value) else { return nil }

                    if value.id == trigger {
                        result.wildcards[key] = value
                    }
                }

                result.ops.merge(childResult.ops) { first, _ in first }
                result.isTriggered = result.isTriggered || childResult.isTriggered
            }

            result.ops[id] = tree

            return result
        }
    }

    /// Builds a rewrite's result. The first use of anything matched keeps
    /// its ids; further uses are clones that split off from the original,
    /// and operators new to the right side grow out of the trigger.
    private static func applying(_ matched: AlgebraMatch, to pattern: AlgebraPattern, trigger: String) -> AlgebraTree {
        var consumed = Set<String>()

        func freshID(_ base: String) -> String {
            "\(trigger)-\(base)-\(uniqueSuffix())"
        }

        func cloned(_ tree: AlgebraTree) -> AlgebraTree {
            AlgebraTree(
                id: freshID(tree.id),
                label: tree.label,
                children: tree.children.map(cloned),
                emergeOrigin: tree.id,
                emergeMode: .clone
            )
        }

        func build(_ pattern: AlgebraPattern) -> AlgebraTree {
            switch pattern {
            case .wildcard(let id, _):
                guard let subtree = matched.wildcards[id] else {
                    preconditionFailure("The rewrite's right side uses \(id), which its left side doesn't bind.")
                }

                return consumed.insert(id).inserted ? subtree : cloned(subtree)

            case .op(let id, let label, let children, _):
                guard let original = matched.ops[id] else {
                    return AlgebraTree(
                        id: freshID(id),
                        label: label,
                        children: children.map(build),
                        emergeOrigin: trigger
                    )
                }

                guard consumed.insert("op:" + id).inserted else {
                    return AlgebraTree(
                        id: freshID(id),
                        label: label,
                        children: children.map(build),
                        emergeOrigin: original.id
                    )
                }

                return AlgebraTree(id: original.id, label: label, children: children.map(build))
            }
        }

        return build(pattern)
    }

    /// Everything the tree can become, by one rewrite at any depth,
    /// triggered by the node `trigger`.
    static func allRewrites(of tree: AlgebraTree, rules: [AlgebraRewrite], trigger: String) -> [AlgebraTree] {
        var results: [AlgebraTree] = []

        for rule in rules {
            if let matched = match(rule.from, tree, trigger: trigger), matched.isTriggered {
                results.append(applying(matched, to: rule.to, trigger: trigger))
            }
        }

        for (index, child) in tree.children.enumerated() {
            for rewritten in allRewrites(of: child, rules: rules, trigger: trigger) {
                var copy = tree
                copy.children[index] = rewritten
                results.append(copy)
            }
        }

        return results
    }
}

/// `freshID`, reachable from inside the local function of the same name.
private func uniqueSuffix() -> String {
    freshID()
}

// MARK: - Rules

enum AlgebraRules {
    static let identity = [
        AlgebraRewrite("(+ (0) #A)", "A"),
        AlgebraRewrite("(+ #A (0))", "A"),
        AlgebraRewrite("#A", "(+ (0) A)"),
    ]

    static let commutativity = [
        AlgebraRewrite("(+ #A #B)", "(+ B A)"),
        AlgebraRewrite("(× #A #B)", "(× B A)"),
    ]

    static let associativity = [
        AlgebraRewrite("(+2 #(+1 A B) C)", "(+1 A (+2 B C))"),
        AlgebraRewrite("(+1 A #(+2 B C))", "(+2 (+1 A B) C)"),
        AlgebraRewrite("(×2 #(×1 A B) C)", "(×1 A (×2 B C))"),
        AlgebraRewrite("(×1 A #(×2 B C))", "(×2 (×1 A B) C)"),
        AlgebraRewrite("(+2 (+1 #A B) C)", "(+1 A (+2 B C))"),
        AlgebraRewrite("(+1 A (+2 B #C))", "(+2 (+1 A B) C)"),
        AlgebraRewrite("(×2 (×1 #A B) C)", "(×1 A (×2 B C))"),
        AlgebraRewrite("(×1 A (×2 B #C))", "(×2 (×1 A B) C)"),
    ]

    static let distribute = [
        AlgebraRewrite("(× A #(+ B C))", "(+ (× A B) (× A C))"),
        AlgebraRewrite("(× #(+ B C) A)", "(+ (× B A) (× C A))"),
        AlgebraRewrite("(× #A (+ B C))", "(+ (× A B) (× A C))"),
        AlgebraRewrite("(× (+ B C) #A)", "(+ (× B A) (× C A))"),
    ]

    static let factor = [
        AlgebraRewrite("#(+ (× A B) (× A C))", "(× A (+ B C))"),
        AlgebraRewrite("#(+ (× B A) (× C A))", "(× A (+ B C))"),
        AlgebraRewrite("(+ (× #A B) (× A C))", "(× A (+ B C))"),
        AlgebraRewrite("(+ (× A B) (× #A C))", "(× A (+ B C))"),
        AlgebraRewrite("(+ (× B #A) (× C A))", "(× A (+ B C))"),
        AlgebraRewrite("(+ (× B A) (× C #A))", "(× A (+ B C))"),
    ]
}
