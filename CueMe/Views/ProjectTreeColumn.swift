import SwiftUI

struct ProjectTreeColumn: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var showCreateProject = false
    @State private var newProjectName = ""
    @State private var expandedProjectIDs: Set<UUID> = []

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader
            searchField
            if !app.historySearch.isEmpty { memoryAsk }

            sectionRows
                .padding(.top, 11)

            HStack {
                Text("PROJECTS").font(.ui(10, .semibold)).tracking(1.3).foregroundStyle(Theme.faint)
                Spacer()
                Button { showCreateProject = true } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.violet).help("Novo projeto")
                .popover(isPresented: $showCreateProject) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Novo projeto").font(.headline)
                        TextField("Nome do projeto", text: $newProjectName)
                            .textFieldStyle(.roundedBorder).onSubmit(createProject)
                        Button("Criar", action: createProject).buttonStyle(.borderedProminent)
                    }
                    .padding(14).frame(width: 260)
                }
            }
            .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 6)

            ScrollView {
                ProjectTreeRows(expandedProjectIDs: $expandedProjectIDs)
            }

            Spacer(minLength: 8)
            footer
        }
        .padding(.horizontal, 9).padding(.vertical, 12)
        .frame(width: 224)
        .background(Theme.tree)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 9) {
            Text("C")
                .font(.ui(12, .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.violet, in: RoundedRectangle(cornerRadius: 6))
            Menu {
                Button("Nova sessão") { app.newSession() }
                    .disabled(app.sessionState == .preparing || app.sessionState == .stopping)
                    .accessibilityIdentifier("workspace.new-session")
                Divider()
                Toggle("Sempre no topo", isOn: Binding(
                    get: { app.pinned },
                    set: { app.pinned = $0 }
                ))
                .accessibilityIdentifier("workspace.pin")
                .accessibilityValue(app.pinned ? "on" : "off")
                Toggle("Modo treino", isOn: Binding(
                    get: { app.trainingMode },
                    set: { app.trainingMode = $0 }
                ))
                .disabled(app.isSessionBusy || app.brief.mode.isPassive)
                .accessibilityIdentifier("workspace.training")
                .accessibilityValue(app.trainingMode ? "on" : "off")
                if !app.profiles.isEmpty {
                    Menu("Perfis") {
                        ForEach(app.profiles) { profile in
                            Button(profile.name) { app.applyProfile(profile.id) }
                                .accessibilityIdentifier("workspace.profile.\(profile.id.uuidString)")
                        }
                    }
                    .disabled(app.isSessionBusy)
                    .accessibilityIdentifier("workspace.profiles")
                    .accessibilityValue(app.activeProfileID?.uuidString ?? "none")
                }
                Divider()
                Button("Camera Rail") { openWindow(id: "camera-rail") }
                    .accessibilityIdentifier("workspace.camera-rail")
                Button("Testar setup") { app.showPreflight = true }
                    .disabled(app.isSessionBusy)
                    .accessibilityIdentifier("workspace.setup")
                Button("Configurar sessão") { app.showSettings = true }
                    .disabled(app.isSessionBusy)
                    .accessibilityIdentifier("workspace.settings")
                Button(app.updateStatus.isActionable ? app.updateStatus.summary : "Buscar atualizações…") {
                    app.checkForUpdates()
                }
                .disabled(app.updateStatus.isBusy)
                .accessibilityIdentifier("workspace.updates")
            } label: {
                HStack(spacing: 5) {
                    Text("CueMe").font(.ui(13.5, .semibold)).foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Theme.faint)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("workspace.menu")
            .accessibilityValue(workspaceMenuAccessibilityValue)

            Spacer()
            Menu {
                ForEach(AppThemePreference.allCases) { preference in
                    Button {
                        app.themePreference = preference
                    } label: {
                        Label(preference.label, systemImage: preference.icon)
                    }
                    .accessibilityIdentifier("theme.\(preference.rawValue)")
                }
            } label: {
                Image(systemName: app.themePreference.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("theme.preference")
            .accessibilityValue(app.themePreference.rawValue)
            .help("Aparência: \(app.themePreference.label)")
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
    }

    private var searchField: some View {
        @Bindable var app = app
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.faint)
            TextField("Search", text: $app.historySearch)
                .textFieldStyle(.plain).font(.ui(12.5))
                .accessibilityIdentifier("memory.search")
            if app.historySearch.isEmpty {
                Text("⌘K").font(.ui(9.5)).foregroundStyle(Theme.faint)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line))
            } else {
                Button { app.historySearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
        .padding(.top, 9)
    }

    private var memoryAsk: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { app.askGlobalMemory() } label: {
                Label(app.globalMemoryAnswering ? "Consultando…" : "Perguntar à memória", systemImage: "sparkles")
                    .font(.ui(10.5, .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small).tint(Theme.violet)
            .accessibilityIdentifier("memory.ask")
            .disabled(app.globalMemoryAnswering)
            if let answer = app.globalMemoryAnswer {
                ScrollView {
                    Text(.init(answer)).font(.ui(10.5)).textSelection(.enabled)
                        .accessibilityIdentifier("memory.answer").accessibilityValue(answer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140).padding(8)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(.top, 8)
    }

    private var sectionRows: some View {
        VStack(spacing: 1) {
            sectionRow("Inbox", icon: "tray", section: .inbox)
            sectionRow("All notes", icon: "line.3.horizontal", section: .all, count: app.history.count)
            sectionRow("Journal", icon: "sparkles", section: .journal)
        }
    }

    private func sectionRow(_ title: String, icon: String, section: LibrarySection, count: Int? = nil) -> some View {
        let selected = app.libraryProjectFilterID == nil && app.librarySection == section
        return Button { app.selectLibrarySection(section) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 15)
                Text(title).font(.ui(13))
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(.ui(10.5)).foregroundStyle(Theme.faint) }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.ink2)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.canvas : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Button {
                app.isRunning ? app.stop() : app.start()
            } label: {
                Text(primaryTitle)
                    .font(.ui(12.5, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(app.isRunning ? Theme.rose : Theme.violet, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("session.primary")
            .accessibilityValue(app.statusText)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(app.sessionState == .preparing || app.sessionState == .stopping)

            HStack(spacing: 7) {
                Button { _ = app.createMemoryNote(kind: .note) } label: {
                    Text("＋ New note").font(.ui(12.5, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Theme.violet, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).accessibilityIdentifier("sidebar.new-note")

                Button { app.chooseAudioFiles() } label: {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 12)).foregroundStyle(Theme.ink2)
                        .padding(9)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
                .help("Importar áudio")
                .disabled(app.isSessionBusy || app.audioImportStatus?.isActive == true)
            }
        }
        .overlay(alignment: .top) {
            if let status = app.audioImportStatus {
                ImportStatusRow(status: status).offset(y: -58)
            }
        }
    }

    private var primaryTitle: String {
        switch app.sessionState {
        case .preparing: return "Preparando"
        case .stopping: return "Salvando"
        default:
            if app.isRunning { return "Parar" }
            return app.selectedSession == nil ? "Iniciar" : "Gravar"
        }
    }

    private var workspaceMenuAccessibilityValue: String {
        let pin = app.pinned ? "on" : "off"
        let training = app.trainingMode ? "on" : "off"
        let profile = app.activeProfileID?.uuidString ?? "none"
        return "pin=\(pin);training=\(training);profile=\(profile)"
    }

    private func createProject() {
        guard let id = app.createProject(named: newProjectName) else { return }
        app.selectLibraryProject(id)
        newProjectName = ""
        showCreateProject = false
    }
}
