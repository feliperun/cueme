import SwiftUI

/// Page geometry every masthead-bearing surface shares: a 720pt band made of a
/// 632pt reading column plus 44pt gutters, where the block handles live.
enum NoteDocumentBand {
    static let readingWidth: CGFloat = 632
    static let gutter: CGFloat = 44
    static let topPadding: CGFloat = 30
    static let bottomPadding: CGFloat = 26
}

/// Document masthead: eyebrow, title and the people in the room.
///
/// It scrolls with the note body instead of sitting in a fixed chrome bar, so a
/// note reads as one page. Rename stays a `Button` + popover: the title is a
/// document heading, and a text field there would fight the block editor for
/// first responder.
struct NoteMasthead: View {
    @Environment(AppModel.self) private var app
    let record: MemoryNote

    @State private var showRename = false
    @State private var titleDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            title.padding(.top, 9)
            if !participants.isEmpty { participantsRow.padding(.top, 15) }
            NoteMetadataChips(record: record).padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note.masthead")
    }

    // MARK: Eyebrow

    private var eyebrow: some View {
        HStack(spacing: 8) {
            Text(NoteMastheadModel.eyebrow(for: record, dateText: dateText))
                .font(.ui(11, .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.faint)
            if record.hasAudio {
                Label(audioFormatLabel, systemImage: "waveform")
                    .font(.ui(10, .semibold))
                    .foregroundStyle(Theme.mint)
            }
        }
    }

    private var dateText: String {
        record.startedAt.formatted(date: .abbreviated, time: .omitted)
    }

    /// Codec of the recording actually on disk — never a stored absolute path.
    private var audioFormatLabel: String {
        let urls = [MeetingRecording.selfURL(for: record), MeetingRecording.otherURL(for: record)]
        let existing = urls.first { FileManager.default.fileExists(atPath: $0.path) }
        switch existing?.pathExtension.lowercased() {
        case "m4a": return "M4A · AAC"
        case "caf": return "CAF · legado"
        default: return "Áudio local"
        }
    }

    // MARK: Title

    private var title: some View {
        Button {
            titleDraft = record.title
            showRename = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(record.title)
                    .font(.read(42, .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "pencil")
                    .font(.ui(11))
                    .foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Renomear nota")
        .accessibilityIdentifier("note.rename")
        .popover(isPresented: $showRename) { renamePopover }
    }

    private var renamePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nome da nota").font(.headline)
            TextField("Um nome que valha reencontrar", text: $titleDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("note.title.input")
                .onSubmit(saveTitle)
            Button("Salvar", action: saveTitle)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("note.title.save")
        }
        .padding(14).frame(width: 310)
    }

    private func saveTitle() {
        app.renameMemoryNote(record.id, to: titleDraft)
        showRename = false
    }

    // MARK: Participants

    private var participants: [NoteMastheadParticipant] {
        NoteMastheadModel.participants(for: record, people: app.people)
    }

    private var participantsRow: some View {
        let faces = participants
        return HStack(spacing: 0) {
            ForEach(Array(faces.enumerated()), id: \.element.id) { index, person in
                Text(person.initials)
                    .font(.ui(10, .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(tint(for: person.role), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2))
                    .zIndex(Double(faces.count - index))
                    .padding(.leading, index == 0 ? 0 : -8)
                    .help(person.name)
            }
            Text(faces.map(\.name).joined(separator: " · "))
                .font(.ui(12.5))
                .foregroundStyle(Theme.ink2)
                .padding(.leading, 9)
        }
    }

    /// Violet marks *you*; everyone else stays neutral ink — the only tint that
    /// keeps white initials legible. Amber is reserved for the live/recording
    /// signal and must not become a decorative avatar colour.
    private func tint(for role: NoteMastheadParticipant.Role) -> Color {
        role == .you ? Theme.violet : Theme.ink2
    }
}
