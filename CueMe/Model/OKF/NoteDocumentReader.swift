import Foundation

/// Parses a note's OKF concept document back into a `MemoryNote`. The inverse
/// of `NoteDocumentWriter` — everything that writer emits is read back here,
/// except the one section that is derived-only (`sources`, design.md §4.10)
/// and the fields that structurally have no home in the document at all: a
/// note's own `id` is never written (identity is the file's path, design.md
/// §1), so this reader always mints a fresh one.
///
/// Also where the seven parser-robustness rules (design.md §5) live: an
/// unknown frontmatter key or an unclaimed body line is never dropped, a
/// hand-edited `# H1` wins over a stale frontmatter `title`, and an item
/// added without its `<!--cueme …-->` comment gets a freshly minted id.
enum NoteDocumentReader {
    private static let knownFrontmatterKeys: Set<String> = [
        "type", "title", "description", "tags", "created_at", "updated_at", "generated",
        "sources", "x_cueme_links", "x_cueme_id", "x_cueme_kind", "x_cueme_mode", "x_cueme_origin",
        "x_cueme_training", "x_cueme_title_source", "x_cueme_ended_at", "x_cueme_lang",
        "x_cueme_participant_names", "x_cueme_models", "x_cueme_audio", "x_cueme_integrity",
        "x_cueme_transcript", "x_cueme_attachments", "x_cueme_vocabulary", "x_cueme_coach_feedback",
    ]

    /// A deterministic stand-in for "no date on file", used only when a note
    /// carries none of its own — e.g. a file with no `x_cueme_*` frontmatter
    /// at all. Never `Date()`: this parser is a pure function of its input.
    private static let unknownDate = Date(timeIntervalSince1970: 0)

