---
bug_id: c3f8e6
date: 2026-09-27
batch: single-owner-a2a (single-owner remediation batch, docs/plans/2026-09-26-single-owner-batch-a.md — a2a, converged in review round 4 with zero material findings against this scope)
status: fixed
blast_radius: platform
symptom: |
  `daily-snapshot/index.ts` (before this fix) had three defects, each
  verified by reading the code on 2026-09-27:
    1. Untestable. `serve(async (req) => {...})` ran at MODULE SCOPE with no
       `import.meta.main` guard, so importing this file for any test would
       boot a real Deno HTTP server (the exact trap
       `supabase/functions/CLAUDE.md` warns about). `extractCoachingNotes`
       was also not exported and called `geminiChat` directly with no
       injectable seam, so a2b's own upcoming metering rewrite would have
       had nothing to test against without hitting a live Gemini call.
    2. No kill switch. Unlike `daily-snapshot`'s own sibling fix in the same
       function (the merge-safe upsert, `DISABLE_SNAPSHOT_MERGE_SAFE_UPSERT`,
       diagnose d8a2f6), the coaching-notes extraction path — which spends a
       real Gemini Flash call — had no way to disable it without a redeploy.
       Platform tier requires a `feature_flag` per `docs/blast_radius.yaml`.
    3. Privacy-mode checked too late. `coach_memory.private_mode` was
       checked ONLY inside `mergeCoachMemoryFields` (`:276` before this fix),
       which ran AFTER `extractCoachingNotes` had already spent a Gemini
       call and AFTER `mergeCoachingNotes` had already written
       `diet_preference`/`injuries`/`lifestyle_notes`/etc. unconditionally
       into `user_preferences.coaching_notes`, `memory_embeddings`, and
       `user_profile`. A user who opted into private mode would still have
       their chat content read, sent to Gemini, and persisted into three
       other tables — only the `coach_memory`-specific identity fields
       (preferred_name, communication_style, ...) were actually withheld.
       Currently LATENT: grepping `lib/` confirms no client-side writer ever
       sets `private_mode = true` (it is only ever read, in
       `ai_snapshot_builder.dart:1002`, and defaulted/preserved in the Dart
       model) — but structurally a privacy leak the moment a toggle exists.
  Found during the a2 brainstorm/review cycle (round 3 finding #9 on the
  original plan) and re-confirmed by reading the live code before touching
  it, per §4.1.5.
concept: coaching_notes / coach_memory extraction
sot_registry_entry: |
  user_preferences_coaching_notes, coaching_notes (both touched by the
  B-pass remediation below — new concept user_preferences_coaching_notes
  added, existing coaching_notes concept gained a cross-reference guard
  note; see the "B-pass remediation" section for full detail)
