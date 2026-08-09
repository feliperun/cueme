import Foundation

enum SessionOrigin: String, Codable, CaseIterable, Sendable, Identifiable {
    case live
    case audioFile
    case voiceMemo
    case written

    var id: String { rawValue }
    var supportsLiveCoach: Bool { self == .live }

    var label: String {
        switch self {
        case .live: return "Ao vivo"
        case .audioFile: return "Áudio importado"
        case .voiceMemo: return "Voice Memo"
        case .written: return "Escrita"
        }
    }
}

/// The canonical domain entity. Session-specific fields are optional enrichment
/// around a user-owned Markdown note rather than the product's primary object.
struct MemoryNote: Codable, Identifiable, Sendable, Hashable {
    static let currentSchemaVersion = 4
    static func == (l: MemoryNote, r: MemoryNote) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    var schemaVersion: Int
    var startedAt: Date
    var recordingStartedAt: Date?
    var endedAt: Date
    var mode: Mode
    var training: Bool
    var conversationLang: String
    var nativeLang: String
    var goal: String
    var transcript: [TranscriptLine]
    var coachCards: [CoachCard]
    var summaryBullets: [String]
    var minutes: MeetingMinutes
    var participantNames: [Speaker: String]
    var coachModel: CoachModel?
    var summaryModel: CoachModel?
    var vocabulary: CustomVocabulary
    var hasAudio: Bool
    var audioDuration: TimeInterval
    var integrity: NoteIntegrity
    var coachFeedback: [UUID: CoachFeedback]
    var archiveFolderName: String
    var notes: [SessionNote]
    var takeaways: [SessionTakeaway]
    var origin: SessionOrigin
    var displayTitle: String?
    var review: MeetingReview
    var artifacts: [SessionArtifact]
    var projectID: UUID?
    var personIDs: [UUID]
    var noteKind: MemoryNoteKind
    var markdownBody: String
    var labels: [String]
    var attachments: [NoteAttachment]
    var titleSource: NoteTitleSource
    var modifiedAt: Date
    var relativeFolderPath: String?

    init(
        id: UUID = UUID(),
        schemaVersion: Int = MemoryNote.currentSchemaVersion,
        startedAt: Date,
        recordingStartedAt: Date? = nil,
        endedAt: Date = Date(),
        mode: Mode,
        training: Bool,
        conversationLang: String,
        nativeLang: String,
        goal: String,
        transcript: [TranscriptLine],
        coachCards: [CoachCard],
        summaryBullets: [String],
        minutes: MeetingMinutes = .empty,
        participantNames: [Speaker: String] = [.self: "Você", .other: "Interlocutor"],
        coachModel: CoachModel? = nil,
        summaryModel: CoachModel? = nil,
        vocabulary: CustomVocabulary = .init(),
        hasAudio: Bool = false,
        audioDuration: TimeInterval = 0,
        integrity: NoteIntegrity = .init(),
        coachFeedback: [UUID: CoachFeedback] = [:],
        archiveFolderName: String? = nil,
        notes: [SessionNote] = [],
        takeaways: [SessionTakeaway] = [],
        origin: SessionOrigin = .live,
        displayTitle: String? = nil,
        review: MeetingReview = .empty,
        artifacts: [SessionArtifact] = [],
        projectID: UUID? = nil,
        personIDs: [UUID] = [],
        noteKind: MemoryNoteKind? = nil,
        markdownBody: String = "",
        labels: [String] = [],
        attachments: [NoteAttachment] = [],
        titleSource: NoteTitleSource? = nil,
        modifiedAt: Date? = nil,
        relativeFolderPath: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.startedAt = startedAt
        self.recordingStartedAt = recordingStartedAt
        self.endedAt = endedAt
        self.mode = mode
        self.training = training
        self.conversationLang = conversationLang
        self.nativeLang = nativeLang
        self.goal = goal
        self.transcript = transcript
        self.coachCards = coachCards
        self.summaryBullets = summaryBullets
        self.minutes = minutes
        self.participantNames = participantNames
        self.coachModel = coachModel
        self.summaryModel = summaryModel
        self.vocabulary = vocabulary
        self.hasAudio = hasAudio
        self.audioDuration = audioDuration
        self.integrity = integrity
        self.coachFeedback = coachFeedback
        let resolvedFolderName = archiveFolderName ?? SessionArchive.folderName(startedAt: startedAt, id: id)
        self.archiveFolderName = resolvedFolderName
        self.notes = notes
        self.takeaways = takeaways
        self.origin = origin
        self.displayTitle = displayTitle
        self.review = review
        self.artifacts = artifacts
        self.projectID = projectID
        self.personIDs = personIDs
        self.noteKind = noteKind ?? MemoryNoteKind.inferred(mode: mode, origin: origin)
        self.markdownBody = markdownBody
        self.labels = Self.normalizedLabels(labels)
        self.attachments = attachments
        self.titleSource = titleSource ?? (displayTitle == nil ? .fallback : .generated)
        self.modifiedAt = modifiedAt ?? endedAt
        self.relativeFolderPath = relativeFolderPath ?? "_Inbox/\(resolvedFolderName)"
    }