    /// `nil` when there is no frontmatter or `type` is empty — the file is
    /// not a CueMe note and the caller should skip it (design.md §5 rule 7).
    ///
    /// `turns` is normally `x_cueme_transcript.turns` read by the caller from
    /// the same document; passing a different value lets a caller that has
    /// already loaded the transcript override it. The result is always
    /// `.notLoaded(turns:)` — this reader never reads `raw/` (design.md §7).
    static func parse(_ markdown: String, slug: String, turns: Int) -> MemoryNote? {
        guard let parsed = OKFFrontmatter.decode(markdown, knownKeys: knownFrontmatterKeys) else { return nil }
        let attrs = NoteItemAttributes(parsed.fields)
        let split = OKFSectionMarkers.split(parsed.body)

        let startedAt = attrs.dateValue("created_at") ?? unknownDate
        let modifiedAt = attrs.dateValue("updated_at") ?? startedAt
        let endedAt = attrs.dateValue("x_cueme_ended_at") ?? startedAt

        let (title, titleSource) = resolveTitle(
            h1: split.h1,
            frontmatterTitle: attrs.stringValue("title") ?? "",
            slug: slug,
            explicitSource: attrs.stringValue("x_cueme_title_source")
        )

        let mode = attrs.stringValue("x_cueme_mode").flatMap(Mode.init(rawValue:)) ?? .recording
        let origin = attrs.stringValue("x_cueme_origin").flatMap(SessionOrigin.init(rawValue:)) ?? .written
        let noteKind = attrs.stringValue("x_cueme_kind").flatMap(MemoryNoteKind.init(rawValue:))
            ?? MemoryNoteKind.inferred(mode: mode, origin: origin)

        let langAttrs = NoteItemAttributes(mapping(attrs["x_cueme_lang"]))
        let audioFields = mapping(attrs["x_cueme_audio"])
        let audioAttrs = NoteItemAttributes(audioFields)
        let integrityAttrs = NoteItemAttributes(mapping(attrs["x_cueme_integrity"]))
        let modelAttrs = NoteItemAttributes(mapping(attrs["x_cueme_models"]))
        let vocabularyAttrs = NoteItemAttributes(mapping(attrs["x_cueme_vocabulary"]))

        let participantAttrs = NoteItemAttributes(mapping(attrs["x_cueme_participant_names"]))
        let speakers: [Speaker] = [.self, .other]
        var participantNames: [Speaker: String] = [:]
        for speaker in speakers {
            if let name = participantAttrs.stringValue(speaker.rawValue) { participantNames[speaker] = name }
        }

        let vocabulary = CustomVocabulary(
            keyterms: vocabularyAttrs.stringsValue("keyterms") ?? [],
            replacements: stringMapping(vocabularyAttrs["replacements"])
        )

        let evidenceByID = parseEvidence(parsed.fields)
        var residual: [String] = split.residual.isEmpty ? [] : [split.residual]

        let takeaways = parseTakeawaySection(
            split.sections[.takeaways], sources: evidenceByID, fallbackDate: modifiedAt, residual: &residual
        )
        let decisions = parseReviewItems(split.sections[.decisions], sources: evidenceByID, residual: &residual)
        let openQuestions = parseReviewItems(split.sections[.openQuestions], sources: evidenceByID, residual: &residual)
        let notes = parseNotes(split.sections[.notes], fallbackDate: modifiedAt, residual: &residual)
        let minutes = parseMinutes(split.sections[.minutes], fallbackDate: modifiedAt, residual: &residual)
        let coachCards = parseCoach(split.sections[.coach], fallbackDate: modifiedAt, residual: &residual)
        let artifacts = parseArtifacts(split.sections[.artifacts], fallbackDate: modifiedAt, residual: &residual)
        let followUp = parseFollowUp(split.sections[.followUp])
        parseSourcesResidual(split.sections[.sources], residual: &residual)

        var note = MemoryNote(
            // The note's own identity, persisted so it survives a reload:
            // chunk ids, the transcript's back-reference and UI selection all
            // key on it. A missing key means a document written by hand, so
            // mint one and let the next save persist it.
            id: attrs.uuidValue("x_cueme_id") ?? UUID(),
            startedAt: startedAt,
            recordingStartedAt: audioAttrs.dateValue("recording_started_at"),
            endedAt: endedAt,
            mode: mode,
            training: attrs["x_cueme_training"].flatMap(boolValue) ?? false,
            conversationLang: langAttrs.stringValue("conversation") ?? "pt-BR",
            nativeLang: langAttrs.stringValue("native") ?? "pt-BR",
            goal: attrs.stringValue("description") ?? "",
            transcript: [],
            coachCards: coachCards,
            minutes: minutes,
            participantNames: participantNames,
            coachModel: modelAttrs.stringValue("coach").flatMap(CoachModel.init(rawValue:)),
            summaryModel: modelAttrs.stringValue("summary").flatMap(CoachModel.init(rawValue:)),
            vocabulary: vocabulary,
            hasAudio: !audioFields.isEmpty,
            audioDuration: audioAttrs.doubleValue("duration") ?? 0,
            integrity: NoteIntegrity(
                recoveries: intValue(integrityAttrs, "recoveries") ?? 0,
                errors: intValue(integrityAttrs, "errors") ?? 0
            ),
            coachFeedback: parseCoachFeedback(attrs["x_cueme_coach_feedback"]),
            notes: notes,
            takeaways: takeaways,
            origin: origin,
            displayTitle: title.isEmpty ? nil : title,
            review: MeetingReview(decisions: decisions, openQuestions: openQuestions, followUp: followUp),
            artifacts: artifacts,
            links: attrs.stringsValue("x_cueme_links") ?? [],
            noteKind: noteKind,
            markdownBody: OKFSectionMarkers.unescape(split.userBody),
            labels: attrs.stringsValue("tags") ?? [],
            attachments: parseAttachments(attrs["x_cueme_attachments"]),
            titleSource: titleSource,
            modifiedAt: modifiedAt,
            relativeFolderPath: nil,
            unknownFrontmatterYAML: parsed.unknownYAML,
            residualMarkdown: residual.joined(separator: "\n")
        )
        note.transcript = .notLoaded(turns: turns)
        return note
    }

