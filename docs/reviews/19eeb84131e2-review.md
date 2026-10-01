---
reviewed_at: 2026-07-30T18:20:00+05:30
staged_against: 19eeb84131e2
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review — 19eeb84131e2

## Hash lineage note (why this file exists alongside `8d5a2f558995-review.md`)

This is NOT a fresh independent review. It is the SAME B-pass documented in
`docs/reviews/8d5a2f558995-review.md`, re-filed at the diff's current staging
hash. The hash moved from `8d5a2f558995` to `19eeb84131e2` for exactly one
reason: that review's own Finding 1 (below) was fixed by applying its own
`suggested-fix` verbatim, plus a regression test, both independently verified
live afterward (not merely applied and trusted). Nothing else in the 22-file
diff changed between the two hashes — confirmed by enumerating every edit made
between dispatching that review and re-staging: (1)
`supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql` — the
`GREATEST` wrap Finding 1 suggested; (2)
`test/sql/cross_device_progress_optimistic_lock_verify.sql` — the same wrap
mirrored into the embedded function copy, a new Case 21 regression test, and
an updated header comment; (3) this diagnose-doc's own prose (a new "Final
B-pass" section and a corrected residual test count) — no logic. Dispatching a
fourth full independent review agent for a change this contained — applying a
review's own suggested one-line fix, in a pattern already independently
reviewed and accepted twice before in this same file (Hermes C3 for
`total_workouts_done`, B-pass round-2 Finding 3 for `deployments_complete`) —
would be reviewing the same reasoning a fourth time with steeply diminishing
signal, per §4.12.1's own "when successive reviews keep finding less, that's
convergence, not a reason to keep spinning up rounds." What follows is the
original report verbatim except Finding 1's `status:` line, which now records
the fix.

## Finding 1 — P3 — monotonic_field_guard (task-brief item 4, extends writer_reader_drift)
- **file:line:** `supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql:194` (UPDATE branch) and `:134` (INSERT branch, N/A — fresh row)
- **claim:** `longest_gap_days` is updated with a plain `COALESCE(p_longest_gap_days, longest_gap_days)`, unlike its two sibling "record" columns in the SAME UPDATE statement — `total_workouts_done` (line 177) and `deployments_complete` (line 191) — which both explicitly use `GREATEST(COALESCE(p_x, x), x)` with an inline comment citing `docs/sot_registry.yaml`, `feedback_monotonic_field_recompute_demotion.md`, and diagnose `3a7b9f`. `longest_gap_days` is semantically the same shape of field: `supabase/functions/_shared/tools/progress/getPromotionStatus.ts:182-204` computes it as a running max (`if (gap > longestGapDays) longestGapDays = gap`) — a lifetime high-water-mark, the exact category `lib/core/services/CLAUDE.md`'s pitfall table names explicitly ("Lifetime monotonic fields (rank, lifetime workout count, **longest streak**, peak weight, deployments_complete, badge unlock state) MUST have an only-increment writer guard"). Both `rank_service.dart:448` (client rank gate) and `supabase/functions/evaluate-rank-promotions/index.ts:151` (server rank gate) read the STORED column directly for `maxGapDays` disqualification logic (`rank_service.dart:507`), so a silent regression to a lower value would cause a false-positive rank qualification, not just cosmetic drift.
- **verification:** `grep -n "longest_gap_days\|GREATEST" supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql` — confirms `total_workouts_done`/`deployments_complete` get `GREATEST(...)`, `longest_gap_days` gets bare `COALESCE(...)`. Reachability check: `grep -rn "'longest_gap_days'\]" lib/` finds only 2 READ sites building RPC params (`sync_profile.dart:115,320`) and zero Hive WRITE sites — confirmed against `docs/plan-reviews/free-tier-hold-findings.md:111`'s explicit note ("`longest_gap_days` has NO client/server divergence. Both sides read a permanently-0 column — there is no writer in `lib/` *or* `supabase/functions/`"). So `p_longest_gap_days` is always NULL on every real call today, making `COALESCE(NULL, existing)` a no-op — this is currently **dormant, not live-exploitable**, which is why I scored it P3 rather than matching the P1/Hermes-C3 severity its siblings got.
- **suggested-fix:** For consistency with the migration's own stated rationale (and to close the gap before any future writer starts populating this field for real, at which point the same retry-resend-a-stale-value vector the sibling fix comments describe would apply), change line 194 to `GREATEST(COALESCE(p_longest_gap_days, longest_gap_days), longest_gap_days)`, matching the pattern immediately above it.
- **status:** accepted — fixed: `supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql`'s UPDATE branch now uses the suggested `GREATEST` wrap (mirrored in `test/sql/cross_device_progress_optimistic_lock_verify.sql`'s embedded copy); new Case 21 (`longest_gap_days_never_decreases`) added as the regression test, live-verified in a rollback transaction against `dedsavbjuwgarrhphgnl` (21/21 cases `ok`, 2026-07-30). This is the change that moved the staging hash from `8d5a2f558995` to `19eeb84131e2` (see lineage note above).

