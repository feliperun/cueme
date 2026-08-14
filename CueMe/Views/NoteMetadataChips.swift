import SwiftUI
import UniformTypeIdentifiers

/// Labels, project, participants and attachments for the note being read.
///
/// These used to live in a fixed chrome bar above the document. They belong to
/// the note itself, so they now sit under the masthead and scroll with it —
/// keeping the accessibility contracts (`note.labels`, `note.links`) stable.
struct NoteMetadataChips: View {
    @Environment(AppModel.self) private var app
    let record: MemoryNote

    @State private var showLabels = false
    @State private var labelDraft = ""
    @State private var showProject = false
    @State private var newProjectName = ""
    @State private var showParticipants = false
    @State private var selfName = ""
    @State private var otherName = ""
    @State private var importingAttachment = false

    var body: some View {
        HStack(spacing: 7) {
            labelsChip
            linksChip
            if record.origin != .written { participantsChip }
            attachChip
            Spacer(minLength: 0)
        }
        .fileImporter(
            isPresented: $importingAttachment,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            try? app.addAttachment(from: url, to: record.id)
        }
    }

    // MARK: Labels

    private var labelsChip: some View {
        Button { showLabels.toggle() } label: {
            chipLabel(
                record.labels.isEmpty ? "Labels" : "\(record.labels.count)",
                icon: "tag",
                active: !record.labels.isEmpty
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note.labels")
        .popover(isPresented: $showLabels) { labelsPopover }
    }

    private var labelsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Labels").font(.headline)
            if record.labels.isEmpty {
                Text("Agrupe ideias que atravessam projetos.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                NoteChipFlow(spacing: 6) {
                    ForEach(record.labels, id: \.self) { label in
                        Button {
                            app.removeLabel(label, from: record.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text(label)
                                Image(systemName: "xmark")
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityIdentifier("note.label.\(label)")
                    }
                }
            }
            HStack {
                TextField("ex.: crescimento", text: $labelDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("note.label.input")
                    .onSubmit(addLabel)
                Button("Adicionar", action: addLabel)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("note.label.add")
            }
            if !app.allLabels.isEmpty {
                Divider()
                Text("JÁ USADAS").font(.ui(9, .bold)).foregroundStyle(.secondary)
                NoteChipFlow(spacing: 5) {
                    ForEach(app.allLabels.filter { !record.labels.contains($0) }, id: \.self) { label in
                        Button(label) { app.addLabel(label, to: record.id) }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.violet)
                    }
                }
            }
        }
        .padding(14).frame(width: 300)
    }

    private func addLabel() {
        app.addLabel(labelDraft, to: record.id)
        labelDraft = ""
    }

    // MARK: Links

    /// One untyped relation. Who is a person, who is a project and who is a
    /// document is decided by where a note sits in the tree, not by a type on
    /// the edge — which is the OKF posture and the reason there is a single
    /// chip here instead of one per entity kind.
    private var linksChip: some View {
        Button { showProject.toggle() } label: {
            chipLabel(
                record.links.isEmpty ? "Relacionadas" : "\(record.links.count) relacionadas",
                icon: "link",
                active: !record.links.isEmpty
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note.links")
        .popover(isPresented: $showProject) { linksPopover }
    }

    private var linksPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Relacionadas").font(.headline)
            if app.linkedNotes(of: record).isEmpty {
                Text("Nenhuma nota relacionada.").font(.ui(11)).foregroundStyle(.secondary)
            }
            ForEach(app.linkedNotes(of: record)) { linked in
                Button(linked.title) {
                    app.selectSession(linked.id)
                    showProject = false
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.link.\(linked.id.uuidString)")
            }
            if let parent = app.parentNote(of: record) {
                Divider()
                Text("TIMELINE").font(.ui(9, .bold)).foregroundStyle(.secondary)
                ForEach(app.timeline(for: parent.id).prefix(6)) { entry in
                    Button {
                        app.selectSession(entry.sessionID)
                        showProject = false
                    } label: {
                        Text("\(entry.title) · \(entry.detail)").font(.ui(11)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timeline.\(entry.id)")
                }
            }
        }
        .padding(14).frame(width: 260, alignment: .leading)
    }

    // MARK: Participants

    private var participantsChip: some View {
        Button {
            selfName = record.participantName(for: .self)
            otherName = record.participantName(for: .other)
            showParticipants.toggle()
        } label: {
            chipLabel("Participantes", icon: "person.2", active: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note.participants")
        .popover(isPresented: $showParticipants) {
            VStack(alignment: .leading, spacing: 9) {
                TextField("Você", text: $selfName)
                TextField("Interlocutor", text: $otherName)
                Button("Salvar") {
                    app.setParticipantName(selfName, for: .self, sessionID: record.id)
                    app.setParticipantName(otherName, for: .other, sessionID: record.id)
                    showParticipants = false
                }
                .buttonStyle(.borderedProminent)
            }
            .textFieldStyle(.roundedBorder)
            .padding(14).frame(width: 240)
        }
    }

    // MARK: Attachments

    private var attachChip: some View {
        Button { importingAttachment = true } label: {
            chipLabel(
                record.attachments.isEmpty ? "Anexar" : "\(record.attachments.count)",
                icon: "paperclip",
                active: !record.attachments.isEmpty
            )
        }
        .buttonStyle(.plain)
        .help("Anexar um arquivo a esta nota")
        .accessibilityIdentifier("note.attach")
    }

    // MARK: Chip styling

    private func chipLabel(_ text: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.ui(10, .semibold))
            Text(text).font(.ui(11.5))
        }
        .foregroundStyle(active ? Theme.violetDeep : Theme.ink2)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(active ? Theme.violetSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? .clear : Theme.line))
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Wrapping row used by the label popovers.
struct NoteChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
