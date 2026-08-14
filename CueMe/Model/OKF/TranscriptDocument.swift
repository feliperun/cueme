import Foundation

/// Renders and parses a note's captured transcript as its own OKF concept
/// document, `raw/transcript.md` (design.md §4.11). It is capture, not
/// knowledge: separating it keeps the note's own `.md` human-sized and makes
/// a live-session snapshot cheap.
///
/// Grammar E. A turn is anchored by a line shaped like
/// `**<name> · <clock>** <!--cueme {…}-->`; the bold name and the clock are
/// renderings only — the speaker comes from `sp` and the time from `ts`,
/// never parsed back out of the visible text.
enum TranscriptDocument {
    private static let originMarker = "<!--cueme:orig-->"
    private static let translationMarker = "<!--cueme:tr-->"

    /// `nil` when `note.transcript` is `.notLoaded` — the caller must not
    /// write anything in that case, or a transcript that was merely never
    /// read into memory would be erased on disk (design.md §7).
    static func render(_ note: MemoryNote, producer: String = CueMeProducer.current) -> String? {
        guard case .loaded(let lines) = note.transcript else { return nil }

        let frontmatter = OKFFrontmatter.encode(transcriptFrontmatter(note, producer: producer), unknownYAML: "")
        let turns = renderTurnBlocks(lines, startedAt: note.audioTimelineStart, participantNames: note.participantNames)

        var body = ["", OKFSectionMarkers.marker(.transcript), "# Transcrição", ""]
        if !turns.isEmpty { body.append(turns) }
        body.append("")

        return frontmatter + "\n" + body.joined(separator: "\n")
    }

    static func parse(_ markdown: String) -> [TranscriptLine] {
        guard let parsed = OKFFrontmatter.decode(markdown, knownKeys: []) else { return [] }
        guard let section = OKFSectionMarkers.split(parsed.body).sections[.transcript] else { return [] }
        return parseTurnBlocks(section)
    }

    /// Turn blocks only, no frontmatter — reused as-is for the incremental
    /// append in T019, and guaranteed identical to the tail `write` produces
    /// for the same lines.
    static func renderTurnBlocks(_ lines: [TranscriptLine], startedAt: Date, participantNames: [Speaker: String]) -> String {
        lines
            .filter(\.isFinal)
            .map { renderTurnBlock($0, startedAt: startedAt, participantNames: participantNames) }
            .joined(separator: "\n\n")
    }

    // MARK: - Rendering

    private static func transcriptFrontmatter(_ note: MemoryNote, producer: String) -> [(String, OKFValue)] {
        var out: [(String, OKFValue)] = [
            ("type", .string("Transcript")),
            ("title", .string("Transcrição — \(note.title)")),
            ("description", .string("Captura verbatim da sessão de \(verbatimDateLabel(note.audioTimelineStart)).")),
            ("generated", .mapping([
                ("by", .string(producer)),
                ("at", .date(note.modifiedAt))
            ])),
            ("x_cueme_note_id", .string(note.id.uuidString.lowercased())),
            ("x_cueme_started_at", .date(note.audioTimelineStart))
        ]
        if !note.participantNames.isEmpty {
            out.append(("x_cueme_participant_names", .mapping(
                note.participantNames.map { ($0.key.rawValue, OKFValue.string($0.value)) }.sorted { $0.0 < $1.0 }
            )))
        }
        return out
    }

    private static func renderTurnBlock(_ line: TranscriptLine, startedAt: Date, participantNames: [Speaker: String]) -> String {
        var attributes: [(String, OKFValue)] = [
            ("id", .string(line.id.uuidString.lowercased())),
            ("sp", .string(line.speaker.rawValue)),
            ("ts", .date(line.ts))
        ]
        if let source = line.sourceTurnID { attributes.append(("src", .string(source.uuidString.lowercased()))) }
        if let editedAt = line.editedAt { attributes.append(("edited_at", .date(editedAt))) }

        let clock = SessionArchive.clock(line.ts.timeIntervalSince(startedAt))
        let anchor = "**\(turnSpeakerLabel(line.speaker, participantNames: participantNames)) · \(clock)**"
            + NoteItemAttributeCodec.encode(attributes)

        var block = [anchor, OKFSectionMarkers.escape(line.text)]
        if let original = line.originalText, !original.isEmpty {
            block.append(originMarker + OKFSectionMarkers.escape(original))
        }
        if let translation = line.translation, !translation.isEmpty {
            block.append(translationMarker + OKFSectionMarkers.escape(translation))
        }
        return block.joined(separator: "\n")
    }

    /// `dd/MM/yyyy` in UTC, so the document does not depend on the machine's
    /// local time zone.
    private static func verbatimDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private static func turnSpeakerLabel(_ speaker: Speaker, participantNames: [Speaker: String]) -> String {
        let name = participantNames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? speaker.label : name
    }

    // MARK: - Parsing

    private static func parseTurnBlocks(_ section: String) -> [TranscriptLine] {
        let lines = section.components(separatedBy: "\n")
        let anchors: [(index: Int, attributes: NoteItemAttributes)] = lines.enumerated().compactMap { index, line in
            turnAnchor(line).map { (index, $0) }
        }
        return anchors.enumerated().compactMap { offset, anchor in
            let regionEnd = offset + 1 < anchors.count ? anchors[offset + 1].index : lines.count
            return parseTurnAttributes(anchor.attributes, body: Array(lines[(anchor.index + 1)..<regionEnd]))
        }
    }

    /// A turn anchor is a bold `**…**` line ending in a non-empty item
    /// attribute comment. The visible `name · clock` text is never parsed —
    /// only its shape is checked, to reject an ordinary bold line in a turn's
    /// own text that carries no comment.
    private static func turnAnchor(_ line: String) -> NoteItemAttributes? {
        guard line.hasPrefix("**") else { return nil }
        let (visible, attributes) = NoteItemAttributeCodec.decode(line)
        guard !attributes.isEmpty, visible.hasPrefix("**"), visible.hasSuffix("**") else { return nil }
        return attributes
    }

    private static func parseTurnAttributes(_ attributes: NoteItemAttributes, body: [String]) -> TranscriptLine? {
        guard let id = attributes.uuidValue("id"),
              let speaker = attributes.stringValue("sp").flatMap(Speaker.init(rawValue:)),
              let ts = attributes.dateValue("ts") else { return nil }

        var lines = body
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }

        let origIndex = lines.firstIndex { $0.hasPrefix(originMarker) }
        let translationIndex = lines.firstIndex { $0.hasPrefix(translationMarker) }
        let textEnd = [origIndex, translationIndex].compactMap { $0 }.min() ?? lines.count

        let text = OKFSectionMarkers.unescape(lines[0..<textEnd].joined(separator: "\n"))
        let originalText = origIndex.map { OKFSectionMarkers.unescape(String(lines[$0].dropFirst(originMarker.count))) }
        let translation = translationIndex.map { OKFSectionMarkers.unescape(String(lines[$0].dropFirst(translationMarker.count))) }

        return TranscriptLine(
            id: id,
            speaker: speaker,
            text: text,
            translation: translation,
            isFinal: true,
            ts: ts,
            sourceTurnID: attributes.uuidValue("src"),
            originalText: originalText,
            editedAt: attributes.dateValue("edited_at")
        )
    }
}