    /// Decode tolerante: sessões salvas antes do gravador não têm hasAudio/audioDuration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        recordingStartedAt = try c.decodeIfPresent(Date.self, forKey: .recordingStartedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        mode = try c.decode(Mode.self, forKey: .mode)
        training = try c.decode(Bool.self, forKey: .training)
        conversationLang = try c.decode(String.self, forKey: .conversationLang)
        nativeLang = try c.decode(String.self, forKey: .nativeLang)
        goal = try c.decode(String.self, forKey: .goal)
        transcript = try c.decode([TranscriptLine].self, forKey: .transcript)
        coachCards = try c.decode([CoachCard].self, forKey: .coachCards)
        summaryBullets = try c.decode([String].self, forKey: .summaryBullets)
        minutes = try c.decodeIfPresent(MeetingMinutes.self, forKey: .minutes)
            ?? (summaryBullets.isEmpty ? .empty : MeetingMinutes(overview: summaryBullets.joined(separator: " ")))
        participantNames = try c.decodeIfPresent([Speaker: String].self, forKey: .participantNames)
            ?? [.self: "Você", .other: "Interlocutor"]
        coachModel = try c.decodeIfPresent(CoachModel.self, forKey: .coachModel)
        summaryModel = try c.decodeIfPresent(CoachModel.self, forKey: .summaryModel)
        vocabulary = try c.decodeIfPresent(CustomVocabulary.self, forKey: .vocabulary) ?? .init()
        hasAudio = try c.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
        audioDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .audioDuration) ?? 0
        integrity = try c.decodeIfPresent(NoteIntegrity.self, forKey: .integrity) ?? .init()
        coachFeedback = try c.decodeIfPresent([UUID: CoachFeedback].self, forKey: .coachFeedback) ?? [:]
        archiveFolderName = try c.decodeIfPresent(String.self, forKey: .archiveFolderName)
            ?? SessionArchive.folderName(startedAt: startedAt, id: id)
        notes = try c.decodeIfPresent([SessionNote].self, forKey: .notes) ?? []
        takeaways = try c.decodeIfPresent([SessionTakeaway].self, forKey: .takeaways) ?? []
        origin = try c.decodeIfPresent(SessionOrigin.self, forKey: .origin) ?? .live
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
        review = try c.decodeIfPresent(MeetingReview.self, forKey: .review) ?? .empty
        artifacts = try c.decodeIfPresent([SessionArtifact].self, forKey: .artifacts) ?? []
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        personIDs = try c.decodeIfPresent([UUID].self, forKey: .personIDs) ?? []
        noteKind = try c.decodeIfPresent(MemoryNoteKind.self, forKey: .noteKind)
            ?? MemoryNoteKind.inferred(mode: mode, origin: origin)
        markdownBody = try c.decodeIfPresent(String.self, forKey: .markdownBody) ?? ""
        labels = Self.normalizedLabels(try c.decodeIfPresent([String].self, forKey: .labels) ?? [])
        attachments = try c.decodeIfPresent([NoteAttachment].self, forKey: .attachments) ?? []
        titleSource = try c.decodeIfPresent(NoteTitleSource.self, forKey: .titleSource)
            ?? (displayTitle == nil ? .fallback : .generated)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? endedAt
        relativeFolderPath = try c.decodeIfPresent(String.self, forKey: .relativeFolderPath)
    }

    /// Lowercased, de-duplicated, length-capped and sorted. Lives here rather
    /// than beside `setLabels` because the initialiser normalizes too, and
    /// Swift's `private` is file-scoped.
    static func normalizedLabels(_ values: [String]) -> [String] {
        Array(Set(values.compactMap { value -> String? in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return clean.isEmpty ? nil : String(clean.prefix(48))
        })).sorted()
    }
}