    // MARK: - Title (design.md §5 rule 4)

    /// A hand-edited `# H1` that disagrees with the frontmatter `title` wins,
    /// and `titleSource` becomes `.user` — someone editing in a plain text
    /// editor changes the heading, not the frontmatter. When they agree (the
    /// normal case for anything this app wrote), `titleSource` comes from
    /// `x_cueme_title_source`. `slug` is the last-resort fallback when the
    /// document carries no title of its own anywhere.
    private static func resolveTitle(
        h1: String?, frontmatterTitle: String, slug: String, explicitSource: String?
    ) -> (title: String, source: NoteTitleSource) {
        if let h1, !h1.isEmpty, h1 != frontmatterTitle {
            return (h1, .user)
        }
        let title = !frontmatterTitle.isEmpty ? frontmatterTitle : (h1 ?? slug)
        let source = explicitSource.flatMap(NoteTitleSource.init(rawValue:)) ?? (title.isEmpty ? .fallback : .generated)
        return (title, source)
    }

    // MARK: - Evidence / sources (design.md §4.10)

    /// `sources[]` is evidence's single home (rule 2); this builds the
    /// lookup used to resolve `[^ev-…]` refs found in item text back into
    /// `MemoryEvidence`, keyed by the full `ev-<uuid>` id.
    private static func parseEvidence(_ fields: [String: OKFValue]) -> [String: MemoryEvidence] {
        guard case let .array(items)? = fields["sources"] else { return [:] }
        var out: [String: MemoryEvidence] = [:]
        for item in items {
            guard case let .mapping(pairs) = item else { continue }
            let attrs = NoteItemAttributes(dictionary(pairs))
            guard let sourceID = attrs.stringValue("id"),
                  let uuid = UUID(uuidString: String(sourceID.dropFirst(3))) else { continue }
            out[sourceID] = MemoryEvidence(
                id: uuid,
                turnID: attrs.uuidValue("x_turn_id"),
                timestamp: attrs.doubleValue("x_timestamp") ?? 0,
                quote: attrs.stringValue("title") ?? ""
            )
        }
        return out
    }

    /// Strips a trailing run of `[^ev-<uuid>]` refs from `text`, resolving
    /// each against `sources`. A ref that does not resolve stops the scan and
    /// is left in the text as literal characters (design.md §4.10).
    private static func splitEvidenceRefs(_ text: String, sources: [String: MemoryEvidence]) -> (text: String, evidence: [MemoryEvidence]) {
        var remaining = Substring(text)
        var found: [MemoryEvidence] = []
        while let range = remaining.range(of: #"\[\^(ev-[0-9a-fA-F-]{36})\]$"#, options: .regularExpression) {
            let token = remaining[range]
            let key = token.dropFirst(2).dropLast(1)
            guard let evidence = sources[String(key)] else { break }
            found.append(evidence)
            remaining = remaining[remaining.startIndex..<range.lowerBound]
        }
        return (String(remaining), found.reversed())
    }

    /// The `sources` section carries no state of its own — it is regenerated
    /// from `sources[]` on every write (rule 1's one exception) — but any
    /// line that is not a footnote definition is something the user appended
    /// (design.md §4.10's `## Apêndice` example) and must not be dropped.
    private static func parseSourcesResidual(_ raw: String?, residual: inout [String]) {
        guard let raw else { return }
        let footnotePattern = #"^\[\^ev-[0-9a-fA-F-]{36}\]: "#
        _ = scan(raw.components(separatedBy: "\n"), residual: &residual) { line -> Bool? in
            line.range(of: footnotePattern, options: .regularExpression) != nil ? true : nil
        }
    }

    // MARK: - Grammar C: takeaways, decisions, open-questions, notes

