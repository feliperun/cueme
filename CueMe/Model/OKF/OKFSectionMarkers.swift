import Foundation

/// The named sections that can appear in a note's Markdown body, each identified
/// by a `<!-- cueme:<name> -->` marker at column 0. See design.md §4.1.
enum OKFSection: String, CaseIterable, Sendable {
    case minutes
    case takeaways
    case decisions
    case openQuestions = "open-questions"
    case followUp = "follow-up"
    case notes
    case coach
    case artifacts
    case sources
    case transcript
}

/// Splits a note's Markdown body into its H1, free-form user body, marker-delimited
/// sections and residual (unclaimed) content, and provides the escape rule that
/// protects free text containing a marker-looking line.
///
/// Pure `String` work — this file never imports Yams (ADR 0044). Frontmatter is
/// `OKFFrontmatter`'s job; this type only ever sees the body.
enum OKFSectionMarkers {

    struct Split: Equatable {
        let h1: String?
        let userBody: String
        let sections: [OKFSection: String]
        let residual: String
    }

    /// The canonical marker text for a section, e.g. `"<!-- cueme:minutes -->"`.
    static func marker(_ section: OKFSection) -> String {
        "<!-- cueme:\(section.rawValue) -->"
    }

    /// Splits `body` into its H1, user body, known sections and residual.
    ///
    /// A marker is `^<!--\s?cueme:<name>\s?-->\s*$` at column 0. A section runs
    /// from its marker to the next marker line or EOF — there is no closing tag.
    /// A marker whose name is not a known `OKFSection` sends its entire region,
    /// including the marker line itself, to `residual`. A section that appears
    /// more than once has its regions concatenated in the order they appear.
    static func split(_ body: String) -> Split {
        let lines = body.components(separatedBy: "\n")

        let markerLines: [(lineIndex: Int, section: OKFSection?)] = lines.enumerated()
            .compactMap { index, line in
                guard let name = markerName(in: line) else { return nil }
                return (index, OKFSection(rawValue: name))
            }

        let preambleEnd = markerLines.first?.lineIndex ?? lines.count
        let preamble = Array(lines[0..<preambleEnd])

        var cursor = 0
        while cursor < preamble.count, isBlank(preamble[cursor]) {
            cursor += 1
        }
        var h1: String?
        if cursor < preamble.count, preamble[cursor].hasPrefix("# ") {
            h1 = String(preamble[cursor].dropFirst(2))
            cursor += 1
        }
        let userBody = trimBlankBorders(Array(preamble[cursor...])).joined(separator: "\n")

        var sections: [OKFSection: String] = [:]
        var residualParts: [String] = []

        for (index, marker) in markerLines.enumerated() {
            let regionEnd = index + 1 < markerLines.count ? markerLines[index + 1].lineIndex : lines.count
            if let section = marker.section {
                let content = lines[(marker.lineIndex + 1)..<regionEnd].joined(separator: "\n")
                if let existing = sections[section] {
                    sections[section] = existing + "\n" + content
                } else {
                    sections[section] = content
                }
            } else {
                residualParts.append(lines[marker.lineIndex..<regionEnd].joined(separator: "\n"))
            }
        }

        return Split(h1: h1, userBody: userBody, sections: sections, residual: residualParts.joined(separator: "\n"))
    }

    /// Escapes free text before writing: a line matching `^\\*<!--\s?cueme` gains
    /// one leading backslash, so a literal marker- or attribute-comment-looking
    /// line inside user content is never mistaken for the real thing on the next
    /// read. `\<` is a valid Markdown escape that renders as `<`.
    static func escape(_ text: String) -> String {
        transformLines(text) { line in
            looksLikeCueme(line) ? "\\" + line : line
        }
    }

    /// Reverses `escape`: a line matching `^\\+<!--\s?cueme` loses one leading
    /// backslash. Applying `escape` and `unescape` the same number of times is
    /// always an exact round trip, including when each is applied more than once.
    static func unescape(_ text: String) -> String {
        transformLines(text) { line in
            guard line.hasPrefix("\\"), looksLikeCueme(line) else { return line }
            return String(line.dropFirst())
        }
    }

    // MARK: - Private

    private static func transformLines(_ text: String, _ transform: (String) -> String) -> String {
        text.components(separatedBy: "\n").map(transform).joined(separator: "\n")
    }

    /// True when `line`, after stripping any number of leading backslashes,
    /// starts with `<!--` optionally followed by one space and then `cueme`.
    /// Matches both the section-marker form (`<!--cueme:name-->`) and the
    /// item-attribute comment form (`<!--cueme {...}-->`).
    private static func looksLikeCueme(_ line: String) -> Bool {
        var rest = Substring(line)
        while rest.first == "\\" {
            rest = rest.dropFirst()
        }
        guard rest.hasPrefix("<!--") else { return false }
        rest = rest.dropFirst(4)
        if rest.first == " " {
            rest = rest.dropFirst()
        }
        return rest.hasPrefix("cueme")
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func trimBlankBorders(_ lines: [String]) -> [String] {
        var start = 0
        var end = lines.count
        while start < end, isBlank(lines[start]) { start += 1 }
        while end > start, isBlank(lines[end - 1]) { end -= 1 }
        return Array(lines[start..<end])
    }

    /// Returns the marker name (`"minutes"`, `"open-questions"`, an unknown name,
    /// …) when `line` is exactly a marker line at column 0, else `nil`.
    private static func markerName(in line: String) -> String? {
        guard line.hasPrefix("<!--") else { return nil }
        var rest = line.dropFirst(4)
        if rest.first == " " {
            rest = rest.dropFirst()
        }
        guard rest.hasPrefix("cueme:") else { return nil }
        rest = rest.dropFirst(6)
        guard let closeRange = rest.range(of: "-->") else { return nil }
        var name = String(rest[rest.startIndex..<closeRange.lowerBound])
        if name.hasSuffix(" ") {
            name.removeLast()
        }
        guard !name.isEmpty, !name.contains(" "), !name.contains("\t") else { return nil }
        let trailer = rest[closeRange.upperBound...]
        guard trailer.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return name
    }
}
