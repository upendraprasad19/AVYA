---
reviewed_at: 2026-09-21T18:14:05+05:30
staged_against: b87e8a1f3f2a
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, modelled_on_is_a_checkable_claim, self_attesting_artifact]
findings_count: 6
verdict: accepted
---

# Code Review — b87e8a1f3f2a

All 6 findings accepted and fixed in-batch (this file's own triage — no separate
founder round-trip needed for a platform-tier advisory verdict per §4 triage
workflow). Each fix independently verified: `deno check`/`flutter analyze`
clean, new/updated tests run green, and the two mutation-sensitive fixes
(Finding 1, and the pre-existing snapshot_merge tests) reproduced red with the
fix reverted before being restored.

## Finding 1 — P1 — guard_without_its_mirror (also writer_reader_drift)
- **file:line:** `supabase/functions/_shared/snapshot_merge.ts:27`; `lib/features/ai_coach/services/ai_snapshot_builder.dart:165` + `:1009-1011`; `lib/core/services/sync_service.dart:1157-1179` (now 1157-1215 post-fix)
- **claim:** `mergeSnapshotJson`'s `{...existing, ...incoming}` protects `morning_alert` (the client never sends it) but NOT `fitness_summary` — `AiSnapshotBuilder.buildAiContext()` unconditionally includes it (defaults to `''`, never omitted), and that same map becomes the `daily-snapshot` push payload, so the client's own lagging/empty local mirror of a CRON-OWNED key wins the merge and clobbers `rolling-context`'s fresher server write.
- **verification:** Confirmed live: `ai_snapshot_builder.dart:165` `'fitness_summary': _getFitnessSummary()` with no null-aware omission; `:1009-1011` defaults to `''`; `sync_service.dart:1234,1248-1256` traced `compileDailySnapshot()`'s output as the EXACT `{'snapshot_json': snapshot}` body sent to `daily-snapshot`.
- **fix applied:** `compileDailySnapshot()` now explicitly `.remove('fitness_summary')` from the push payload after the `aiContext` spread, leaving `buildAiContext()`'s direct chat-context use (which needs the field) untouched. `docs/sot_registry.yaml`'s `daily_snapshot_server_key_preservation` concept updated with this as a third writer entry + a `class_constraints:` note on the scoping lesson.
- **status:** fixed — `test/contracts/daily_snapshot_fitness_summary_omission_test.dart` (2 tests, mutation-proven: reverting the `.remove()` call reddens both).

## Finding 2 — P1 — blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml:23-25` (platform tier `requires: [..., feature_flag]`), `:58`/`:61` (daily-snapshot/`_shared` are platform tier)
- **claim:** No kill-switch anywhere around the new merge-read-write path; the old blind-upsert code path isn't preserved/reachable, violating platform tier's `feature_flag` requirement and CLAUDE.md §4.6.
- **verification:** `grep -in "kill.switch\|feature.flag\|DISABLE_"` over the staged diff returned zero hits, confirmed.
- **fix applied:** Added `DISABLE_SNAPSHOT_MERGE_SAFE_UPSERT` env-var kill-switch in `daily-snapshot/index.ts` — when set `"true"`, skips the SELECT+merge entirely and falls back to the verbatim pre-fix blind-replace (`mergedSnapshotJson` defaults to the raw `snapshot_json` payload).
- **status:** fixed — pinned by a new `index_test.ts` assertion checking both the env-var gate and its correct raw-payload fallback value.

## Finding 3 — P2 — function_exception_swallow (also missing_input)
- **file:line:** `supabase/functions/daily-snapshot/index.ts` (pre-fix :350-355, the existing-row SELECT)
- **claim:** The SELECT destructures only `data`, discarding `error` — a genuine query failure (not "no row") takes the same code path as a legitimate absent row, silently reproducing the pre-fix blind-overwrite behavior with zero log trace.
- **verification:** Confirmed — only `const { data: existingRow } = await ...` was destructured; the upsert 12-19 lines below DOES check its own error by contrast.
- **fix applied:** Now destructures `error: existingRowError` too and `console.error`s it before proceeding with the (still-safe) empty-merge-base fallback — makes the degradation observable rather than indistinguishable from the legitimate case.
- **status:** fixed — pinned by a new `index_test.ts` assertion.

