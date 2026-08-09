# Constitution — okf-corpus

Non-negotiable rules for every task in this plan. Read this before `spec.md`.
If a task instruction and this document disagree, **this document wins** — stop
and report the contradiction instead of choosing.

## 1. Scope discipline

- A task may only touch the files listed under **PODE TOCAR** in its own task
  file. Needing another file is a **stop-and-report**, not a judgement call.
- Do not fix unrelated problems you notice. Report them; they become new tasks.
- Do not add abstractions, protocols, or extension points "for later". Write the
  minimum code that satisfies the acceptance criteria.

## 2. No backward compatibility

Governed by [ADR 0043](../../docs/adr/0043-greenfield-compatibility-policy.md).

- Remove the old path. Do not add a fallback, a shim, a `legacy*` function, or a
  version branch.
- Do not keep a deleted symbol alive as a `typealias` or a forwarding wrapper.
- The one-shot migration script is the *only* place old formats are read, and it
  lives outside the app target.

## 3. TDD is mandatory

Red → Green → Refactor, in that order, with no exceptions in this plan.

1. Write the test named in the task's test table.
2. Run it. **See it fail.** A test that passes before the implementation exists
   is proving nothing — rewrite it.
3. Implement the minimum that makes it pass.
4. Run the full unit suite.

Report which tests you saw fail and what the failure message was. The reviewer
verifies this by reverting the implementation and re-running.

## 4. Test quality

- **Isolated** — no shared state between tests; every filesystem test uses a
  temp directory via `CorpusStore.rootOverride` / `SessionStore.rootOverride`.
- **Deterministic** — never `Thread.sleep`, never wall-clock assertions, never
  `Date()` without injection. Inject dates and the producer string.
- **Behavioural** — assert observable output, not internal call sequences.
- **Byte-exact where the contract is bytes.** Round-trip and golden-file tests
  compare full strings, never `contains`.

### The `Equatable` trap

`MemoryNote` conforms to `Equatable` **by `id` only**. `XCTAssertEqual(a, b)` on
two notes passes whenever the ids match, regardless of every other field. Any
round-trip test written that way is vacuous. Use `assertDeepEqual` (T009).

## 5. Structural gate

- Run `sentrux check .` and `sentrux gate .` before reporting done. Both must pass.
- **Never** silence, loosen, or exclude a rule to get past the gate. Fix the
  structure. Changing `.sentrux/rules.toml` requires an ADR and is out of scope
  for every task in this plan.
- Boy Scout Rule: a file you touch leaves with an equal-or-better score.

## 6. Language

- Code, identifiers, comments, commit messages, ADRs, and on-disk format keys and
  markers are **English**.
- User-visible strings and Markdown section headings in the corpus are
  **pt-BR**. This split is deliberate: it means changing the UI language never
  changes the on-disk contract.

## 7. Commits

- The task file names the exact Conventional Commit subject. Use it verbatim.
- **Do not commit.** The orchestrator commits after review. Leave the work in the
  working tree.
- Never `--no-verify`. If a hook blocks, the hook found a real problem.

## 8. Data safety

The corpus is the user's irreplaceable personal archive.

- No task may run the migration script against a real corpus. Tests use temp
  directories only.
- A write path that can *delete* user content without having loaded it first is
  a defect, even if no test catches it. The `TranscriptState` type exists
  precisely to make that unrepresentable — do not work around it.
- When in doubt between losing data and failing loudly, fail loudly.

## 9. Reporting

Every task report must contain:

- Files changed, grouped by added / modified / deleted.
- One line per acceptance criterion: `AC<n> → <test name>`.
- Pasted output of the three verification commands.
- **What you did not do, and why.**
- Every assumption you made that the spec did not settle.

Do not report success for work you did not verify. If the build passed but you
skipped the suite, say so.