    private static func parseTakeawaySection(
        _ raw: String?, sources: [String: MemoryEvidence], fallbackDate: Date, residual: inout [String]
    ) -> [SessionTakeaway] {
        guard let raw else { return [] }
        return scan(stripHeadingLines(raw), residual: &residual) { line -> SessionTakeaway? in
            guard let (isDone, rest) = takeawayAnchor(line) else { return nil }
            let (visible, attributes) = NoteItemAttributeCodec.decode(rest)
            let (strippedText, evidence) = splitEvidenceRefs(visible, sources: sources)
            return SessionTakeaway(
                id: attributes.uuidValue("id") ?? UUID(),
                text: OKFSectionMarkers.unescape(strippedText),
                isDone: isDone,
                createdAt: attributes.dateValue("at") ?? fallbackDate,
                evidence: evidence,
                confidence: attributes.doubleValue("confidence"),
                assignee: attributes.stringValue("assignee"),
                dueAt: attributes.dateValue("due")
            )
        }
    }

    private static func takeawayAnchor(_ line: String) -> (isDone: Bool, rest: String)? {
        if line.hasPrefix("- [ ] ") { return (false, String(line.dropFirst(6))) }
        if line.hasPrefix("- [x] ") { return (true, String(line.dropFirst(6))) }
        return nil
    }

    private static func parseReviewItems(
        _ raw: String?, sources: [String: MemoryEvidence], residual: inout [String]
    ) -> [MeetingReviewItem] {
        guard let raw else { return [] }
        return scan(stripHeadingLines(raw), residual: &residual) { line -> MeetingReviewItem? in
            guard line.hasPrefix("- ") else { return nil }
            let (visible, attributes) = NoteItemAttributeCodec.decode(String(line.dropFirst(2)))
            let (strippedText, evidence) = splitEvidenceRefs(visible, sources: sources)
            return MeetingReviewItem(
                id: attributes.uuidValue("id") ?? UUID(),
                text: OKFSectionMarkers.unescape(strippedText),
                evidence: evidence,
                confidence: attributes.doubleValue("confidence"),
                supersedesID: attributes.uuidValue("supersedes")
            )
        }
    }

    private static func parseNotes(_ raw: String?, fallbackDate: Date, residual: inout [String]) -> [SessionNote] {
        guard let raw else { return [] }
        return scan(stripHeadingLines(raw), residual: &residual) { line -> SessionNote? in
            guard line.hasPrefix("- ") else { return nil }
            let (visible, attributes) = NoteItemAttributeCodec.decode(String(line.dropFirst(2)))
            return SessionNote(
                id: attributes.uuidValue("id") ?? UUID(),
                timeOffset: attributes.doubleValue("t") ?? 0,
                text: OKFSectionMarkers.unescape(visible),
                createdAt: attributes.dateValue("at") ?? fallbackDate
            )
        }
    }

    // MARK: - Grammar A: follow-up

    private static func parseFollowUp(_ raw: String?) -> String {
        guard let raw else { return "" }
        return joinedText(stripHeadingLines(raw))
    }

    // MARK: - Grammar B: minutes, coach, artifacts

    private static func parseMinutes(_ raw: String?, fallbackDate: Date, residual: inout [String]) -> MeetingMinutes {
        guard let raw else { return .empty }
        let (preamble, blocks) = splitAnchoredBlocks(stripHeadingLines(raw))
        let overview = joinedText(preamble)
        let topics: [MeetingTopic] = blocks.map { block in
            MeetingTopic(
                id: block.attributes.uuidValue("id") ?? UUID(),
                title: block.label,
                summary: joinedText(block.body),
                updatedAt: block.attributes.dateValue("at") ?? fallbackDate
            )
        }
        guard !overview.isEmpty || !topics.isEmpty else { return .empty }
        return MeetingMinutes(overview: overview, topics: topics, updatedAt: topics.map(\.updatedAt).max())
    }

    private static let sayConversationPrefix = "<!--cueme:say-conv-->"
    private static let sayNativePrefix = "<!--cueme:say-native-->"