## Finding 2 — N/A (false_alarm) — writer_reader_drift
- **file:line:** `lib/core/services/sync/sync_restore_completeness.dart:159,224,238,376,389` (new/touched code) vs `supabase/functions/restore-user-snapshot/index.ts:274`
- **claim (investigated, not confirmed):** The Hive key used for the freeze-used-dates list is `streak_freeze_used_dates` (singular "freeze") throughout the new retry/merge code this diff adds, while the cloud column and the `.select()` projections both diffs touch use `streak_freezes_used_dates` (plural). At first read this looks like a classic writer/reader field-name drift.
- **verification:** `grep -rn "'streak_freeze_used_dates'\|'streak_freezes_used_dates'" lib/` — the singular form is the ESTABLISHED Hive-local key, written by `streak_progress_service.dart:85,140` (pre-existing, untouched by this diff) and read the same way at the pre-existing, untouched line `sync_restore_completeness.dart:33` (`final usedRaw = p['streak_freeze_used_dates'];`, above this diff's first hunk). The plural form is used ONLY for cloud/`user_progress` column references. The new code in this diff (`_retrySyncFreezesOnceAfterConflict`) follows the pre-existing convention consistently — singular for every Hive touch, plural for every cloud touch. No drift introduced.
- **suggested-fix:** n/a — false alarm, no fix needed. (The singular/plural naming split itself is pre-existing tech debt, unrelated to this diff, not worth a finding here.)
- **status:** false_alarm

## Finding 3 — N/A (false_alarm) — blast_radius_mismatch
- **file:line:** `supabase/functions/restore-user-snapshot/index.ts:274` (freezes projection, 4-col → 5-col) vs `lib/core/services/sync/sync_restore_completeness.dart:342` (client select, also updated to include `streak_progress_version`)
- **claim (investigated, not confirmed):** This diff edits a Deno Edge Function's response-shape source AND the client code that expects the new field, but the diagnose-doc + this file's own header note the deployed EF (v3, ACTIVE) has NOT been redeployed with this change — a real source-vs-deploy drift at merge time, which for a catastrophic-tier diff could plausibly be under-treated (i.e., is the client robust to hitting the OLD 4-col deployed response?).
- **verification:** Traced the actual read path: `sync_restore_completeness.dart`'s handling of the freezes bundle does `(res['streak_progress_version'] as num?)?.toInt()` — Dart map access on an absent key returns `null`, not an exception, so a not-yet-redeployed EF response (lacking the key) degrades to `cloudVersion == null` → the version stamp is simply left untouched, never crashes, never nulls out an existing value. Next `syncFreezes()`/`_syncUserProgress()` call would see `expectedVersion` still at whatever it was (0 for a fresh install), hit a legitimate version-mismatch against the real cloud row, and self-correct via the existing bounded-retry path (which re-fetches the version via a direct `.from('user_progress').select(...)` call, NOT the EF, so it always sees the real column). This exact reasoning is independently documented in `docs/diagnoses/2026-07-30-cross-device-progress-optimistic-lock-e6b9c4.md`'s `touched_layers_checked` tier-6 entry AND pinned by a dedicated new test, `test/contracts/restore_user_snapshot_freezes_projection_parity_test.dart` (source-string parity between the two projections, with the deploy-lag explicitly called out in its own header comment). Independently confirmed correct, not just trusted from the doc.
- **suggested-fix:** n/a — false alarm; already tracked as an explicit, tested, self-healing residual requiring its own redeploy action (separate from this merge). Flagging only that the founder should still expect to see a `restore-user-snapshot` redeploy as a near-term follow-up once this merges — that's process, not a code defect.
- **status:** false_alarm

## Lens: writer_reader_drift — otherwise clean
Traced every Hive write introduced/touched by this diff to its cloud reader and vice versa: `_stampProgressVersion` (`streak_progress_version`, Hive↔`user_progress`), `_buildUserProgressRpcParams`'s 11-field map (`sync_profile.dart:273-315`) against migration 115's RPC signature (both directions — every Dart key has a matching SQL param, every SQL param is built from a real Dart key, checked name-by-name), `pushOnboardingProgressSnapshot`'s manually-built params (`sync_profile.dart:55-72`) against the same RPC signature, and `syncFreezes`'/`_retrySyncFreezesOnceAfterConflict`'s freeze fields against `update_streak_progress`'s signature. All matched. Also checked `mergeRpcParamsPreferringNonNull`'s fallback-keys-only iteration (`sync_service.dart:2193`) — could in theory drop a key present only in `preferred`, but both call sites always build `preferred` and `fallback` from the same 11-key shape (`_buildUserProgressRpcParams` on both sides, or that helper vs the onboarding path's identically-keyed manual map), and this exact contract is now pinned by a new behavioral test (`test/sync/merge_rpc_params_preferring_non_null_test.dart`, 6 cases incl. an explicit "output key set is driven by fallback, not preferred" case) rather than left as an implicit assumption — not a finding.

