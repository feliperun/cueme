import XCTest
@testable import CueMe

/// AC6–AC12 (specs/okf-corpus/tasks/T012-note-reader.md, design.md §5 — the
/// seven robustness rules). Every test starts from a byte-exact writer output
/// (never hand-typed frontmatter, which would drift from the real format),
/// applies one targeted external edit, reads it, and saves it back — the
/// whole file is diffed against what the edit should have produced, not just
/// the fields that scenario is about.
final class NoteDocumentExternalEditTests: XCTestCase {
    /// A small note with one evidenced takeaway — enough to exercise the
    /// `takeaways` and `sources` sections without the size of the full golden
    /// fixture. `titleSource: .generated` so AC6 can show the transition to
    /// `.user`.
    private func baseNote() -> MemoryNote {
        MemoryNote(
            id: fixtureUUID("66666666-6666-4666-8666-666666666666"),
            startedAt: fixtureDate("2026-08-08T09:00:00.000Z"),
            endedAt: fixtureDate("2026-08-08T09:00:00.000Z"),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            takeaways: [
                SessionTakeaway(
                    id: fixtureUUID("77777777-7777-4777-8777-777777777771"),
                    text: "Primeira pendência",
                    isDone: false,
                    createdAt: fixtureDate("2026-08-08T09:05:00.000Z"),
                    evidence: [
                        MemoryEvidence(
                            id: fixtureUUID("88888888-8888-4888-8888-888888888881"),
                            timestamp: 10,
                            quote: "Uma citação qualquer."
                        ),
                    ]
                ),
            ],
            origin: .written,
            displayTitle: "Rascunho automático",
            noteKind: .note,
            markdownBody: "Corpo qualquer.",
            titleSource: .generated,
            modifiedAt: fixtureDate("2026-08-08T09:00:00.000Z")
        )
    }

    private func render(_ note: MemoryNote) -> String {
        NoteDocumentWriter.render(note, producer: "cueme/test")
    }

    private func read(_ markdown: String) throws -> MemoryNote {
        try XCTUnwrap(NoteDocumentReader.parse(markdown, slug: "rascunho", turns: 0))
    }

    /// The full source line containing `substring`, located by scanning
    /// outward from the first match — avoids hand-transcribing the exact
    /// `<!--cueme {…}-->` attribute comment the writer produces.
    private func fullLine(containing substring: String, in text: String) -> String {
        guard let range = text.range(of: substring) else { return "" }
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
        let lineEnd = text[range.lowerBound...].firstIndex(of: "\n") ?? text.endIndex
        return String(text[lineStart..<lineEnd])
    }

    private func assertWholeFileMatches(
        _ produced: String,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard produced != expected else { return }
        let dump = FileManager.default.temporaryDirectory.appendingPathComponent("okf-external-edit.md")
        try? produced.write(to: dump, atomically: true, encoding: .utf8)
        let a = produced.components(separatedBy: "\n")
        let b = expected.components(separatedBy: "\n")
        for index in 0..<max(a.count, b.count) where index >= min(a.count, b.count) || a[index] != b[index] {
            let got = index < a.count ? a[index] : "<sem linha>"
            let want = index < b.count ? b[index] : "<sem linha>"
            XCTFail(
                "linha \(index + 1) difere:\n  produzido: |\(got)|\n  esperado:  |\(want)|\n  arquivo completo em \(dump.path)",
                file: file, line: line
            )
            return
        }
        XCTFail("conteúdo igual mas comprimentos diferem: \(a.count) vs \(b.count) linhas; arquivo em \(dump.path)", file: file, line: line)
    }

    // MARK: - AC6

    func testHandRenamedH1WinsOverFrontmatterTitleAndTitleSourceBecomesUser() throws {
        let rendered = render(baseNote())
        let edited = rendered.replacingOccurrences(of: "\n# Rascunho automático\n", with: "\n# Título editado à mão\n")
        XCTAssertNotEqual(edited, rendered, "the fixture must actually change for this test to mean anything")

        let note = try read(edited)
        XCTAssertEqual(note.displayTitle, "Título editado à mão")
        XCTAssertEqual(note.titleSource, .user)

        let expected = rendered
            .replacingOccurrences(of: "title: Rascunho automático", with: "title: Título editado à mão")
            .replacingOccurrences(of: "\n# Rascunho automático\n", with: "\n# Título editado à mão\n")
            .replacingOccurrences(of: "x_cueme_title_source: generated", with: "x_cueme_title_source: user")
        assertWholeFileMatches(render(note), expected)
    }

    // MARK: - AC7