    private static func parseCoach(_ raw: String?, fallbackDate: Date, residual: inout [String]) -> [CoachCard] {
        guard let raw else { return [] }
        let (preamble, blocks) = splitAnchoredBlocks(stripHeadingLines(raw))
        if let chunk = trimmedRun(preamble) { residual.append(chunk) }
        return blocks.map { block in
            let lines = block.body
            let sayConvIndex = lines.firstIndex { $0.hasPrefix(sayConversationPrefix) }
            let sayNativeIndex = lines.firstIndex { $0.hasPrefix(sayNativePrefix) }
            let guideEnd = [sayConvIndex, sayNativeIndex].compactMap { $0 }.min() ?? lines.count
            let sayConversation = sayConvIndex.map {
                OKFSectionMarkers.unescape(String(lines[$0].dropFirst(sayConversationPrefix.count)))
            }
            let sayNative = sayNativeIndex.map {
                OKFSectionMarkers.unescape(String(lines[$0].dropFirst(sayNativePrefix.count)))
            } ?? ""
            return CoachCard(
                id: block.attributes.uuidValue("id") ?? UUID(),
                guidePT: joinedText(Array(lines[0..<guideEnd])),
                sayConversation: sayConversation,
                sayNative: sayNative,
                keytermsConversation: block.attributes.stringsValue("keyterms") ?? [],
                kind: block.attributes.stringValue("kind").flatMap(CoachKind.init(rawValue:)) ?? .answer,
                severity: block.attributes.stringValue("severity").flatMap(Severity.init(rawValue:)) ?? .info,
                isStreaming: false,
                ts: block.attributes.dateValue("ts") ?? fallbackDate
            )
        }
    }

    private static func parseArtifacts(_ raw: String?, fallbackDate: Date, residual: inout [String]) -> [SessionArtifact] {
        guard let raw else { return [] }
        let (preamble, blocks) = splitAnchoredBlocks(stripHeadingLines(raw))
        if let chunk = trimmedRun(preamble) { residual.append(chunk) }
        return blocks.map { block in
            SessionArtifact(
                id: block.attributes.uuidValue("id") ?? UUID(),
                kind: block.attributes.stringValue("kind").flatMap(SessionArtifactKind.init(rawValue:)) ?? .custom,
                title: block.label,
                body: joinedText(block.body),
                createdAt: block.attributes.dateValue("at") ?? fallbackDate
            )
        }
    }

    /// Splits Grammar B content into its optional preamble and the anchored
    /// `### <label> <!--cueme {…}-->` blocks that follow it. Mirrors
    /// `TranscriptDocument`'s turn-block splitter (same anchor-then-region
    /// shape), kept local because that file is out of this task's scope.
    private static func splitAnchoredBlocks(
        _ lines: [String]
    ) -> (preamble: [String], blocks: [(label: String, attributes: NoteItemAttributes, body: [String])]) {
        let anchorPrefix = "### "
        let anchors: [(index: Int, label: String, attributes: NoteItemAttributes)] = lines.enumerated().compactMap { index, line in
            guard line.hasPrefix(anchorPrefix) else { return nil }
            let (visible, attributes) = NoteItemAttributeCodec.decode(line)
            guard !attributes.isEmpty, visible.hasPrefix(anchorPrefix) else { return nil }
            return (index, String(visible.dropFirst(anchorPrefix.count)), attributes)
        }
        let preambleEnd = anchors.first?.index ?? lines.count
        let blocks = anchors.enumerated().map { offset, anchor -> (label: String, attributes: NoteItemAttributes, body: [String]) in
            let regionEnd = offset + 1 < anchors.count ? anchors[offset + 1].index : lines.count
            return (anchor.label, anchor.attributes, Array(lines[(anchor.index + 1)..<regionEnd]))
        }
        return (Array(lines[0..<preambleEnd]), blocks)
    }

    // MARK: - Line scanning shared by every grammar

