import SwiftUI

/// The corpus tree, one level at a time. A container is just a note other
/// notes sit under, so every row is the same kind of thing.
struct NoteTreeRows: View {
    @Environment(AppModel.self) private var app
    @Binding var expandedNoteIDs: Set<UUID>
    @State private var hoveredDropID: UUID?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(app.rootNotes) { note in
                let forcedExpanded = app.isNoteForcedExpanded(note)
                let expanded = app.isNoteExpanded(note, explicitly: expandedNoteIDs)
                VStack(spacing: 1) {
                    containerRow(note, expanded: expanded, forcedExpanded: forcedExpanded)
                    if expanded {
                        if NoteTreeProjection.showsLiveChild(
                            for: note.id,
                            activeParentNoteID: app.activeParentNoteID,
                            isRunning: app.isRunning
                        ) {
                            liveChildRow(parentID: note.id)
                        }
                        ForEach(app.noteTreeChildren(of: note)) { record in
                            childRow(record)
                        }
                    }
                }
            }
        }
    }

    private func containerRow(_ note: MemoryNote, expanded: Bool, forcedExpanded: Bool) -> some View {
        let selected = app.librarySubtreeNoteID == note.id
        return HStack(spacing: 2) {
            Button {
                if expandedNoteIDs.contains(note.id) {
                    expandedNoteIDs.remove(note.id)
                } else {
                    expandedNoteIDs.insert(note.id)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .rotationEffect(expanded ? .degrees(90) : .zero)
                    .frame(width: 17, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(forcedExpanded)
            .accessibilityLabel(
                forcedExpanded
                    ? "\(note.title) is expanded for the current selection"
                    : (expanded ? "Collapse \(note.title)" : "Expand \(note.title)")
            )
            .accessibilityIdentifier(NoteTreeIdentifier.disclosure(note.id))
            .accessibilityValue(forcedExpanded ? "forced-expanded" : (expanded ? "expanded" : "collapsed"))

            Button { app.selectLibraryNote(note.id) } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(app.libraryColor(for: note.id))
                        .frame(width: 9, height: 9)
                    Text(note.title).font(.ui(13, selected ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(NoteTreeIdentifier.container(note.id))
            .accessibilityValue(selected ? "selected" : "not-selected")
        }
        .padding(.leading, 1)
        .frame(maxWidth: .infinity)
        .background(selected ? Theme.canvas : .clear, in: RoundedRectangle(cornerRadius: 7))
        .modifier(NoteDropRow(note: note, hovered: $hoveredDropID, cornerRadius: 7))
    }

    private func childRow(_ record: MemoryNote) -> some View {
        let selected = app.selectedSessionID == record.id
        return Button { app.selectNoteTreeRecord(record) } label: {
            HStack(spacing: 7) {
                Image(systemName: record.noteKind.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 13)
                Text(record.title)
                    .font(.ui(11.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 26).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
            .background(selected ? Theme.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(NoteTreeIdentifier.child(record.id))
        .accessibilityValue(selected ? "selected" : "not-selected")
        .modifier(NoteDropRow(note: record, hovered: $hoveredDropID, cornerRadius: 6))
    }

    private func liveChildRow(parentID: UUID) -> some View {
        let selected = app.selectedSessionID == nil
        return Button(action: app.showLiveSession) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 6, height: 6)
                    .modifier(NoteTreeLivePulse())
                Text(app.brief.goal.isEmpty ? "Live session" : app.brief.goal)
                    .font(.ui(11.5, .semibold))
                    .foregroundStyle(Theme.amberText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 30).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
            .background(selected ? Theme.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Live session")
        .accessibilityIdentifier(NoteTreeIdentifier.live)
        .accessibilityValue(parentID.uuidString)
    }
}

/// Makes a tree row both draggable and a drop destination. A row that would
/// refuse the drop says so while the note is over it, rather than accepting it
/// and silently doing nothing.
private struct NoteDropRow: ViewModifier {
    @Environment(AppModel.self) private var app
    let note: MemoryNote
    @Binding var hovered: UUID?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let targeted = hovered == note.id
        let accepts = app.acceptsNoteDrop(onto: note.id)
        return content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(accepts ? Theme.violet : Theme.amber, lineWidth: 1.5)
                }
            }
            .opacity(targeted && !accepts ? 0.55 : 1)
            .onDrag {
                app.draggingNoteID = note.id
                return NoteDragPayload.provider(for: note.id)
            }
            .onDrop(
                of: [.text],
                isTargeted: Binding(
                    get: { hovered == note.id },
                    set: { isOver in
                        if isOver { hovered = note.id } else if hovered == note.id { hovered = nil }
                    }
                )
            ) { providers in
                NoteDragPayload.load(from: providers) { app.dropNote($0, onto: note.id) }
            }
    }
}

private struct NoteTreeLivePulse: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content.opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