writers:
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "handler() — DISABLE_COACH_EXTRACTION kill switch + private_mode gate, now checked BEFORE the 6h staleness check and before any Gemini call", line: 453 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "extractCoachingNotes — exported, injectable geminiChatFn (defaults to the real geminiChat; no production call site passes a second argument)", line: 56 }
readers:
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "handler() — if (import.meta.main) { serve(handler); }, replacing the unguarded module-scope serve(...) call", line: 520 }
  - { file: supabase/functions/daily-snapshot/index_test.ts, method_or_widget: "4 new source-grep tests: the import.meta.main guard, the exported injectable extractCoachingNotes, the kill switch's position before the coach_memory read, and private_mode's position before isStale/the extraction call", line: 149 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: coach_memory
cloud_columns: [user_id, private_mode, last_extraction_at]
contract_test_path: supabase/functions/daily-snapshot/index_test.ts
ist_handling:
  - "Unchanged by this fix — the 6h staleness window and IST snapshot-date computation are untouched. a2b (separate, own review) replaces the fixed-bucket staleness check with a watermark read; that is out of scope here."
provider_invalidations: []
telemetry_op_types: []
cross_account_guard: Not applicable — no client-side account state is read or written; the gate is server-side on the JWT-derived user id only.
forbidden_patterns_checked:
  - "removing the redundant private_mode check inside mergeCoachMemoryFields now that the caller gates earlier — rejected: it is now unreachable in practice but harmless defense-in-depth for a privacy-sensitive path, and removing it is not part of what this fix needs to do."
  - "changing what extractCoachingNotes reads (channel filter, read window) or how extraction is metered — explicitly a2b's scope, reviewed separately, so as not to conflate a converged (a2a) and a still-under-review (a2b) piece in one diff."
  - "fail-closed on a fetchCoachMemory read error — rejected: fetchCoachMemory collapses 'no row yet' and 'genuine read error' to the same null, and failing closed on that would block a legitimate first-time user with no coach_memory row at all; matches this function's existing non-fatal-on-error posture everywhere else in the same handler."
proposed_fix: |
  - `extractCoachingNotes` exported; gained an injectable
    `{ geminiChatFn = geminiChat }: { geminiChatFn?: typeof geminiChat } = {}`
    parameter, defaulting to the real import. Its one Gemini call site now
    calls `geminiChatFn(...)` instead of the bare import.
  - `handler()` (renamed from the anonymous `serve(async (req) => {...})`
    callback) now boots only under `if (import.meta.main) { serve(handler); }`.
  - `DISABLE_COACH_EXTRACTION` kill switch (`Deno.env.get(...) === "true"`),
    read per call — no redeploy needed to disable extraction.
  - `fetchCoachMemory` moved to run once, with its `private_mode` checked
    IMMEDIATELY after, before computing `isStale` or calling
    `extractCoachingNotes` at all. `!existing?.private_mode` (optional
    chaining) so an absent row or a read error both fail open, matching the
    surrounding try/catch's existing non-fatal posture.
regression_test_planned: |
  4 new Deno source-grep tests in daily-snapshot/index_test.ts (matching
  this file's existing convention — see its header for why this stays
  source-grep rather than a dynamic-import behavioral test): the
  import.meta.main guard exists AND the old unguarded serve(async...) form
  is gone; extractCoachingNotes is exported with the injectable default;
  the kill switch is checked before the coach_memory read it gates;
  private_mode is checked before isStale and before the extraction call.
  One pre-existing test (OI-238's lastError-destructure pin) was repointed
  from the literal `geminiChat(` call site to `geminiChatFn(` — the call
  site moved under its new name, the assertion is unchanged.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No client (lib/) file touched — server-side Edge Function only." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none supabase/functions/daily-snapshot/index.ts — Check OK. Not yet deployed; deploy needs its own founder go per §4.3, tracked with the rest of this batch's deploy list." }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "This function touches Postgres tables only, no Storage." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "The 200 response shape (status, snapshot_date, coaching_extracted, coach_memory) is unchanged; coaching_extracted is still `extractedFacts !== null`, now simply gated earlier by the same variable." }
impact_analysis: |
  No behavior change for any currently-real user, since private_mode is
  latent (0 rows set it live) and DISABLE_COACH_EXTRACTION defaults to
  unset/false. This is a structural fix that only changes behavior the
  moment a private-mode toggle ships client-side, or the kill switch is
  flipped. What this function reads/meters (the 6h staleness window, the
  chat-channel selection, the read cap) is entirely unchanged — that is
  a2b's scope, under its own separate review, specifically so a converged
  piece (a2a) does not have to wait on a still-under-review piece (a2b).
---

# daily-snapshot coaching-notes extraction: untestable, no kill switch, privacy gate too late

## Mutation proof (rule 21)

Each mutation applied by exact-string replacement (anchor confirmed present,
match count checked), full `daily-snapshot/index_test.ts` run, then reverted
byte-for-byte and re-confirmed against the pre-mutation file (`deno check`
clean, all 13 tests green).

| Mutation | Red |
|---|---|
| A — moved the `private_mode` guard to AFTER `isStale` (restoring the pre-fix ordering, wrapping the extraction call in `if (isStale && !existing?.private_mode)` instead of gating the whole block) | 2 / 13 (`private_mode is checked BEFORE...`, `private_mode gate fails OPEN...`) |
| B — neutered the kill switch (`const extractionDisabled = false;`, deleting the `Deno.env.get(...)` read) | 1 / 13 (`daily-snapshot has a DISABLE_COACH_EXTRACTION kill switch...`) |
| C — removed the `import.meta.main` guard, restoring a bare `serve(handler);` | 1 / 13 (`daily-snapshot boots the server ONLY under import.meta.main`) |
| D — reverted `extractCoachingNotes` to unexported with no injectable parameter, and its call site back to bare `geminiChat(` | 2 / 13 (`extractCoachingNotes destructures lastError...`, `extractCoachingNotes is exported with an injectable geminiChatFn...`) |

