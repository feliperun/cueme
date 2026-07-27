import SwiftUI

struct ProjectTreeRows: View {
    @Environment(AppModel.self) private var app
    @Binding var expandedProjectIDs: Set<UUID>

    var body: some View {
        VStack(spacing: 1) {
            ForEach(app.projects.filter { !$0.archived }) { project in
                let forcedExpanded = app.isProjectForcedExpanded(project.id)
                let expanded = app.isProjectExpanded(project.id, explicitly: expandedProjectIDs)
                VStack(spacing: 1) {
                    projectRow(project, expanded: expanded, forcedExpanded: forcedExpanded)
                    if expanded {
                        if ProjectTreeProjection.showsLiveChild(
                            for: project.id,
                            activeProjectID: app.activeProjectID,
                            isRunning: app.isRunning
                        ) {
                            liveProjectRow(projectID: project.id)
                        }
                        ForEach(app.projectTreeRecords(for: project.id)) { record in
                            projectRecordRow(record)
                        }
                    }
                }
            }
        }
    }

    private func projectRow(_ project: KnowledgeProject, expanded: Bool, forcedExpanded: Bool) -> some View {
        let selected = app.libraryProjectFilterID == project.id
        return HStack(spacing: 2) {
            Button {
                if expandedProjectIDs.contains(project.id) {
                    expandedProjectIDs.remove(project.id)
                } else {
                    expandedProjectIDs.insert(project.id)
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
                    ? "\(project.name) is expanded for the current selection"
                    : (expanded ? "Collapse \(project.name)" : "Expand \(project.name)")
            )
            .accessibilityIdentifier("tree.project.disclosure.\(project.id.uuidString)")
            .accessibilityValue(forcedExpanded ? "forced-expanded" : (expanded ? "expanded" : "collapsed"))

            Button { app.selectLibraryProject(project.id) } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(app.libraryColor(for: project.id))
                        .frame(width: 9, height: 9)
                    Text(project.name).font(.ui(13, selected ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project.\(project.id.uuidString)")
            .accessibilityValue(selected ? "selected" : "not-selected")
        }
        .padding(.leading, 1)
        .frame(maxWidth: .infinity)
        .background(selected ? Theme.canvas : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func projectRecordRow(_ record: SessionRecord) -> some View {
        let selected = app.selectedSessionID == record.id
        return Button { app.selectProjectTreeRecord(record) } label: {
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
        .accessibilityIdentifier("tree.note.\(record.id.uuidString)")
        .accessibilityValue(selected ? "selected" : "not-selected")
    }

    private func liveProjectRow(projectID: UUID) -> some View {
        let selected = app.selectedSessionID == nil
        return Button(action: app.showLiveSession) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 6, height: 6)
                    .modifier(ProjectTreeLivePulse())
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
        .accessibilityIdentifier("tree.live")
        .accessibilityValue(projectID.uuidString)
    }
}

private struct ProjectTreeLivePulse: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content.opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
