import Foundation

/// Finds and rewrites the links that point at a note, so renaming or moving one
/// does not leave dead paths behind in the rest of the corpus.
///
/// Resolution is by UUID, so a stale path is a portability problem — the corpus
/// opened in Obsidian shows a dead link — not a correctness one. OKF requires
/// consumers to tolerate broken links. The rewrite is therefore best-effort by
/// design, but its result is reported rather than swallowed.
enum BacklinkIndex {
    /// Every `.md` in the corpus that mentions `path`, excluding the note's own
    /// document.
    static func referencingDocuments(to path: String, in root: URL, excluding: URL?) -> [URL] {
        documentURLs(in: root).filter { url in
            guard url.standardizedFileURL != excluding?.standardizedFileURL,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return text.contains(path)
        }
    }

    /// Rewrites every mention of `old` to `new` across the corpus and returns
    /// how many documents changed. Covers Markdown link targets in the body and
    /// the path-valued frontmatter fields (`x_cueme_links`, `sources[].resource`)
    /// alike, because they are all just the path as text.
    @discardableResult
    static func rewriteReferences(from old: String, to new: String, in root: URL, excluding: URL? = nil) -> Int {
        guard old != new else { return 0 }
        var changed = 0
        for url in referencingDocuments(to: old, in: root, excluding: excluding) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rewritten = text.replacingOccurrences(of: old, with: new)
            guard rewritten != text,
                  (try? rewritten.write(to: url, atomically: true, encoding: .utf8)) != nil else { continue }
            changed += 1
        }
        return changed
    }

    private static func documentURLs(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
    }
}
