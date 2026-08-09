import Foundation
import Yams

/// A closed set of the value shapes an OKF frontmatter field can hold.
///
/// `alwaysQuoted` on `.string` records whether the scalar must be rendered
/// double-quoted regardless of content (design.md §3 quoting policy: dates,
/// paths, URIs and fragments are always quoted; `decode` recovers this from
/// the original scalar's style so a round trip preserves it without the
/// caller having to know which fields are path-like).
enum OKFValue {
    case string(String, alwaysQuoted: Bool = false)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case array([OKFValue])
    case mapping([(String, OKFValue)])
}

/// Codec for the YAML frontmatter block of an OKF note. Separates the
/// frontmatter from the Markdown body, decodes known fields into typed
/// `OKFValue`s, and preserves keys this build does not recognize verbatim so
/// that opening a note written by another tool and saving it never drops
/// someone else's metadata (OKF requires consumers to preserve unknown
/// keys).
///
/// No Yams type (`Node`, `Emitter`, ...) ever appears in this file's public
/// API. They are not `Sendable` under Swift 6 strict concurrency (design.md
/// §10 risk 5), so all Yams usage stays inside private, synchronous,
/// non-escaping calls confined to `decode`.
enum OKFFrontmatter {
    /// Emits frontmatter in block style, including the `---` delimiters.
    /// The order of `ordered` is the emission order; `unknownYAML` is
    /// appended verbatim after all known keys. Block style throughout, per
    /// design.md §3.
    static func encode(_ ordered: [(String, OKFValue)], unknownYAML: String) -> String {
        var lines = ["---"]
        for (key, value) in ordered {
            lines.append(contentsOf: emitField(key, value, indent: 0))
        }
        if !unknownYAML.isEmpty {
            lines.append(contentsOf: unknownYAML.components(separatedBy: "\n"))
        }
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    struct Parsed {
        let fields: [String: OKFValue]
        let unknownYAML: String
        let body: String
    }

    /// `nil` when there is no frontmatter, the YAML does not parse, or
    /// `type` is missing or empty.
    static func decode(_ markdown: String, knownKeys: Set<String>) -> Parsed? {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---",
              let closeIndex = lines.dropFirst().firstIndex(of: "---") else { return nil }

        let yamlLines = Array(lines[1..<closeIndex])
        let yamlText = yamlLines.joined(separator: "\n")
        guard !yamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let root = try? Yams.compose(yaml: yamlText),
              let mapping = root.mapping else { return nil }

        guard let type = mapping["type"]?.string, !type.isEmpty else { return nil }

        var fields: [String: OKFValue] = [:]
        var unknownBlocks: [String] = []
        let entries = Array(mapping)
        for (index, entry) in entries.enumerated() {
            guard let key = entry.key.string else { continue }
            if knownKeys.contains(key) {
                fields[key] = convert(entry.value)
            } else {
                let startLine = entry.key.mark?.line ?? 1
                let endLine = index + 1 < entries.count
                    ? (entries[index + 1].key.mark?.line ?? yamlLines.count + 1)
                    : yamlLines.count + 1
                let startIdx = max(0, startLine - 1)
                let endIdx = min(yamlLines.count, max(startIdx, endLine - 1))
                unknownBlocks.append(yamlLines[startIdx..<endIdx].joined(separator: "\n"))
            }
        }

        var body = lines[(closeIndex + 1)...].joined(separator: "\n")
        if body.hasPrefix("\n") { body.removeFirst() }

        return Parsed(fields: fields, unknownYAML: unknownBlocks.joined(separator: "\n"), body: body)
    }

    // MARK: - Yams Node -> OKFValue (private: Node never escapes this file)

    private static func convert(_ node: Node) -> OKFValue {
        if let mapping = node.mapping {
            return .mapping(mapping.map { ($0.key.string ?? "", convert($0.value)) })
        }
        if let sequence = node.sequence {
            return .array(sequence.map(convert))
        }
        // Yams' typed accessors already respect scalar style (a quoted "true"
        // or "42" does not construct as Bool/Int/Double), so trying them in
        // order and falling back to .string is enough — no need to inspect
        // Node's (non-public) resolved tag name.
        if let b = node.bool { return .bool(b) }
        if let i = node.int { return .int(i) }
        if let d = node.float { return .double(d) }
        let style = node.scalar?.style
        let quoted = style == .doubleQuoted || style == .singleQuoted
        return .string(node.string ?? "", alwaysQuoted: quoted)
    }

    // MARK: - OKFValue -> lines

    private static func emitField(_ key: String, _ value: OKFValue, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        switch value {
        case .array(let items):
            var out = ["\(pad)\(key):"]
            for item in items { out.append(contentsOf: emitItem(item, indent: indent + 2)) }
            return out
        case .mapping(let pairs):
            var out = ["\(pad)\(key):"]
            for (k, v) in pairs { out.append(contentsOf: emitField(k, v, indent: indent + 2)) }
            return out
        default:
            return ["\(pad)\(key): \(scalarText(value))"]
        }
    }

    private static func emitItem(_ value: OKFValue, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        switch value {
        case .mapping(let pairs):
            var out: [String] = []
            for (index, pair) in pairs.enumerated() {
                let fieldLines = emitField(pair.0, pair.1, indent: indent + 2)
                if index == 0, let first = fieldLines.first {
                    let content = first.dropFirst(indent + 2)
                    out.append("\(pad)- \(content)")
                    out.append(contentsOf: fieldLines.dropFirst())
                } else {
                    out.append(contentsOf: fieldLines)
                }
            }
            return out
        case .array(let items):
            var out = ["\(pad)-"]
            for item in items { out.append(contentsOf: emitItem(item, indent: indent + 2)) }
            return out
        default:
            return ["\(pad)- \(scalarText(value))"]
        }
    }

    private static func scalarText(_ value: OKFValue) -> String {
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
        case .array, .mapping:
            preconditionFailure("scalarText called on a composite OKFValue")
        }
    }

    // MARK: - Quoting policy (design.md §3)

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