    func testItemWithoutCommentMintsAFreshIDAndTheSecondWriteIsIdempotent() throws {
        let rendered = render(baseNote())
        let originalLine = fullLine(containing: "Primeira pendência", in: rendered)
        XCTAssertFalse(originalLine.isEmpty)
        let edited = rendered.replacingOccurrences(
            of: originalLine,
            with: originalLine + "\n- [ ] Nova ação adicionada à mão"
        )

        let firstRead = try read(edited)
        XCTAssertEqual(firstRead.takeaways.count, 2)
        let minted = firstRead.takeaways[1]
        XCTAssertEqual(minted.text, "Nova ação adicionada à mão")
        XCTAssertNotEqual(minted.id, firstRead.takeaways[0].id)

        // First half: minting a fresh id necessarily changes the bytes — the
        // hand-added line had no comment at all, the written one does.
        let firstWrite = render(firstRead)
        XCTAssertNotEqual(firstWrite, edited)

        // Second half: reading what we just wrote and writing it again is
        // now stable, because the minted id is baked into the text.
        let secondRead = try XCTUnwrap(NoteDocumentReader.parse(firstWrite, slug: "rascunho", turns: 0))
        assertWholeFileMatches(render(secondRead), firstWrite)
    }

    // MARK: - AC8

    func testRenamedSectionHeadingPreservesItemsAndRegeneratesTheCanonicalTitle() throws {
        let rendered = render(baseNote())
        let edited = rendered.replacingOccurrences(of: "## Pendências", with: "## To-do")
        XCTAssertNotEqual(edited, rendered)

        let note = try read(edited)
        XCTAssertEqual(note.takeaways.count, 1)
        XCTAssertEqual(note.takeaways.first?.text, "Primeira pendência")

        assertWholeFileMatches(render(note), rendered)
    }

    // MARK: - AC9

    func testMalformedItemLineInsideAKnownSectionGoesToResidualNotDropped() throws {
        let rendered = render(baseNote())
        let originalLine = fullLine(containing: "Primeira pendência", in: rendered)
        let strayLine = "Uma linha solta sem marcador de item."
        let edited = rendered.replacingOccurrences(of: originalLine, with: originalLine + "\n" + strayLine)

        let note = try read(edited)
        XCTAssertEqual(note.takeaways.count, 1, "the stray line must not be parsed as a second item")
        XCTAssertTrue(note.residualMarkdown.contains(strayLine), "the stray line must be preserved, not dropped")

        let saved = render(note)
        XCTAssertTrue(saved.hasSuffix(strayLine + "\n"), "residual is re-emitted at the end of the file (design.md rule 2)")
    }

    // MARK: - AC10

    func testUnknownFrontmatterKeyIsPreservedThroughAFullSaveCycle() throws {
        let rendered = render(baseNote())
        let edited = rendered.replacingOccurrences(
            of: "x_cueme_integrity:",
            with: "x_outra_ferramenta: valor-do-usuario\nx_cueme_integrity:"
        )

        let note = try read(edited)
        XCTAssertTrue(note.unknownFrontmatterYAML.contains("x_outra_ferramenta: valor-do-usuario"))

        let saved = render(note)
        let frontmatter = try XCTUnwrap(saved.components(separatedBy: "---").dropFirst().first)
        XCTAssertTrue(frontmatter.contains("x_outra_ferramenta: valor-do-usuario"))
        let lastKnown = try XCTUnwrap(frontmatter.range(of: "x_cueme_integrity:"))
        let unknown = try XCTUnwrap(frontmatter.range(of: "x_outra_ferramenta:"))
        XCTAssertTrue(lastKnown.lowerBound < unknown.lowerBound, "unknown keys are re-emitted after all known keys")
    }

    // MARK: - AC11

    func testAppendixAddedAfterTheLastSectionIsPreserved() throws {
        let rendered = render(baseNote())
        XCTAssertTrue(rendered.hasSuffix("\n"))
        let appendix = "## Apêndice\n\nAlgo que o usuário escreveu no fim."
        let edited = rendered + "\n" + appendix + "\n"

        let note = try read(edited)
        XCTAssertTrue(note.residualMarkdown.contains("## Apêndice"))
        XCTAssertTrue(note.residualMarkdown.contains("Algo que o usuário escreveu no fim."))

        assertWholeFileMatches(render(note), rendered + "\n" + appendix + "\n")
    }

    // MARK: - AC12

    func testTogglingACheckboxByHandChangesOnlyIsDoneOnTheNextSave() throws {
        let rendered = render(RichNote.note)
        let originalLine = fullLine(containing: "Solicitar propostas aos fornecedores", in: rendered)
        XCTAssertTrue(originalLine.hasPrefix("- [ ] "))
        let toggledLine = "- [x] " + originalLine.dropFirst("- [ ] ".count)
        let edited = rendered.replacingOccurrences(of: originalLine, with: toggledLine)

        let note = try XCTUnwrap(NoteDocumentReader.parse(edited, slug: "estrategia-de-frota-eletrica", turns: 2))
        XCTAssertEqual(note.takeaways.first?.isDone, true)

        assertWholeFileMatches(render(note), edited)
    }
}
