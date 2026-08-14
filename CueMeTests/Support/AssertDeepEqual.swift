import XCTest
@testable import CueMe

/// Number of stored properties on `MemoryNote`, pinned so that adding or
/// removing one breaks a test instead of silently escaping the comparison
/// below. Bump it only together with `deepEqualFailures`.
enum MemoryNoteFieldCount {
    static let pinned = 37
}

struct DeepEqualFailure {
    let field: String
    let lhs: String
    let rhs: String
}

/// Field-by-field comparison of two notes.
///
/// `MemoryNote` conforms to `Equatable` by `id` alone, so `XCTAssertEqual` on
/// two notes passes whenever the ids match — regardless of every other field.
/// Any round-trip test written that way proves nothing. This is what round-trip
/// tests must use instead.
func deepEqualFailures(_ lhs: MemoryNote, _ rhs: MemoryNote) -> [DeepEqualFailure] {
    var failures: [DeepEqualFailure] = []

    func compare<T: Equatable>(_ field: String, _ l: T, _ r: T) {
        guard l != r else { return }
        failures.append(DeepEqualFailure(field: field, lhs: "\(l)", rhs: "\(r)"))
    }

    compare("id", lhs.id, rhs.id)
    compare("startedAt", lhs.startedAt, rhs.startedAt)
    compare("recordingStartedAt", lhs.recordingStartedAt, rhs.recordingStartedAt)
    compare("endedAt", lhs.endedAt, rhs.endedAt)
    compare("mode", lhs.mode, rhs.mode)
    compare("training", lhs.training, rhs.training)
    compare("conversationLang", lhs.conversationLang, rhs.conversationLang)
    compare("nativeLang", lhs.nativeLang, rhs.nativeLang)
    compare("goal", lhs.goal, rhs.goal)
    compare("transcript", lhs.transcript, rhs.transcript)
    compare("coachCards", lhs.coachCards.map(\.id), rhs.coachCards.map(\.id))
    compare("coachCards.guidePT", lhs.coachCards.map(\.guidePT), rhs.coachCards.map(\.guidePT))
    compare("minutes", lhs.minutes, rhs.minutes)
    compare("participantNames", lhs.participantNames, rhs.participantNames)
    compare("coachModel", lhs.coachModel, rhs.coachModel)
    compare("summaryModel", lhs.summaryModel, rhs.summaryModel)
    compare("vocabulary", lhs.vocabulary, rhs.vocabulary)
    compare("hasAudio", lhs.hasAudio, rhs.hasAudio)
    compare("audioDuration", lhs.audioDuration, rhs.audioDuration)
    compare("integrity", lhs.integrity, rhs.integrity)
    compare("coachFeedback", lhs.coachFeedback, rhs.coachFeedback)
    compare("archiveFolderName", lhs.archiveFolderName, rhs.archiveFolderName)
    compare("notes", lhs.notes, rhs.notes)
    compare("takeaways", lhs.takeaways, rhs.takeaways)
    compare("origin", lhs.origin, rhs.origin)
    compare("displayTitle", lhs.displayTitle, rhs.displayTitle)
    compare("review", lhs.review, rhs.review)
    compare("artifacts", lhs.artifacts, rhs.artifacts)
    compare("links", lhs.links, rhs.links)
    compare("noteKind", lhs.noteKind, rhs.noteKind)
    compare("markdownBody", lhs.markdownBody, rhs.markdownBody)
    compare("labels", lhs.labels, rhs.labels)
    compare("attachments", lhs.attachments, rhs.attachments)
    compare("titleSource", lhs.titleSource, rhs.titleSource)
    compare("modifiedAt", lhs.modifiedAt, rhs.modifiedAt)
    compare("relativeFolderPath", lhs.relativeFolderPath, rhs.relativeFolderPath)
    compare("unknownFrontmatterYAML", lhs.unknownFrontmatterYAML, rhs.unknownFrontmatterYAML)
    compare("residualMarkdown", lhs.residualMarkdown, rhs.residualMarkdown)

    return failures
}

func assertDeepEqual(
    _ lhs: MemoryNote,
    _ rhs: MemoryNote,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for failure in deepEqualFailures(lhs, rhs) {
        XCTFail(
            "MemoryNote.\(failure.field) differs:\n  lhs: \(failure.lhs)\n  rhs: \(failure.rhs)",
            file: file,
            line: line
        )
    }
}