    /// Classifies each line via `classify`; a run of unclaimed lines between
    /// (or around) claimed ones is trimmed of its blank borders and flushed
    /// as one residual chunk, preserving any content in between. A run that
    /// is blank throughout is discarded rather than residualized — the
    /// blank line every section ends with is formatting, not content
    /// (design.md §5 rule 2 only asks to preserve *unclaimed* text).
    private static func scan<T>(_ lines: [String], residual: inout [String], classify: (String) -> T?) -> [T] {
        var claimed: [T] = []
        var pending: [String] = []
        for line in lines {
            if let value = classify(line) {
                if let chunk = trimmedRun(pending) { residual.append(chunk) }
                pending = []
                claimed.append(value)
            } else {
                pending.append(line)
            }
        }
        if let chunk = trimmedRun(pending) { residual.append(chunk) }
        return claimed
    }

    private static func trimmedRun(_ lines: [String]) -> String? {
        var run = lines
        while let first = run.first, first.trimmingCharacters(in: .whitespaces).isEmpty { run.removeFirst() }
        while let last = run.last, last.trimmingCharacters(in: .whitespaces).isEmpty { run.removeLast() }
        return run.isEmpty ? nil : run.joined(separator: "\n")
    }

    /// Drops a leading canonical `## <heading>` line (and the blank line
    /// after it, if any) — the heading is decoration keyed off the marker,
    /// not the text, and is regenerated verbatim on write regardless of what
    /// it said (design.md §4.1, AC8).
    private static func stripHeadingLines(_ raw: String) -> [String] {
        var lines = raw.components(separatedBy: "\n")
        trimLeadingBlank(&lines)
        if let first = lines.first, first.hasPrefix("## ") {
            lines.removeFirst()
            trimLeadingBlank(&lines)
        }
        return lines
    }

    private static func trimLeadingBlank(_ lines: inout [String]) {
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
    }

    /// Joins, unescapes (design.md §4.12) and trims the blank border left by
    /// slicing a fixed line range out of a larger section.
    private static func joinedText(_ lines: [String]) -> String {
        OKFSectionMarkers.unescape(lines.joined(separator: "\n")).trimmingCharacters(in: .newlines)
    }

    // MARK: - Scalar frontmatter mappings

    private static func parseAttachments(_ value: OKFValue?) -> [NoteAttachment] {
        guard case let .array(items)? = value else { return [] }
        return items.compactMap { item -> NoteAttachment? in
            guard case let .mapping(pairs) = item else { return nil }
            let attrs = NoteItemAttributes(dictionary(pairs))
            guard let id = attrs.uuidValue("id"), let file = attrs.stringValue("file") else { return nil }
            return NoteAttachment(
                id: id,
                filename: file,
                kind: attrs.stringValue("kind").flatMap(NoteAttachmentKind.init(rawValue:)) ?? .file,
                addedAt: attrs.dateValue("added_at") ?? unknownDate
            )
        }
    }

    private static func parseCoachFeedback(_ value: OKFValue?) -> [UUID: CoachFeedback] {
        guard case let .mapping(pairs)? = value else { return [:] }
        var out: [UUID: CoachFeedback] = [:]
        for (key, raw) in pairs {
            guard let id = UUID(uuidString: key),
                  case let .string(feedbackRaw, _) = raw,
                  let feedback = CoachFeedback(rawValue: feedbackRaw) else { continue }
            out[id] = feedback
        }
        return out
    }

    private static func mapping(_ value: OKFValue?) -> [String: OKFValue] {
        guard case let .mapping(pairs)? = value else { return [:] }
        return dictionary(pairs)
    }

    private static func stringMapping(_ value: OKFValue?) -> [String: String] {
        guard case let .mapping(pairs)? = value else { return [:] }
        var out: [String: String] = [:]
        for (key, value) in pairs {
            if case let .string(raw, _) = value { out[key] = raw }
        }
        return out
    }

    private static func dictionary(_ pairs: [(String, OKFValue)]) -> [String: OKFValue] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private static func boolValue(_ value: OKFValue) -> Bool? {
        guard case let .bool(b) = value else { return nil }
        return b
    }

    private static func intValue(_ attrs: NoteItemAttributes, _ key: String) -> Int? {
        guard case let .int(i)? = attrs[key] else { return nil }
        return i
    }
}
