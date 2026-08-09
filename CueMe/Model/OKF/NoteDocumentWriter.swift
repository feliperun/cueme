import Foundation

/// Renders a note as its OKF concept document. The executable definition of the
/// output is `specs/okf-corpus/contracts/note.md`; this file must reproduce it
/// byte for byte.
///
/// Everything emitted here is read back by `NoteDocumentReader`. The one
/// exception is the `sources` section, which renders footnote definitions from
/// the `sources` frontmatter so `[^ev-…]` references resolve in any Markdown
/// renderer — it carries no state the frontmatter does not.
enum NoteDocumentWriter {
    static func render(_ note: MemoryNote, producer: String = CueMeProducer.current) -> String {
        let evidence = collectedEvidence(note)
        let frontmatter = OKFFrontmatter.encode(
            fields(note, producer: producer, evidence: evidence),
            unknownYAML: note.unknownFrontmatterYAML
        )
        return frontmatter + "\n" + NoteBodyWriter.render(note, evidence: evidence)
    }

    // MARK: - Frontmatter

    private static func fields(
        _ note: MemoryNote,
        producer: String,
        evidence: [MemoryEvidence]
    ) -> [(String, OKFValue)] {
        okfFields(note, producer: producer, evidence: evidence)
            + sessionFields(note)
            + collectionFields(note)
    }

    /// The keys OKF itself defines, in spec order.
    private static func okfFields(
        _ note: MemoryNote,
        producer: String,
        evidence: [MemoryEvidence]
    ) -> [(String, OKFValue)] {
        var out: [(String, OKFValue)] = [
            ("type", .string("Note")),
            ("title", .string(note.title))
        ]
        if !note.goal.isEmpty { out.append(("description", .string(note.goal))) }
        if !note.labels.isEmpty { out.append(("tags", .array(note.labels.sorted().map { .string($0) }))) }
        out.append(("created_at", .date(note.startedAt)))
        out.append(("updated_at", .date(note.modifiedAt)))
        out.append(("generated", .mapping([
            ("by", .string(producer)),
            ("at", .date(note.modifiedAt))
        ])))
        if !evidence.isEmpty { out.append(("sources", .array(evidence.map(source)))) }
        if !note.links.isEmpty {
            out.append(("x_cueme_links", .array(note.links.sorted().map { .string($0, alwaysQuoted: true) })))
        }
        return out
    }

    /// Scalar session metadata that OKF has no home for.
    private static func sessionFields(_ note: MemoryNote) -> [(String, OKFValue)] {
        var out: [(String, OKFValue)] = [
            ("x_cueme_kind", .string(note.noteKind.rawValue)),
            ("x_cueme_mode", .string(note.mode.rawValue)),
            ("x_cueme_origin", .string(note.origin.rawValue)),
            ("x_cueme_training", .bool(note.training)),
            ("x_cueme_title_source", .string(note.titleSource.rawValue)),
            ("x_cueme_ended_at", .date(note.endedAt)),
            ("x_cueme_lang", .mapping([
                ("conversation", .string(note.conversationLang)),
                ("native", .string(note.nativeLang))
            ]))
        ]
        if !note.participantNames.isEmpty {
            out.append(("x_cueme_participant_names", .mapping(
                note.participantNames
                    .map { ($0.key.rawValue, OKFValue.string($0.value)) }
                    .sorted { $0.0 < $1.0 }
            )))
        }
        var models: [(String, OKFValue)] = []
        if let coach = note.coachModel { models.append(("coach", .string(coach.rawValue))) }
        if let summary = note.summaryModel { models.append(("summary", .string(summary.rawValue))) }
        if !models.isEmpty { out.append(("x_cueme_models", .mapping(models))) }
        if note.hasAudio {
            var audio: [(String, OKFValue)] = [("duration", .double(note.audioDuration))]
            if let started = note.recordingStartedAt {
                audio.append(("recording_started_at", .date(started)))
            }
            out.append(("x_cueme_audio", .mapping(audio)))
        }
        out.append(("x_cueme_integrity", .mapping([
            ("errors", .int(note.integrity.errors)),
            ("recoveries", .int(note.integrity.recoveries))
        ])))
        return out
    }

    /// Collections, each omitted entirely when empty.
    private static func collectionFields(_ note: MemoryNote) -> [(String, OKFValue)] {
        var out: [(String, OKFValue)] = []
        if note.transcript.turnCount > 0 {
            out.append(("x_cueme_transcript", .mapping([
                ("file", .string(OKFBundle.transcriptRelativePath, alwaysQuoted: true)),
                ("turns", .int(note.transcript.turnCount))
            ])))
        }
        if !note.attachments.isEmpty {
            out.append(("x_cueme_attachments", .array(
                note.attachments.sorted { $0.id.uuidString < $1.id.uuidString }.map(attachment)
            )))
        }
        var vocabulary: [(String, OKFValue)] = []
        if !note.vocabulary.keyterms.isEmpty {
            vocabulary.append(("keyterms", .array(note.vocabulary.keyterms.sorted().map { .string($0) })))
        }
        if !note.vocabulary.replacements.isEmpty {
            vocabulary.append(("replacements", .mapping(
                note.vocabulary.replacements.map { ($0.key, OKFValue.string($0.value)) }.sorted { $0.0 < $1.0 }
            )))
        }
        if !vocabulary.isEmpty { out.append(("x_cueme_vocabulary", .mapping(vocabulary))) }
        if !note.coachFeedback.isEmpty {
            out.append(("x_cueme_coach_feedback", .mapping(
                note.coachFeedback
                    .map { ($0.key.uuidString.lowercased(), OKFValue.string($0.value.rawValue)) }
                    .sorted { $0.0 < $1.0 }
            )))
        }
        return out
    }

    private static func source(_ item: MemoryEvidence) -> OKFValue {
        var pairs: [(String, OKFValue)] = [("id", .string(sourceID(item)))]
        let fragment = item.turnID.map { "\(OKFBundle.transcriptRelativePath)#t-\($0.uuidString.lowercased())" }
        pairs.append(("resource", .string(fragment ?? OKFBundle.transcriptRelativePath, alwaysQuoted: true)))
        pairs.append(("title", .string(item.quote)))
        pairs.append(("x_timestamp", .double(item.timestamp)))
        if let turnID = item.turnID {
            pairs.append(("x_turn_id", .string(turnID.uuidString.lowercased())))
        }
        return .mapping(pairs)
    }

    private static func attachment(_ item: NoteAttachment) -> OKFValue {
        .mapping([
            ("id", .string(item.id.uuidString.lowercased())),
            ("file", .string(item.filename, alwaysQuoted: true)),
            ("kind", .string(item.kind.rawValue)),
            ("added_at", .date(item.addedAt))
        ])
    }

    static func sourceID(_ item: MemoryEvidence) -> String { "ev-\(item.id.uuidString.lowercased())" }

    /// Every evidence entry cited anywhere in the note, de-duplicated by id.
    /// The same quote is routinely attached to a takeaway, a decision and a
    /// question; storing it once is the point of moving evidence to `sources`.
    static func collectedEvidence(_ note: MemoryNote) -> [MemoryEvidence] {
        var seen = Set<UUID>()
        var out: [MemoryEvidence] = []
        for item in note.takeaways.flatMap(\.evidence)
            + note.review.decisions.flatMap(\.evidence)
            + note.review.openQuestions.flatMap(\.evidence) where seen.insert(item.id).inserted {
            out.append(item)
        }
        return out.sorted { sourceID($0) < sourceID($1) }
    }
}
