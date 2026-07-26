import XCTest

@MainActor
final class CueMeMemoryE2ETests: XCTestCase {
    private func launchApp(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CUEME_UI_TESTING"] = "1"
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    func testSearchOpensEvidenceBackedMemory() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let search = app.textFields["memory.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        // No lexical token exists in the fixture: this result must come from sqlite-vec.
        search.typeText("carro sustentável")

        let session = app.buttons["session.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()

        let decision = app.textFields["review.item.30000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        XCTAssertEqual(decision.value as? String, "Adotar veículos elétricos no próximo trimestre")
        let evidence = app.buttons["evidence.30000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(evidence.exists)
        XCTAssertEqual(evidence.value as? String, "00:42")
        evidence.click()
        XCTAssertTrue(app.buttons["memory.ask"].exists)
    }

    func testGlobalMemoryAnswerIncludesGroundedSource() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let search = app.textFields["memory.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("carro sustentável")
        let ask = app.buttons["memory.ask"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.click()
        let answer = app.staticTexts["memory.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let rawAnswer = [answer.value as? String, answer.label]
            .compactMap { $0 }
            .joined(separator: " ")
        XCTAssertTrue(rawAnswer.contains("[S1]"))
        XCTAssertTrue(rawAnswer.contains("Estratégia de frota elétrica"))
    }

    func testEditingMemoryReindexesSearchFromTheUI() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let session = app.buttons["session.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()
        let decision = app.textFields["review.item.30000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        decision.click()
        decision.typeKey("a", modifierFlags: .command)
        decision.typeText("Contrato solar aprovado")
        decision.typeKey(.return, modifierFlags: [])

        let search = app.textFields["memory.search"]
        search.click()
        search.typeText("Contrato solar")
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()
        XCTAssertEqual(decision.value as? String, "Contrato solar aprovado")
    }

    func testProjectPopoverShowsLongitudinalTimeline() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let session = app.buttons["session.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()
        let project = app.buttons["session.project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.click()

        XCTAssertTrue(app.staticTexts["TIMELINE"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["timeline.meeting-20000000-0000-0000-0000-000000000001"].exists)
        XCTAssertTrue(app.buttons["timeline.meeting-20000000-0000-0000-0000-000000000002"].exists)
    }

    func testLiveSessionRecordsTranscriptNoteAndCreatesDurableHistory() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let primary = app.buttons["session.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.click()
        XCTAssertEqual(primary.label, "Parar")

        let noteButton = app.buttons["live.note"]
        XCTAssertTrue(noteButton.waitForExistence(timeout: 5))
        noteButton.click()
        let note = app.textFields["live.note.input"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.click()
        note.typeText("Validar entrega final")
        app.buttons["live.note.submit"].click()

        primary.click()
        XCTAssertTrue(app.staticTexts["Biblioteca"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Áudio local"].exists)
        app.buttons["session.tab.transcript"].click()
        XCTAssertTrue(app.staticTexts["Como vamos reduzir o risco da entrega?"].waitForExistence(timeout: 3))
        app.buttons["session.tab.notes"].click()
        let savedNote = app.textFields["memory.note"]
        XCTAssertTrue(savedNote.waitForExistence(timeout: 3))
        XCTAssertEqual(savedNote.value as? String, "Validar entrega final")
    }

    func testSessionRecordsMicrophoneWhenSystemCapturePermissionIsUnavailable() {
        continueAfterFailure = false
        let app = launchApp(environment: ["CUEME_UI_TEST_SYSTEM_CAPTURE_DENIED": "1"])
        defer { app.terminate() }

        let primary = app.buttons["session.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.click()
        XCTAssertEqual(primary.label, "Parar")

        let microphone = app.buttons["capture.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 3))
        XCTAssertEqual(microphone.value as? String, "active")
        let system = app.buttons["capture.system"]
        XCTAssertTrue(system.exists)
        XCTAssertEqual(system.value as? String, "unavailable")
        let alert = app.buttons["capture.alert"]
        XCTAssertTrue(alert.exists)
        XCTAssertTrue(alert.label.contains("ÁUDIO EXTERNO OFF"))

        primary.click()
        XCTAssertTrue(app.staticTexts["Biblioteca"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Áudio local"].exists)
    }

    func testLiveCoachSuggestionSurvivesIntoSessionHistory() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let primary = app.buttons["session.primary"]
        primary.click()
        let guide = app.staticTexts["coach.guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        XCTAssertEqual(guide.value as? String, "Explique mitigação e prazo")
        XCTAssertTrue(app.staticTexts["Vamos dividir a entrega em marcos semanais."].exists)

        primary.click()
        XCTAssertTrue(app.staticTexts["Biblioteca"].waitForExistence(timeout: 5))
        app.buttons["session.tab.coach"].click()
        XCTAssertTrue(app.staticTexts["Explique mitigação e prazo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Vamos dividir a entrega em marcos semanais."].exists)
    }

    func testHomeSurfacesProfilesAndSecondBrainEntryPoints() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Sua memória, viva e organizada."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.new-note"].exists)
        XCTAssertTrue(app.buttons["home.journal"].exists)
        XCTAssertTrue(app.buttons["home.record"].exists)
        XCTAssertTrue(app.buttons["home.profile.interview"].exists)
        XCTAssertTrue(app.buttons["home.profile.sales"].exists)
    }

    func testCreatesRenamesLabelsAndEditsAMarkdownNoteWithVisualBlocks() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        let newNote = app.buttons["home.new-note"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 5))
        newNote.click()

        let rename = app.buttons["note.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.click()
        let title = app.textFields["note.title.input"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Mapa da minha jornada")
        app.buttons["note.title.save"].click()

        let headingEditor = app.textViews["note.block.editor.0"]
        XCTAssertTrue(headingEditor.waitForExistence(timeout: 3))
        headingEditor.click()
        headingEditor.typeText("/")
        let headingCommand = app.buttons["note.block.command.heading1"]
        XCTAssertTrue(headingCommand.waitForExistence(timeout: 3))
        headingCommand.click()
        XCTAssertTrue(headingEditor.waitForExistence(timeout: 3))
        headingEditor.typeText("Aprendizados")
        headingEditor.typeKey(.return, modifierFlags: [])

        let paragraphEditor = app.textViews["note.block.editor.1"]
        XCTAssertTrue(paragraphEditor.waitForExistence(timeout: 3))
        paragraphEditor.typeText("A memória ajuda na hora exata.")

        app.buttons["note.labels"].click()
        let label = app.textFields["note.label.input"]
        XCTAssertTrue(label.waitForExistence(timeout: 3))
        label.click()
        // Avoid `c` here: macOS 26's XCUI keyboard synthesizer drops that key
        // under some active keyboard layouts, even though the field has focus.
        label.typeText("jornada")
        app.buttons["note.label.add"].click()
        XCTAssertTrue(app.buttons["note.label.jornada"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])

        let source = app.buttons["note.editor.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.click()
        let rawMarkdown = app.textViews["note.editor.raw"]
        XCTAssertTrue(rawMarkdown.waitForExistence(timeout: 3))
        let markdown = rawMarkdown.value as? String ?? ""
        XCTAssertTrue(markdown.contains("# Aprendizados"))
        XCTAssertTrue(markdown.contains("A memória ajuda na hora exata."))
        XCTAssertTrue(app.buttons["note.rename"].label.contains("Mapa da minha jornada"))
    }

    func testVisualBlockEditorFormatsInlineTextAsMarkdown() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        app.buttons["home.new-note"].click()
        let editor = app.textViews["note.block.editor.0"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("Memória forte")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("b", modifierFlags: .command)

        app.buttons["note.editor.source"].click()
        let rawMarkdown = app.textViews["note.editor.raw"]
        XCTAssertTrue(rawMarkdown.waitForExistence(timeout: 3))
        XCTAssertEqual(rawMarkdown.value as? String, "**Memória forte**")
    }

    func testSavedSessionReceivesASignificantGeneratedTitle() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        let primary = app.buttons["session.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.click()
        primary.click()

        let title = app.buttons["note.rename"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Plano de mitigação da entrega"))
    }

    func testThemePreferenceCanBePinnedFromTheMainWindow() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        let theme = app.menuButtons["theme.preference"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        theme.click()
        let light = app.menuItems["Claro"]
        XCTAssertTrue(light.waitForExistence(timeout: 3))
        light.click()
        XCTAssertEqual(theme.value as? String, "light")
    }

    func testVoiceMemoSharedIntoCueMeAppearsInTheLibrary() {
        continueAfterFailure = false
        let app = launchApp(environment: ["CUEME_UI_TEST_VOICE_MEMO_IMPORT": "1"])
        defer { app.terminate() }

        let importedMemo = app.buttons["note.rename"]
        XCTAssertTrue(importedMemo.waitForExistence(timeout: 8))
        XCTAssertTrue(importedMemo.label.contains("Planejamento semanal do Voice Memos"))
    }

    /// A SwiftUI `Text` surfaces its string as the element value on macOS.
    private func readText(_ element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return value.isEmpty ? element.label : value
    }

    /// Opens About and returns its update status element. "Sobre o CueMe"
    /// exists both in the app menu and in the menu-bar extra, so the item is
    /// resolved inside the app menu to keep the query unambiguous.
    private func openAboutUpdateStatus(_ app: XCUIApplication) -> XCUIElement {
        let appMenu = app.menuBars.menuBarItems.element(boundBy: 1)
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let about = appMenu.menuItems["Sobre o CueMe"]
        XCTAssertTrue(about.waitForExistence(timeout: 3))
        about.click()
        let status = app.staticTexts["about.update.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 6))
        return status
    }

    func testAboutOffersAnAvailableUpdateByVersion() {
        continueAfterFailure = false
        let app = launchApp(environment: ["CUEME_UI_TEST_UPDATE_STATUS": "available:9.9.9"])
        defer { app.terminate() }

        let status = openAboutUpdateStatus(app)
        XCTAssertEqual(readText(status), "Atualização disponível: 9.9.9")

        let action = app.buttons["about.update.check"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        XCTAssertEqual(readText(action), "Instalar agora")
    }

    func testAboutReportsAFailedCheckWithoutLeakingTheFeedURL() {
        continueAfterFailure = false
        let app = launchApp(environment: ["CUEME_UI_TEST_UPDATE_STATUS": "unavailable"])
        defer { app.terminate() }

        let status = openAboutUpdateStatus(app)
        let summary = readText(status)
        XCTAssertEqual(summary, "Nenhuma atualização publicada ainda")
        // A broken feed must read as a plain sentence, never as a URL or code.
        XCTAssertFalse(summary.lowercased().contains("http"))
        XCTAssertFalse(summary.contains("appcast"))

        let action = app.buttons["about.update.check"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        XCTAssertEqual(readText(action), "Buscar atualizações")
    }
}