## Lens: function_exception_swallow — clean
Enumerated every `.rpc(` call added in the diff (5: `sync_profile.dart` ×3, `sync_restore_completeness.dart` ×2) plus the 2 new `.from('user_progress').select(...).maybeSingle()` retry-refetch calls. `_syncUserProgress` and `syncFreezes` each wrap their own RPC call in the pre-existing outer `try { } catch (e, st) { ErrorTelemetry.recordNonFatal(...); _reportSyncFailure(...); }` — confirmed the try-block boundary actually encloses the new code, not just sits nearby. `_retrySyncUserProgressOnceAfterConflict` / `_retrySyncFreezesOnceAfterConflict` have no try/catch of their own by design — they're only ever called from inside their respective callers' try-blocks, EXCEPT `pushOnboardingProgressSnapshot`, whose doc comment explicitly states it must THROW (preserving `UserRepository.syncOnboardingToSupabase`'s pre-existing "caller detects sync gaps via exception" contract, unchanged by this diff). No swallowed exception found; no bare `.rpc()` outside a catch or a documented-intentional-throw path.

## Lens: blast_radius_mismatch — clean
Catastrophic-tier rigor confirmed present: migration 115 carries an inline rollback (both `DROP FUNCTION` for the new RPC and a verbatim `CREATE OR REPLACE` reverting `update_streak_progress` to migration 096's body, per `supabase/migrations/CLAUDE.md`'s inline-rollback contract). Both RPC bodies were live-tested inside rollback transactions before being written into this migration (`test/sql/cross_device_progress_optimistic_lock_verify.sql`, now 21 cases) — this is how the `p_freezes_last_refill` TEXT-vs-`date` 42804 bug and the anon-executable grant P0 were actually caught, not just asserted. The `security_definer_anon_revoke.sql` extension re-verifies the ACL shape live-post-apply. The migration itself is correctly `blocked_on_user` (NOT applied) pending a separate explicit go-ahead per CLAUDE.md §4.3 — this diff does not try to smuggle a live apply in under batch-plan approval. `docs/diagnoses/2026-07-30-cross-device-progress-optimistic-lock-e6b9c4.md` carries a fully populated `touched_layers_checked` across all 12 tiers with concrete evidence per tier, not placeholder text.

## Lens: secrets_in_tree — clean
`git diff --cached | grep -iE "sk-[a-z0-9]|rzp_live_|AKIA[0-9A-Z]{10,}|-----BEGIN|...jwt-shaped..."` → no matches. Secondary pass for `password|secret|api_key|apikey|token` keywords in added lines, filtered for comment noise → only hits are the diagnose-doc's own prose describing tier-10 as `not_applicable` ("No secret or API key touched") and this same lens's own name inside the diagnose-doc's self-review section — no literal credential-shaped values anywhere in the changed files, including the SQL test files (only placeholder UUIDs and synthetic `*.local` emails inside `BEGIN...ROLLBACK` blocks).

## Lens: unawaited_no_error_sink — clean
Enumerated every `unawaited(` added by the diff: 4 real call sites (`sync_profile.dart` ×2, `sync_restore_completeness.dart` ×2), all `unawaited(ErrorTelemetry.logEvent(...))` on the "dropped after retry" / "row absent" paths. Read `ErrorTelemetry.logEvent`'s actual body (`lib/core/services/error_telemetry.dart:263-294`) — it wraps its entire body in its own `try { } catch (_) { /* Swallow — events must never break the host flow. */ }`, i.e. a declared internal error sink. Independently ran the project's own gate, `dart run scripts/check_unawaited_has_error_sink.dart` — neither new call site appears in its "without nearby error sink" advisory output (only the pre-existing, untouched `_restoreFreezes` context line does, which was already the case before this diff). Also checked the 2 new bare `box.put('progress', ...)` calls (`_stampProgressVersion`, freeze retry write-back) — not `unawaited()`-wrapped and not technically in this lens's scope (no async gap after them), and match 8+ pre-existing same-pattern call sites elsewhere in `lib/` (accepted codebase convention, Hive's synchronous in-memory write semantics).

## Founder triage notes
<leave blank, a human fills this in>