Each mutation reddened exactly the test(s) written for that guard and no
others — confirmed by diffing the full 13-line pass/fail summary against the
clean baseline for each of the four runs.

## Related

Same shape as a1's own findings in this batch (125b81, e5c9d2): a gate that
exists but runs too late to prevent the thing it's supposed to prevent. Not
a literal recurrence of the same bug — different table, different guard —
but the same class, worth citing per §4.1.5.

## B-pass remediation (context-blind review, agent a621939efa88341db)

Two findings, both verified against live code before acting (neither taken
on the reviewer's word alone) and both fixed in this same commit:

- **Finding 1 (P2, blast_radius_mismatch — CONFIRMED).** The already-converged
  plan (`docs/plans/2026-09-26-single-owner-batch-a.md:262`, round-4
  disposition) named a2a dependent #7 as: "the three 'same shape' test
  headers, `sot_registry.yaml` guard note, `user_preferences.coaching_notes`
  as its own concept" — none of which landed in the first diff. Verified live:
  `weekly-report/index_test.ts`, `assess-body-composition/index_test.ts` and
  `rolling-context/index_test.ts` each carried a header citing
  daily-snapshot/index.ts as a same-shaped sibling still lacking an
  `import.meta.main` guard — stale the moment this fix gave daily-snapshot
  that guard. Fixed: all three headers repointed at each other + noted
  daily-snapshot's new shape. Added `user_preferences_coaching_notes` as its
  own SoT concept (`docs/sot_registry.yaml`, `presence_only: true` — no
  live-Postgres round-trip test exists, matching rule 21's documented escape
  for an infeasible behavioral test) with daily-snapshot's `mergeCoachingNotes`
  and assess-body-composition's rate-limit stamp as writers,
  `sync_profile.dart` + `restore-user-snapshot/index.ts` as readers; added a
  cross-reference "guard note" to the pre-existing (unrelated, same-named)
  `coaching_notes` Hive-singleton concept so the two are never conflated
  again. New test: `test/contracts/user_preferences_coaching_notes_writer_to_reader_test.dart`
  (5 tests, mutation-proven — see below).
- **Finding 2 (P3, asserted_fixture_value / guard_without_its_mirror —
  ACKNOWLEDGED, no code change).** The 4 new a2a tests are pure
  source-position/string checks with no live invocation of
  `extractCoachingNotes` or `handler()`. Accepted as-is: this file's own
  header (unchanged by this batch) already documents WHY — module-scope
  `Deno.env.get(...)!` reads throw on any dynamic import without env vars
  set, the same constraint `supabase/functions/CLAUDE.md`'s AI-architecture
  section records for all 5 sibling functions using this identical pattern
  (weekly-report, assess-body-composition, rolling-context, ai-media-proxy).
  A real behavioral test is infeasible here without a broader test-harness
  change out of scope for this fix; the mutation-proof table above is this
  codebase's documented substitute (§4.4 rule 21) for exactly this
  circumstance, and each of the 4 new tests is individually mutation-proven
  in that table. a2b (separate, own review) is expected to build real
  behavioral coverage on top of this seam once it exists.

### Mutation proof — user_preferences_coaching_notes test (new)

| Mutation | Red |
|---|---|
| E — `daily-snapshot`'s `.select("coaching_notes")` renamed to a nonexistent column, breaking the read-before-merge | 1 / 5 (`daily-snapshot read-merge-writes...`) |
| F — `sync_profile.dart` reintroduced `p['coaching_notes']` (the exact pre-OI-98 forbidden pattern) | 1 / 5 (`client never includes coaching_notes...`) |

Both applied by exact-string edit, confirmed present (`grep -c`), test run,
then reverted byte-for-byte and re-confirmed clean (`git diff --stat` showed
no residual change to either mutated file; all 5 tests green).
