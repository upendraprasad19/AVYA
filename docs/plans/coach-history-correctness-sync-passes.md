# Plan — L1a-3 "exercise-log skip index: merge, don't overwrite; restore records what it wrote" (D5a, D2e)

**Version:** v2 (2026-10-06) — **redesigned after plan-review round 8 (R8P).** v1 serialised every exercise-log pass behind a `SerialSlot` with per-call timeouts; rounds 5–8 kept finding new P1s in that machinery (slot release vs the 45 s ceiling, an orphaned `whenComplete` future, an unbounded failure report wedging the slot, key starvation under the timeout cap). Re-reading what it protects: **neither defect loses data.** Overlapping passes only overwrite each other's skip-index confirmations, so the worst case is a redundant re-push; the restore echo is one redundant re-push per restored row. Both are fixed by making the index writes MERGE instead of overwrite, which needs no slot, no timeouts and no wrapper. v1's slot/timeout design and its round-8 findings (R8P-1..3) are withdrawn with it; R8P-4/5 dispositions §5.
**Umbrella:** `docs/superpowers/specs/2026-10-03-progress-review-design.md` v3.1, landing L1. Split from L1a-2 after round 7. **Depends on L1a-2 (merged)** — its restore (U2 a–d) decides which rows restore writes.
**Execution branch / worktree:** `coach-history-correctness-sync-passes`. **Mode:** inline, one coordinator.
**Blast radius:** `platform` (`lib/core/services/sync/**`). No migration, no Edge Function, no call-site or ceiling change.
**Status:** v3 — converged in round 9 (R9P: `converged`, two P2s applied, §6). No code.

---

## 1. Defects
| # | Defect | Evidence | Effect | Class |
|---|---|---|---|---|
| D5a | `SyncSkipIndex` snapshots the whole index at construction (`sync_skip_index.dart:131`) and `commit` writes the whole map back (`:270-285`); two overlapping exercise-log passes (entry points `sync_service.dart:1348`, `sync_workout.dart:63,2661`) overwrite each other's confirmations | code (R8P verified) | redundant re-pushes; no data loss | lost update on a local index; FULL |
| D2e | Restore records no fingerprint for the exercise logs it writes (`recordConfirmed`, `:306`, has one caller, plans, `sync_workout.dart:1455`) | code | every restored row is pushed back once; harmless after L1a-1 (identical push suppressed / one live row), but a full re-upload per restore | restore class (e6a2d4); FULL |

## 2. Units

**M1 · `commit` merges this pass's deltas.** The deltas are exactly (R9P-1): keys this pass PUSHED and confirmed (the `pushed++` branch, `sync_skip_index.dart:244`, including forced pushes whose fingerprint equals the snapshot) with their fingerprints, and keys it forgot — **never skipped keys** (`pushIfChanged` returns true for a skip, `:217`). Counting skips as confirmed would write the stale snapshot back exactly as today, including over a `clearAll` from a `sync_epoch` bump during the launch restore (`sync_service.dart:1735`) — the resync that M1 now preserves. The change is in the shared class, so it applies to all 17 skip-index domains, not only exlog (R9P verified no domain relies on the whole-map write except through prune/forget). `commit` re-reads the stored map and applies, in ONE synchronous section (no `await` between the read and the `box.put`, so no other Dart task can interleave — Hive runs on the one isolate): set each confirmed key, remove each forgotten key, prune keys not in `liveKeys` (unchanged rule, `:270-285`), and write only when something changed. The owner-change and disabled-index branches (`:258-260`) are unchanged. Effect: two overlapping passes both keep their confirmations; when both confirm the same key the later commit wins, and if its fingerprint is older than the Hive content the next pass sees the mismatch and re-pushes (the same safe outcome as today).

**M2 · restore records what it wrote.** Extract one pure `buildExlogPushBundle(userId, key, log)` from `_syncExerciseLogs` (`:276-470`; clamps, null-key guards, timed aggregate, L1a-2 U3's day rule) and use it in both push and restore (parity test: same map ⇒ same fingerprint). Restore evaluates it on the map actually written, only when its `put` ran (`sync_workout.dart` ~`:1023-1025`, never on the local-wins skip), and records the batch through a new `SyncSkipIndex.recordConfirmedAll(box, domain, Map)` with M1's merge (one read, one write, synchronous). Owner check (`ownerChangedSince(userId)`, `sync_service.dart:606-621`) immediately before the write; on a changed owner nothing is recorded. A pass that commits later with an older fingerprint for the same key only causes a re-push (M1).

**Tests.** M1: two `SyncSkipIndex` instances built from the same stored map each confirm different keys and commit in either order ⇒ both sets of keys are stored; both confirm the same key ⇒ the later commit's value is stored and a pass with newer Hive content re-pushes it; prune still removes non-live keys; owner change ⇒ no write; build the index, `clearAll`, skip key a, push key b, commit ⇒ the stored map is `{b}` only (R9P-1). M2: restored entries are not re-pushed (fingerprint equals the push's own — parity test); local-wins skip records nothing; owner change ⇒ nothing recorded; `recordConfirmedAll` writes once for N entries (write-counting box); a pass constructed before the restore and committed after it does not erase the restore's entries (M1 merge). Mutation-proven (rule 21): revert `commit` to the whole-map write ⇒ the two-instance test reddens; drop the restore call ⇒ the no-re-push test reddens.

## 3. Residual (founder decision 2026-10-06, unchanged)
A late upload that lands after a newer edit is accepted under "last sync or write wins" (decided before this redesign; it never depended on the slot). Ledger: half (b) `verified_clean`, evidence "founder decision 2026-10-06"; half (a) (a late drain) has **no separate row here** — under the corrected L1a-2 §10 decision ("newest action wins") a late drain only touches versions older than the delete; its residuals are L1a-2's ledger rows (`coach-history-correctness-client.md` §5) (R8P-5).

## 4. Process
Gate loop, ×2 plan review (this v2 is reviewed as a new design), B-pass, one `fix(...)` commit per unit with diagnose-docs (D5a, D2e), closure ledger `docs/audit/coach-history-correctness-sync-passes.closure.yaml`. SoT: `sync_exercise_log_payload_hash_index` gains `_restoreExerciseLogs` as a second writer (`docs/sot_registry.yaml:2334-2343`); `lib/core/services/CLAUDE.md:50` "sole writer AND reader" corrected. §4.6: no flag for M1 (the old whole-map write is the defect; outcome-identical for a single pass); M2 sits under L1a-2's restore switch `disable_exlog_restore_dedupe`. Founder builds the APK after merge.

## 6. Round-9 dispositions
| Finding | Disposition |
|---|---|
| R9P-1 ("confirmed" ambiguous; epoch-clear race) | Deltas defined as pushed-and-confirmed + forgotten, never skipped; `clearAll` test; all-domain scope stated. |
| R9P-2 (withdrawn slot still cited by siblings) | L1a-2 §3/§4 and L1a-1 §5 R4 edited to drop U6/P2/P3 references. |

Rounds on this lineage: R8 (v1, slot design, needs-changes) and R9 (v2, merge design, converged). Earlier rounds on these units ran inside L1a-2 (R3–R7).

## 5. Round-8 dispositions
| Finding | Disposition |
|---|---|
| R8P-1, R8P-2, R8P-3 (slot wrapper, wedge, starvation) | Withdrawn with the slot/timeout design: no slot, no wrapper, no timeouts, no call-site changes. |
| R8P-4 (`:2661` behaviour change) | Moot: no call site changes. |
| R8P-5 (ledger wording for half (a)) | §3: no ledger row; points to L1a-2 §5/§10. |
