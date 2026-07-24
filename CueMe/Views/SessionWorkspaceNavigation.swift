import SwiftUI

struct SessionWorkspaceTabs: View {
    let record: SessionRecord
    @Binding var selection: SessionWorkspaceTab

    var body: some View {
        HStack(spacing: 8) {
            // Primary projections of the same session.json: Document · Transcript · Minutes.
            HStack(spacing: 2) {
                ForEach(primaryTabs, id: \.tab) { item in
                    segment(item.label, tab: item.tab)
                }
            }
            .padding(2)
            .background(Theme.soft, in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 8)

            // Secondary lanes stay reachable (and keep their test identifiers).
            HStack(spacing: 5) {
                ForEach(secondaryTabs) { tab in secondaryChip(tab) }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    // MARK: Segments

    private func segment(_ label: String, tab: SessionWorkspaceTab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.18)) { selection = tab }
        } label: {
            Text(label)
                .font(.ui(11.5, .semibold))
                .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.paper)
                            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.tab.\(tab.rawValue)")
        .help(tab.label)
    }

    private func secondaryChip(_ tab: SessionWorkspaceTab) -> some View {
        let selected = selection == tab
        let count = badge(for: tab)
        return Button {
            withAnimation(.snappy(duration: 0.18)) { selection = tab }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                Text(tab.label)
                if let count, count > 0 { Text("\(count)").font(.ui(8, .bold)) }
            }
            .font(.ui(10, .semibold))
            .foregroundStyle(selected ? Theme.violet : Theme.ink2)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selected ? Theme.violetSoft : Theme.soft, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.tab.\(tab.rawValue)")
        .help(tab.label)
    }

    private var documentTab: SessionWorkspaceTab {
        record.origin == .written ? .note : .review
    }

    private var primaryTabs: [(label: String, tab: SessionWorkspaceTab)] {
        var items: [(String, SessionWorkspaceTab)] = [("Document", documentTab)]
        if availableTabs.contains(.transcript) { items.append(("Transcript", .transcript)) }
        if availableTabs.contains(.summary) { items.append(("Minutes", .summary)) }
        return items
    }

    private var secondaryTabs: [SessionWorkspaceTab] {
        let primary = Set(primaryTabs.map(\.tab))
        return availableTabs.filter { !primary.contains($0) }
    }

    private var availableTabs: [SessionWorkspaceTab] {
        if record.origin == .written { return [.note, .generated] }
        return record.origin.supportsLiveCoach
            ? SessionWorkspaceTab.allCases
            : SessionWorkspaceTab.allCases.filter { $0 != .coach }
    }

    private func badge(for tab: SessionWorkspaceTab) -> Int? {
        switch tab {
        case .note: return nil
        case .review:
            return record.review.decisions.count + record.review.openQuestions.count
                + record.takeaways.filter { !$0.isDone }.count
        case .coach: return record.coachCards.count
        case .summary: return record.minutes.topics.count
        case .transcript: return record.transcript.filter(\.isFinal).count
        case .notes: return record.notes.count
        case .takeaways: return record.takeaways.filter { !$0.isDone }.count
        case .generated: return record.artifacts.count
        }
    }
}

struct SessionWorkspacePane: View {
    let record: SessionRecord
    let selection: SessionWorkspaceTab
    let player: MeetingPlayer

    @ViewBuilder
    var body: some View {
        switch selection {
        case .note: MemoryNoteEditor(record: record)
        case .review: SessionReviewPane(record: record, player: player)
        case .coach: SessionCoachPane(record: record)
        case .summary: SessionSummaryPane(record: record)
        case .transcript: SessionTranscriptPane(record: record, player: player)
        case .notes: SessionNotesPane(record: record, player: player)
        case .takeaways: SessionTakeawaysPane(record: record)
        case .generated: SessionArtifactsPane(record: record)
        }
    }
}
