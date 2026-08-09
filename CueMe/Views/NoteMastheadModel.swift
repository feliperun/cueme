import Foundation

/// One face in the note masthead. `role` only drives the avatar tint — it never
/// invents a participant the record does not actually have.
struct NoteMastheadParticipant: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case you
        case counterpart
        case linked
    }

    let id: String
    let name: String
    let initials: String
    let role: Role
}

/// Pure derivations behind `NoteMasthead`. Kept free of SwiftUI so the rules —
/// who was in the room, what the eyebrow says — stay unit-testable.
enum NoteMastheadModel {
    /// Speakers of this note, followed by the `KnowledgePerson`s linked to it.
    ///
    /// A written note has no room, so it gets no avatars: placeholder faces
    /// would claim a meeting that never happened.
    static func participants(
        for record: MemoryNote,
        people: [KnowledgePerson]
    ) -> [NoteMastheadParticipant] {
        guard record.origin != .written else { return [] }

        var result: [NoteMastheadParticipant] = []
        var seen: Set<String> = []

        func append(_ rawName: String, id: String, role: NoteMastheadParticipant.Role) {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(fold(name)).inserted else { return }
            result.append(.init(id: id, name: name, initials: initials(for: name), role: role))
        }

        append(record.participantName(for: .self), id: "self", role: .you)
        append(record.participantName(for: .other), id: "other", role: .counterpart)
        for person in people where record.personIDs.contains(person.id) {
            append(person.name, id: person.id.uuidString, role: .linked)
        }
        return Array(result.prefix(4))
    }

    static func initials(for name: String) -> String {
        let letters = name
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// `JUL 23, 2026 · SALES CALL · 24:31` — every segment backed by real data.
    /// The date arrives already formatted so the caller owns locale/style.
    static func eyebrow(for record: MemoryNote, dateText: String) -> String {
        var parts = [dateText.uppercased(), record.noteKind.label.uppercased()]
        if record.origin != .written, record.duration > 0 {
            parts.append(SessionArchive.clock(record.duration))
        }
        return parts.joined(separator: " · ")
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
