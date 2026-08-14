import Foundation
import Yams

/// Typed, read-only view over the flow mapping carried by an item's inline
/// `<!--cueme {…}-->` comment (design.md §4.2). Every accessor is `nil`-safe:
/// a missing or mistyped key never throws, it just returns `nil`.
struct NoteItemAttributes {
    private let values: [String: OKFValue]

    init(_ values: [String: OKFValue] = [:]) {
        self.values = values
    }

    subscript(key: String) -> OKFValue? { values[key] }

    var isEmpty: Bool { values.isEmpty }

    func uuidValue(_ key: String) -> UUID? {
        guard case let .string(raw, _)? = values[key] else { return nil }
        return UUID(uuidString: raw)
    }

    /// Dates ride the comment the same way they ride frontmatter (design.md
    /// §3): a double-quoted ISO-8601 string, decoded here as `.string`.
    func dateValue(_ key: String) -> Date? {
        switch values[key] {
        case .string(let raw, _)?: return Self.parseDate(raw)
        case .date(let d)?: return d
        default: return nil
        }
    }

    func doubleValue(_ key: String) -> Double? {
        switch values[key] {
        case .double(let d)?: return d
        case .int(let i)?: return Double(i)
        default: return nil
        }
    }

    func stringValue(_ key: String) -> String? {
        guard case let .string(raw, _)? = values[key] else { return nil }
        return raw
    }

    func stringsValue(_ key: String) -> [String]? {
        guard case let .array(items)? = values[key] else { return nil }
        return items.compactMap { item -> String? in
            guard case let .string(raw, _) = item else { return nil }
            return raw
        }
    }

    // Not a cached `static let`: `ISO8601DateFormatter` is not `Sendable`
    // under Swift 6 strict concurrency, same rationale as `OKFFrontmatter`'s
    // `iso8601String` — a fresh instance per call, never shared.
    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
}

/// Codec for the inline item-attribute comment: the flow-mapping YAML carried
/// in an HTML comment at the end of an item's anchor line (design.md §4.2).
///
/// No Yams type ever appears in this file's public API — same rationale as
/// `OKFFrontmatter` (not `Sendable` under Swift 6 strict concurrency).
enum NoteItemAttributeCodec {
    /// Emits the full inline comment, including its leading separating space,
    /// e.g. `" <!--cueme {id: …, at: …}-->"`. Empty string when `pairs` is
    /// empty, so `anchorText + encode(pairs)` is always the correct anchor
    /// line — never a dangling trailing space.
    static func encode(_ pairs: [(String, OKFValue)]) -> String {
        guard !pairs.isEmpty else { return "" }
        let body = pairs.map { "\($0.0): \(flowScalar($0.1))" }.joined(separator: ", ")
        return " <!--cueme {\(body)}-->"
    }

    /// Splits `line` into its visible text and typed attributes. The comment
    /// is recognized only when it is the last thing on the line — found via
    /// the *last* occurrence of the opening token, so a `-->` inside the
    /// visible text never truncates anything. A malformed comment (unbalanced
    /// braces, or content that is not valid YAML) degrades to "the whole line
    /// is text, attributes empty" — this never throws.
    static func decode(_ line: String) -> (text: String, attributes: NoteItemAttributes) {
        let opening = "<!--cueme {"
        guard let openingRange = line.range(of: opening, options: .backwards) else {
            return (line, NoteItemAttributes())
        }

        // openingRange.upperBound sits right after the "{" that opens the
        // flow mapping; balance starts at 1 to account for it.
        var balance = 1
        var cursor = openingRange.upperBound
        var closeIndex: String.Index?
        while cursor < line.endIndex {
            let character = line[cursor]
            if character == "{" {
                balance += 1
            } else if character == "}" {
                balance -= 1
                if balance == 0 {
                    closeIndex = cursor
                    break
                }
            }
            cursor = line.index(after: cursor)
        }

        guard let close = closeIndex else {
            return (line, NoteItemAttributes())
        }

        let afterClose = line.index(after: close)
        let tail = line[afterClose...]
        guard tail.hasPrefix("-->") else {
            return (line, NoteItemAttributes())
        }
        let trailing = tail.dropFirst(3)
        guard trailing.allSatisfy({ $0 == " " || $0 == "\t" }) else {
            return (line, NoteItemAttributes())
        }

        let openBrace = line.index(before: openingRange.upperBound)
        let payload = String(line[openBrace...close])

        guard let root = try? Yams.compose(yaml: payload), let mapping = root.mapping else {
            return (line, NoteItemAttributes())
        }

        var values: [String: OKFValue] = [:]
        for entry in mapping {
            guard let key = entry.key.string else { continue }
            values[key] = convert(entry.value)
        }

        var textEnd = openingRange.lowerBound
        while textEnd > line.startIndex {
            let previous = line.index(before: textEnd)
            guard line[previous] == " " || line[previous] == "\t" else { break }
            textEnd = previous
        }
        let text = String(line[line.startIndex..<textEnd])

        return (text, NoteItemAttributes(values))
    }

    // MARK: - Yams Node -> OKFValue (private: Node never escapes this file)

    private static func convert(_ node: Node) -> OKFValue {
        if let mapping = node.mapping {
            return .mapping(mapping.map { ($0.key.string ?? "", convert($0.value)) })
        }
        if let sequence = node.sequence {
            return .array(sequence.map(convert))
        }
        if let b = node.bool { return .bool(b) }
        if let i = node.int { return .int(i) }
        if let d = node.float { return .double(d) }
        let style = node.scalar?.style
        let quoted = style == .doubleQuoted || style == .singleQuoted
        return .string(node.string ?? "", alwaysQuoted: quoted)
    }

    // MARK: - OKFValue -> flow-style text

    private static func flowScalar(_ value: OKFValue) -> String {
        switch value {
        case .string(let raw, let alwaysQuoted):
            return alwaysQuoted || needsQuoting(raw) ? quoted(raw) : raw
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .date(let d):
            return quoted(iso8601String(d))
        case .array(let items):
            return "[" + items.map(flowScalar).joined(separator: ", ") + "]"
        case .mapping(let pairs):
            return "{" + pairs.map { "\($0.0): \(flowScalar($0.1))" }.joined(separator: ", ") + "}"
        }
    }

    // MARK: - Quoting policy (design.md §3 — applies unchanged inside flow mappings)

    private static let yamlIndicators: Set<Character> = [
        "-", "?", ":", ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`",
    ]

    private static func needsQuoting(_ s: String) -> Bool {
        if s.isEmpty { return true }
        if s.first == " " || s.last == " " { return true }
        if s.contains("\n") { return true }
        if s.contains(": ") || s.contains(" #") { return true }
        if let first = s.first, yamlIndicators.contains(first) { return true }
        if Int(s) != nil || Double(s) != nil { return true }
        if ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(s.lowercased()) { return true }
        if s.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
        return out
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
