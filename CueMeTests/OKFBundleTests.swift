import XCTest
@testable import CueMe

final class OKFBundleTests: XCTestCase {
    // MARK: AC1 — sibling slugs disambiguate with -2, -3.

    func testDisambiguatesSiblingSlugs() {
        let first = OKFBundle.uniqueSlug("Reunião", taken: [])
        XCTAssertEqual(first, "reuniao")

        let second = OKFBundle.uniqueSlug("Reunião", taken: [first])
        XCTAssertEqual(second, "reuniao-2")

        let third = OKFBundle.uniqueSlug("Reunião", taken: [first, second])
        XCTAssertEqual(third, "reuniao-3")
    }

    // MARK: AC2 — a slug colliding with a reserved name falls through to the
    // next free numbered candidate, sharing the same counter as `taken`.

    func testRejectsReservedSlugs() {
        XCTAssertEqual(OKFBundle.uniqueSlug("raw", taken: []), "raw-2")
        XCTAssertEqual(OKFBundle.uniqueSlug("index", taken: []), "index-2")
        XCTAssertEqual(OKFBundle.uniqueSlug("log", taken: []), "log-2")

        // "index-2" is separately taken: the reserved base and the taken
        // suffix share one numbering sequence, so the winner is "index-3".
        XCTAssertEqual(OKFBundle.uniqueSlug("index", taken: ["index-2"]), "index-3")
    }

    // MARK: AC3 — an untitled session is named from local wall-clock time.

    func testUntitledSessionUsesLocalTimestamp() {
        let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = saoPaulo
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 8
        components.hour = 14
        components.minute = 30
        let startedAt = calendar.date(from: components)!

        XCTAssertEqual(
            OKFBundle.untitledSlug(startedAt: startedAt, timeZone: saoPaulo),
            "2026-08-08-1430"
        )
    }

    // MARK: AC4 — diacritics, emoji, punctuation and repeated spaces fold to
    // a slug made only of [a-z0-9-].

    func testFoldsDiacriticsAndPunctuation() {
        let slug = OKFBundle.slug("Reunião 🎉  de Projeto!!  Ação   Rápida")

        XCTAssertEqual(slug, "reuniao-de-projeto-acao-rapida")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        XCTAssertTrue(slug.unicodeScalars.allSatisfy(allowed.contains))
    }

    // MARK: AC5 — a title longer than 54 useful characters truncates without
    // leaving a hyphen at the border.

    func testTruncatesWithoutTrailingHyphen() {
        let word = "abcdefgh" // 8 letters; "word-" units are 9 chars, so 6 units
        // land exactly on position 54 — the truncation point is a hyphen.
        let title = Array(repeating: word, count: 7).joined(separator: " ")

        let slug = OKFBundle.slug(title)

        XCTAssertEqual(slug, Array(repeating: word, count: 6).joined(separator: "-"))
        XCTAssertFalse(slug.hasSuffix("-"))
        XCTAssertFalse(slug.hasPrefix("-"))
        XCTAssertLessThanOrEqual(slug.count, 54)
    }

    // MARK: AC6 — slug uniqueness is scoped to whatever `taken` set the
    // caller passes, i.e. per directory, not global.

    func testSlugUniquenessIsPerDirectory() {
        let inFirstDirectory = OKFBundle.uniqueSlug("Reunião", taken: [])
        let inSecondDirectory = OKFBundle.uniqueSlug("Reunião", taken: [])

        XCTAssertEqual(inFirstDirectory, "reuniao")
        XCTAssertEqual(inSecondDirectory, "reuniao")
    }

    // MARK: isReserved's two calling conventions — bare name for a
    // directory-shaped entry, extensioned name for a file-shaped entry.

    func testIsReservedHonorsExtensionConvention() {
        // Directory-shaped: "raw" is reserved only inside a note's own
        // folder, never at the bundle root, and never as "raw.md".
        XCTAssertTrue(OKFBundle.isReserved("raw", atRoot: false))
        XCTAssertFalse(OKFBundle.isReserved("raw", atRoot: true))
        XCTAssertFalse(OKFBundle.isReserved("raw.md", atRoot: false))

        // File-shaped: index.md / log.md are reserved at every level; the
        // bare name without extension never matches.
        XCTAssertTrue(OKFBundle.isReserved("index.md", atRoot: false))
        XCTAssertTrue(OKFBundle.isReserved("index.md", atRoot: true))
        XCTAssertTrue(OKFBundle.isReserved("log.md", atRoot: true))
        XCTAssertFalse(OKFBundle.isReserved("index", atRoot: false))
        XCTAssertFalse(OKFBundle.isReserved("log", atRoot: true))

        // AGENTS.md is reserved only at the bundle root.
        XCTAssertTrue(OKFBundle.isReserved("AGENTS.md", atRoot: true))
        XCTAssertFalse(OKFBundle.isReserved("AGENTS.md", atRoot: false))
    }

    // MARK: pure path math for the bundle layout — no filesystem access.

    func testBundleURLsComposePathsWithoutIO() {
        let directory = URL(fileURLWithPath: "/tmp/corpus/acme", isDirectory: true)

        XCTAssertEqual(
            OKFBundle.noteURL(slug: "reuniao-1", in: directory).path,
            "/tmp/corpus/acme/reuniao-1.md"
        )
        XCTAssertEqual(
            OKFBundle.noteFolder(slug: "reuniao-1", in: directory).path,
            "/tmp/corpus/acme/reuniao-1"
        )
        XCTAssertEqual(
            OKFBundle.rawDirectory(slug: "reuniao-1", in: directory).path,
            "/tmp/corpus/acme/reuniao-1/raw"
        )
        XCTAssertEqual(
            OKFBundle.attachmentsDirectory(slug: "reuniao-1", in: directory).path,
            "/tmp/corpus/acme/reuniao-1/raw/attachments"
        )
    }
}