## Finding 4 — P2 — blast_radius_mismatch (account tier)
- **file:line:** `lib/features/ai_coach/screens/ai_coach/compact_header.dart`, `telegram_view.dart`; `docs/blast_radius.yaml:267` (account tier requires `regression_test`)
- **claim:** No test pins the Telegram UI removal — the `telegram` menu item's absence, `switch_channel`'s continued presence, or `telegram_view.dart`'s connected-only CTA gating.
- **verification:** Confirmed via grep — only an unrelated widget test references `compact_header.dart` by path, no telegram-specific assertion anywhere.
- **fix applied:** New source-grep contract test (see below) pinning all three behaviors the finding named. Explicitly labeled in its own header as presence-only, not a rendered-widget test — both files are `part of 'screen.dart'` and a real widget pump would need substantial Riverpod/Hive fixture scaffolding disproportionate to a P2 on already-hand-verified UI logic.
- **status:** fixed — `test/contracts/telegram_connect_ui_removed_test.dart` (4 tests, all green).

## Finding 5 — P2 — self_attesting_artifact
- **file:line:** `docs/diagnoses/2026-09-21-morning-alert-snapshot-clobber-d8a2f6.md:21` (frontmatter `writers:` — cited line 341, a stale carry-forward from the OLDER e4a1b7 doc's citation of the SAME line number in the pre-fix file)
- **claim:** Line 341 in the current file is a comment, not the SELECT/merge/upsert logic it claims to describe.
- **verification:** Confirmed — `grep -n "line: 341"` across both diagnose-docs showed the citation was copied forward without re-deriving against the new file, which had ~20 lines inserted above the cited point.
- **fix applied:** Re-derived against the CURRENT file state (which, by the time of fixing, had moved AGAIN due to Findings 2+3's kill-switch addition) — now cites `line_range: "339-397"` with three specific sub-line pointers (SELECT :362, merge :383, upsert :396) plus the new kill-switch line (:356). `docs/sot_registry.yaml`'s parallel citation for the same file was independently re-derived the same way — its own line_range had gone stale a SECOND time from the Finding-1 fix to `sync_service.dart`, catching (and fixing) two more stale citations for UNRELATED methods (`applyRestoreCeiling`, `restoreFailureReason`) that `check_sot_registry_parity.dart` flagged during pre-commit.
- **status:** fixed — both `validate_diagnose_doc.dart` and `check_sot_registry_parity.dart` pass clean.

## Finding 6 — P4 — guard_without_its_mirror (cosmetic)
- **file:line:** `lib/features/ai_coach/screens/ai_coach/compact_header.dart:177-178`
- **claim:** `_menuItemsForChannel`'s `telegramConnected` parameter is now dead — nothing in its body references it after the connect-flow removal.
- **verification:** Confirmed via full-file read; `flutter analyze lib/` baseline unaffected either way (unused params aren't a Dart analyzer warning).
- **fix applied:** Dropped the parameter from `_menuItemsForChannel` and its one call site. Left `_buildCompactHeader`'s own `telegramConnected` parameter untouched (still accepted from its caller in `screen.dart`, just no longer forwarded) — matching the finding's own scoped suggestion rather than cascading the removal further up.
- **status:** fixed.

## Lenses that returned clean (unchanged from the dispatched report)

- **secrets_in_tree** — `grep -in` credential-shaped patterns over the full staged diff: zero hits, manually re-read every added line.
- **unawaited_no_error_sink** — `grep -n "unawaited("` over the diff: zero matches.
- **asserted_fixture_value** — all 4 `snapshot_merge_test.ts` tests checked individually against the real implementation; the 2 that wouldn't redden under a no-op mutation are honestly self-disclosed as such in both the test file's header and the SoT registry notes.
- **modelled_on_is_a_checkable_claim** — the "mirrors morning-alert's generate mode" claim verified line-for-line against the real file; independently confirmed the other two cron writers (`beat-my-coach`, `future-prediction`) also already read-modify-write correctly.
- **missing_input** — `user_daily_snapshots`'s live/migration-defined columns confirmed via both the migration source and `backups/live_schema_columns.json`; the one real gap here (swallowed error) is Finding 3, not a schema mismatch.
