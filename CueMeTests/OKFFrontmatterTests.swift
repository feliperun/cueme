import Foundation
import XCTest
@testable import CueMe

/// Regression tests for `OKFFrontmatter`, the YAML frontmatter codec for OKF
/// notes. See `specs/okf-corpus/tasks/T003-frontmatter-codec.md` for the
/// acceptance criteria (AC1-AC6) this file proves.
final class OKFFrontmatterTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_770_000_000) // 2026-02-02T02:40:00.000Z

    // MARK: - AC1: unknown keys are preserved verbatim, after known keys

    func testPreservesUnknownKeysVerbatim() throws {
        let markdown = """
        ---
        type: Note
        x_mystery:
          nested: value
          other: 42
        title: Hello
        ---

        Body.
        """

        let parsed = try XCTUnwrap(OKFFrontmatter.decode(markdown, knownKeys: ["type", "title"]))
        XCTAssertEqual(parsed.unknownYAML, "x_mystery:\n  nested: value\n  other: 42")
        XCTAssertNil(parsed.fields["x_mystery"], "unknown keys must not be typed as known fields")

        let ordered: [(String, OKFValue)] = [
            ("type", try XCTUnwrap(parsed.fields["type"])),
            ("title", try XCTUnwrap(parsed.fields["title"])),
        ]
        let reencoded = OKFFrontmatter.encode(ordered, unknownYAML: parsed.unknownYAML)

        XCTAssertEqual(reencoded, """
        ---
        type: Note
        title: Hello
        x_mystery:
          nested: value
          other: 42
        ---
        """, "unknown keys must be re-emitted literally, after every known key")
    }

    // MARK: - AC2: encoding is a pure, deterministic function

    func testEncodingIsDeterministic() {
        let ordered: [(String, OKFValue)] = [
            ("type", .string("Note")),
            ("title", .string("Estratégia de frota elétrica")),
            ("tags", .array([.string("frota"), .string("mobilidade")])),
            ("generated", .mapping([
                ("by", .string("cueme/test")),
                ("at", .date(fixedDate)),
            ])),
        ]

        let first = OKFFrontmatter.encode(ordered, unknownYAML: "")
        let second = OKFFrontmatter.encode(ordered, unknownYAML: "")

        XCTAssertEqual(first, second)
    }

    // MARK: - AC3: nil when there is no frontmatter, or `type` is missing/empty

    func testRejectsDocumentWithoutTypeOrFrontmatter() {
        XCTAssertNil(
            OKFFrontmatter.decode("# Just a heading\n\nNo frontmatter here.", knownKeys: ["type"]),
            "a document with no --- delimiters at all"
        )
        XCTAssertNil(
            OKFFrontmatter.decode("---\ntitle: Hello\n---\n\nBody.", knownKeys: ["title"]),
            "frontmatter present but no type key"
        )
        XCTAssertNil(
            OKFFrontmatter.decode("---\ntype: \"\"\ntitle: Hello\n---\n\nBody.", knownKeys: ["type", "title"]),
            "type present but empty"
        )
    }

    // MARK: - AC4: hostile scalars round-trip without loss

    func testRoundTripsHostileScalars() throws {
        let hostileValues = [
            "",
            "true",
            "42",
            "2026-08-08",
            "- começa com indicador",
            "tem: dois pontos",
            "tem #hash",
            " espaço na borda ",
            "multi\nlinha",
            "emoji 🚗 e ç",
        ]

        for original in hostileValues {
            let markdown = OKFFrontmatter.encode(
                [("type", .string("Note")), ("value", .string(original))],
                unknownYAML: ""
            )
            let parsed = try XCTUnwrap(
                OKFFrontmatter.decode(markdown, knownKeys: ["type", "value"]),
                "failed to decode round trip for \(original.debugDescription)"
            )
            guard case let .string(roundTripped, _)? = parsed.fields["value"] else {
                XCTFail("expected a .string value for \(original.debugDescription)")
                continue
            }
            XCTAssertEqual(roundTripped, original, "round trip mismatch for \(original.debugDescription)")
        }
    }

    // MARK: - AC5: dates are always double-quoted, and decode back as String

    func testDatesStayQuotedStrings() throws {
        let markdown = OKFFrontmatter.encode(
            [("type", .string("Note")), ("created_at", .date(fixedDate))],
            unknownYAML: ""
        )

        XCTAssertTrue(
            markdown.contains(#"created_at: ""#),
            "the date must be emitted between double quotes:\n\(markdown)"
        )

        let parsed = try XCTUnwrap(OKFFrontmatter.decode(markdown, knownKeys: ["type", "created_at"]))
        guard case let .string(value, alwaysQuoted)? = parsed.fields["created_at"] else {
            XCTFail("decoding a quoted date must yield .string, not a YAML timestamp")
            return
        }
        XCTAssertTrue(alwaysQuoted, "a double-quoted scalar must be reported as always-quoted on decode")
        XCTAssertFalse(value.isEmpty)
        // Must not silently re-resolve as a YAML 1.1 timestamp: decode gives back
        // exactly the ISO-8601 text, as a plain String.
        XCTAssertTrue(value.hasSuffix("Z"))
    }

    // MARK: - AC6: byte-exact reproduction of the golden frontmatter

    func testReproducesGoldenFrontmatterByteForByte() throws {
        let goldenMarkdown = try String(contentsOf: Self.goldenNoteURL, encoding: .utf8)
        let goldenFrontmatterBlock = try Self.frontmatterBlock(of: goldenMarkdown)

        let knownKeys: Set<String> = [
            "type", "title", "description", "tags", "created_at", "updated_at", "generated", "sources",
            "x_cueme_links", "x_cueme_id", "x_cueme_kind", "x_cueme_mode", "x_cueme_origin", "x_cueme_training",
            "x_cueme_title_source", "x_cueme_ended_at", "x_cueme_lang", "x_cueme_participant_names",
            "x_cueme_models", "x_cueme_audio", "x_cueme_integrity", "x_cueme_transcript",
            "x_cueme_attachments", "x_cueme_vocabulary", "x_cueme_coach_feedback",
        ]
        let orderedKeys = [
            "type", "title", "description", "tags", "created_at", "updated_at", "generated", "sources",
            "x_cueme_links", "x_cueme_id", "x_cueme_kind", "x_cueme_mode", "x_cueme_origin", "x_cueme_training",
            "x_cueme_title_source", "x_cueme_ended_at", "x_cueme_lang", "x_cueme_participant_names",
            "x_cueme_models", "x_cueme_audio", "x_cueme_integrity", "x_cueme_transcript",
            "x_cueme_attachments", "x_cueme_vocabulary", "x_cueme_coach_feedback",
        ]

        let parsed = try XCTUnwrap(OKFFrontmatter.decode(goldenMarkdown, knownKeys: knownKeys))
        XCTAssertEqual(parsed.unknownYAML, "", "the golden fixture declares no unknown keys")

        let ordered: [(String, OKFValue)] = try orderedKeys.map { key in
            (key, try XCTUnwrap(parsed.fields[key], "golden is missing known key \(key)"))
        }

        let reencoded = OKFFrontmatter.encode(ordered, unknownYAML: parsed.unknownYAML)

        XCTAssertEqual(reencoded, goldenFrontmatterBlock)
    }

    // MARK: - Fixture helpers

    private static var goldenNoteURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CueMeTests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("specs/okf-corpus/contracts/note.md")
    }

    /// Slices out the `---`-delimited frontmatter block (both delimiters
    /// included, no trailing newline) from a full note markdown string.
    private static func frontmatterBlock(of markdown: String) throws -> String {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---",
              let closeIndex = lines.dropFirst().firstIndex(of: "---") else {
            throw XCTSkip("golden fixture has no frontmatter delimiters")
        }
        return lines[0...closeIndex].joined(separator: "\n")
    }
}
