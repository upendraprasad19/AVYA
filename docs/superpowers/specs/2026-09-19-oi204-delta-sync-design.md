# OI-204 Delta-Sync Design — Fingerprint-Skip for Exercise Logs + Nutrition Logs

> **For agentic workers:** this spec is the input to `superpowers:writing-plans`. Read this in full
> before drafting the implementation plan; do not re-derive facts already verified here without
> checking whether they've since drifted (grep the cited file:line first).

**Status:** approved by founder 2026-09-19 (batch scope confirmed: single batch, both domains).
**Blast radius:** platform (touches `sync_fanout_workout_domain` + `sync_fanout_nutrition_domain`,
the most heavily-guarded subsystem in the repo — writer/reader drift is its single most recurrent
bug class). Full §4.12 ×2 context-blind plan review required, not ship-dark tiering (see
"Rollout posture" below).

## 1. Problem

**OI-204** (`docs/audit/open_issues.md:4432-4485`, filed 2026-09-16): `_syncExerciseLogs`
(`lib/core/services/sync/sync_workout.dart:185-418`) and `_syncNutritionLogs`
(`lib/core/services/sync/sync_nutrition.dart:201-463`) are the COALESCED, per-write
fire-and-forget sync entries fired after every `WorkoutWriteService.logExercise` /
`NutritionWriteService.logMeal`. Both iterate **every** Hive row of their domain
(`exlog_*` / `nlog_*` prefix) on **every** call — not just what changed since the last
successful sync — and `await` a network upsert per row/slot, sequentially. As the founder's
historical log count has grown, each coalesced pass now routinely takes 14-40s even on
success, tripping `SyncService.restoreOpTimeout = Duration(seconds: 45)`
(`sync_service.dart:2204`, diagnose `b7e4c1`) — a ceiling deliberately generous, meant to
unstick a genuinely WEDGED call, not act as a normal-case latency budget. Verified via
`client_errors` telemetry: 34× `sync_exercise_logs` timeouts + 11× `sync_nutrition_logs`
timeouts in one 25h window on the founder's account (2026-09-14→16), still ongoing as of
filing.

## 2. Goals / non-goals

**Goals:**
- Stop pushing rows to the network that cloud already has, byte-for-byte, from the last
  confirmed-successful push.
- Never silently under-sync: any row that changed (created, edited) since its last confirmed
  push MUST be detected and re-pushed on the very next coalesced pass.
- No new Hive fields on the log rows themselves — bookkeeping lives in a separate, dedicated
  Hive key per domain (mirrors the existing pattern; keeps `docs/architecture/sync.md`'s
  Hive field-name contract for `exlog_*`/`nlog_*` rows unchanged).
- Reuse the exact fingerprinting primitive already in production for a sibling domain
  (`_deterministicId`, i.e. UUID v5 over sorted-key JSON) — no new hashing scheme.

**Non-goals (explicitly out of scope for this batch):**
- Reducing the FIRST-sync cost on a fresh device/reinstall (every row is new by definition;
  no stored fingerprint exists yet, so the first pass after a fresh install is still a full
  push — unavoidable, and unrelated to OI-204's symptom, which is about *repeated* re-pushes
  on an established device).
- Any change to the restore/pull side (`_restoreExerciseLogs`, `_restoreNutritionLogs`) —
  this batch is push-side only.
- Raising or otherwise touching `restoreOpTimeout` itself — the timeout is correctly generous
  for its actual purpose (catching a wedged call); this batch removes the reason it's being
  tripped routinely, it doesn't adjust the ceiling.
- Per-item-level skip within a nutrition slot that DID change (see §4.2 — a changed slot
  always re-sends its full item list; this is correct/required, not a missed optimization,
  because `nutrition_log_items` sync is a full slot upsert-by-position).

## 3. Prior art (verified by direct read, not summary)

`_syncScheduledWorkouts` (`sync_workout.dart:1500-1782`) already solves this exact class of
problem for its own domain, shipped 2026-06-27 as "H1b Part A"
(diagnose `2026-06-27-sched-dirty-filter-b4f7e2.md`), registered as its own SoT concept
`sync_scheduled_payload_hash_index` (`docs/sot_registry.yaml:2014-2058`):

- **Fingerprint:** `SyncService.schedPayloadFingerprint(payload)` (`sync_service.dart:315-324`)
  — sorts payload keys, `jsonEncode`, then `_deterministicId(...)` (`sync_service.dart:561-563`
  = `_uuidGen.v5(_syncNamespace, localKey)`, UUID v5/sha1-based, stable across VMs/sessions —
  NOT `String.hashCode`).
- **Skip decision:** `SyncService.schedShouldSkipUpsert({killSwitchDisabled, status,
  storedFingerprint, currentFingerprint})` (`sync_service.dart:333-343`) — pure, static.
- **Index:** one Hive key `_schedHashIndexKey = 'sync_sched_payload_hash_index'`
  (`sync_service.dart:293`, in `workoutBox`), `Map<String,String>` (date → fingerprint).
  Loaded once per call, mutated in-memory, **persisted store-ON-200-ONLY**, **pruned to
  still-present keys** after the loop (`schedPrunedHashIndex`, `sync_service.dart:349-355`,
  pure, `@visibleForTesting`).
- **Kill-switch:** `configBox.get('disable_sched_hash_skip') == true` — reverts to the
  verbatim pre-H1b unconditional sweep.
- **Test template:** `test/contracts/sync_scheduled_payload_hash_index_writer_to_reader_test.dart`
  (266 lines, 6 groups) — fingerprint stability + field-sensitivity (incl. key-set changes),
  skip-decision semantics, prune-drops-dead-keeps-live, exact fingerprint-write call-site
  COUNT via comment-stripped regex, source-guard grep (sim reset clears the index), a real
  Hive round-trip.

This design extends that exact pattern to two new domains rather than inventing a new
mechanism.

## 4. Rejected alternatives

**B — Pure performance fix (parallelize the per-row calls and/or raise the timeout).**
Rejected: treats the symptom, not the cause. The app would still push the entire historical
log to the network on every write, forever, growing worse as history grows — it would just
fail less visibly (or burn more data/battery on concurrent calls against a mobile connection,
which risks worse contention, not better).

**C — Timestamp-cursor delta sync (`updated_at >= last_synced`).** Rejected on direct
precedent, not speculation: the SAME 2026-06-27 batch that built the pattern in §3 explicitly
considered and rejected this shape for the sibling domain. Per
`docs/diagnoses/2026-06-27-sync-debounce-cost-h1a-c4f8d2.md`'s "Review (rejected)" section:
*"Delta-sync (since→last_synced) — REJECTED: the Step-B pulls page on creation/event columns,
not a mutation timestamp → drops late edits/completions."* Exercise/nutrition log rows only
carry creation-ish timestamps (`_resolveCompletedAt`'s 7-branch fallback chain,
`sync_workout.dart:439-482`) and neither domain bumps any timestamp field on edit today
(confirmed — see §5.3). A cursor design would silently drop a row edited after the cursor
passed it, re-opening the exact hole this codebase already closed once. The fingerprint
approach (§3, adopted here) does not have this failure mode: it re-walks every row locally
every pass (cheap — local Hive iteration was never the expensive part) and only skips the
*network call*, computing a fresh content fingerprint each time, so an edit is caught on the
very next pass regardless of any timestamp field.

## 5. Detailed design

### 5.1 Exercise logs (`_syncExerciseLogs`, `sync_workout.dart:185-418`)

**New primitives** (static, pure, on `SyncService`, alongside the `sched*` family):

```dart
static const String _exlogHashIndexKey = 'sync_exlog_payload_hash_index'; // in workoutBox

bool get _exlogHashSkipDisabled {
  try {
    return _hive.configBox.get('disable_exlog_hash_skip') == true;
  } catch (_) {
    return false;
  }
}

/// Fingerprint of the FULL per-key push bundle: the summary row payload plus
/// its ordered per-set rows (sorted-key JSON, each map's keys sorted, then
/// the whole structure through `_deterministicId`). Any change to either
/// half flips the fingerprint. Pure; extracted for behavioral coverage.
static String exlogPayloadFingerprint(
  Map<String, dynamic> summary,
  List<Map<String, dynamic>> sets,
) {
  Map<String, dynamic> sortKeys(Map<String, dynamic> m) =>
      <String, dynamic>{for (final k in m.keys.toList()..sort()) k: m[k]};
  final combined = {
    'summary': sortKeys(summary),
    'sets': sets.map(sortKeys).toList(),
  };
  return _deterministicId(jsonEncode(combined));
}

/// No status-based carve-out (unlike `schedShouldSkipUpsert`) — deliberate,
/// not an oversight. Exercise-log rows have no server-side out-of-band
/// mutator (verified: grepped all of `supabase/functions/` for writes to
/// `workout_log_exercises`/`workout_log_sets` — zero) and every edit path
/// rewrites the SAME Hive key in place (`WorkoutWriteService.editLog`,
/// `workout_write_service.dart:911+`, takes the existing `logKey` and
/// `box.put`s back under it) — so any edit changes the fingerprint on its
/// own, with no need for a forced-repush class. Pure, static.
static bool exlogShouldSkipUpsert({
  required bool killSwitchDisabled,
  required String? storedFingerprint,
  required String currentFingerprint,
}) {
  if (killSwitchDisabled) return false;
  return storedFingerprint != null && storedFingerprint == currentFingerprint;
}

@visibleForTesting
static Map<String, String> exlogPrunedHashIndex(
    Map<String, String> index, Set<String> liveKeys) {
  return <String, String>{
    for (final e in index.entries)
      if (liveKeys.contains(e.key)) e.key: e.value,
  };
}
```

**Loop integration.** After the existing null-key guard (`sync_workout.dart:264-271`, which
already `continue`s before any network call — unaffected) and after `resolvedSets` /
`completedAt` / clamped fields are resolved: build the summary payload map (the exact literal
already passed to `.upsert()` at :287-308) and the `rows` list (the exact literal built for
the per-set upsert at :374-385, or `[]` if `resolvedSets` is empty), compute
`exlogPayloadFingerprint(summaryPayload, rows)`, and check
`exlogShouldSkipUpsert(killSwitchDisabled: _exlogHashSkipDisabled, storedFingerprint:
exlogHashIndex[key], currentFingerprint: fp)`. Skip → `continue` (both the summary AND the
per-set upsert are skipped as one unit for this key).

**Store-on-full-success-only — the atomicity requirement.** Verified by reading the current
control flow precisely: the summary upsert (:287-308) is **not** in its own try/catch — an
exception there propagates to the OUTER catch (:408), so the per-set section never runs and
the fingerprint is correctly never stored (unreachable). The per-set batch upsert (:388-395)
**is** in its own inner try/catch that logs telemetry and does **not** rethrow — so the outer
try reaches its end even when the per-set send failed. A naive "store fingerprint at the end
of the try block" would therefore wrongly mark a key as fully-synced when its per-set rows
silently failed, permanently skipping the retry that today happens automatically (since today
this domain has no skip logic, every failed row gets a fresh, un-skippable attempt next pass).
**Required:** a local `bool exlogBundleSynced = true;` declared at the top of the per-key
try block, set to `false` inside the per-set catch block (:396-405), and the fingerprint-store
line gated `if (exlogBundleSynced) { exlogHashIndex[key] = fp; }`, placed as the last
statement of the try block (after the per-set section, before the closing brace — never
inside any catch).

**Prune.** After the loop: `exlogHashIndex = exlogPrunedHashIndex(exlogHashIndex,
workoutBox.keys.whereType<String>().where((k) => k.startsWith('exlog_')).toSet())`, then
persist to `_exlogHashIndexKey` — mirrors the scheduled_workouts store-back, gated the same
way (`if (!_exlogHashSkipDisabled) { ... }` so the kill-switch leaves the box verbatim).

### 5.2 Nutrition logs (`_syncNutritionLogs`, `sync_nutrition.dart:201-463`)

**New primitives**, same shape as §5.1 (naming `nlog*`, index key
`sync_nlog_payload_hash_index` in `nutritionBox`, kill-switch
`disable_nlog_hash_skip`). `nlogPayloadFingerprint(parentPayload, items)` fingerprints the
resolved `parentPayload` map (the exact literal built at :277-295) plus the slot's `items`
list (from `log['items']`) — same sorted-key-JSON approach.

**Slot keying.** The fingerprint index is keyed by **slot id** (`'$date $mealType'`), not by
raw Hive key — because `_syncNutritionLogs` already merges same-slot logs into one payload
before pushing (`mergeEnabled` branch, :210-214, the NUT-02 fix) and the natural unit that
maps 1:1 to what's actually sent to cloud is the slot, exactly mirroring how
`schedPayloadFingerprint`'s natural unit is a schedule *date*, not a raw Hive key.

**Interaction with the existing `disable_nutrition_slot_merge` kill-switch.** When
slot-merge is disabled, `_syncNutritionLogs` reverts to the legacy per-raw-key push path
(`_nutritionLogsRaw()`, unmerged — multiple raw keys can share one slot, later ones
overwriting earlier ones in cloud, the pre-NUT-02-fix behavior kept only as an emergency
revert). **The new hash-skip is inert whenever `disable_nutrition_slot_merge` is set**
(falls through to always-push, same as if `disable_nlog_hash_skip` were also set) — the
legacy path predates the slot concept the fingerprint is keyed on, and it's already a rare
emergency-revert path not worth extending. This is a deliberate scope decision, not a gap.

**Loop integration.** After the existing null-natural-key guard (:235-247) and the
`ownerChangedSince` guard (:314, unrelated existing cross-account safety check — left
untouched), compute the fingerprint and skip-check exactly as in §5.1; skip → `continue`.
Skipping this early means the id-resolution SELECT (:330-345), every item upsert (:356-429),
and the tail-vacuum DELETE (:436-452) are **all** skipped for an unchanged slot — this is the
single biggest win of the batch, since nutrition's per-slot cost (1 upsert + 1 SELECT + N item
upserts + 1 DELETE, all sequential) is the worse of the two domains.

**Store-on-full-success-only.** Same hazard as §5.1, worse here because there are TWO
swallowing catch sites, not one: the per-item catch (:419-427, inside the `for` loop over
`items`) and the tail-vacuum catch (:447-451) both log telemetry without rethrowing. The
parent upsert (:320-323) is NOT in its own try/catch (exception propagates to the outer catch
at :453, so it's already correctly all-or-nothing with everything after it). The id-resolution
SELECT already has its own `continue`-on-failure (:346-348) which correctly prevents reaching
the store line. **Required:** a local `bool nlogSlotSynced = true;` declared at the top of the
per-slot try block, set `false` in BOTH the item catch (:419-427) and the vacuum catch
(:447-451), fingerprint-store gated `if (nlogSlotSynced) { nlogHashIndex[slotId] = fp; }` as
the last statement of the try block.

**Prune.** Live-slot set is derived from `logsToSync` itself (the merged-by-slot list already
computed this pass): `logsToSync.map((l) => '${l['date']} ${l['meal_type']}').toSet()` —
this is exactly the live-slot set at call time, no extra Hive scan needed. Skipped entirely
(index left untouched) when `disable_nutrition_slot_merge` is set, per the interaction rule
above.

### 5.3 Edit-path verification (why no forced-repush carve-out is needed)

Verified directly, not assumed:
- `WorkoutWriteService.editLog` (`workout_write_service.dart:911+`) takes the existing
  `logKey` as a required param, `box.get(logKey)` → mutate → `box.put(logKey, ...)` — same
  key, in place.
- `NutritionWriteService.editLog` (`nutrition_write_service.dart:292-341`) and `deleteLog`
  (:362+) — same pattern.
- Neither writes under a new/different key. So a content-based fingerprint naturally and
  correctly flips on any edit — there is no path where a row's content changes but its Hive
  key (or, for nutrition, its slot id) stays the same AND its fingerprint stays the same.
- Server-side out-of-band mutation hazard (the reason `_syncScheduledWorkouts` needs its
  `status == 'completed'` never-skip carve-out, per d9b2c5): grepped all 10
  `supabase/functions/` files that reference `workout_log_exercises` / `workout_log_sets` /
  `nutrition_logs` / `nutrition_log_items` for `.update(`/`.upsert(`/`.insert(` — **zero
  writes** to any of the four tables (all are readers: `pr-detection`, `future-prediction`,
  `weekly-report`, `weekly-recalc`, `restore-user-snapshot`, `i-see-you-callout`, the
  `_shared/tools/progress/*` trio, `getNutritionHistory.ts`). Three migrations
  (`057_schema_unique_indexes_h25_h26_h27_h28.sql`, `064_fix_partial_unique_arbiter.sql`,
  `083_nutrition_sync_natural_keys.sql`) contain historical one-shot mutations on these
  tables — 057's are `DELETE`s (a one-shot dedup before creating unique indexes on
  `nutrition_logs`/`workout_log_exercises`), 064/083 are `UPDATE`s — all three
  already-applied schema-change backfills, not a recurring process. A DELETE with a
  surviving stale fingerprint is the same hazard class as the UPDATE case below (row never
  re-created), so the conclusion is unchanged; named here because an earlier count of two
  missed it. **Conditional risk flagged, not a current defect:** a
  *future* one-shot repair migration on these tables, landing after this index exists, would
  leave a stale fingerprint pointing at a pre-repair payload and skip re-pushing the
  (unchanged-locally) row — the same shape as d9b2c5, just not observed to have ever happened
  here. No carve-out is warranted today; a future repair migration should clear the relevant
  index entries as part of its own rollout, the same way `resetJourney` already clears
  `_schedHashIndexKey` on a full account reset.

### 5.4 Safety net — fingerprint computation itself must never cause a silent skip

If either fingerprint function throws (a malformed/legacy Hive row shape) or a stored index
value is corrupt, treat it as "no confirmed match" — fall through to a normal push, never to
a skip. Concretely: wrap the fingerprint computation + lookup in a try/catch at the call site
that defaults `currentFingerprint`'s lookup-comparison to "always push" on any exception,
mirroring `_schedHashSkipDisabled`'s own defensive-read pattern (`sync_service.dart:298-304`,
`try { ... } catch (_) { return false; }`).

## 6. §4.11 gate-before-refactor

Per CLAUDE.md §4.11, the regression-detection gate lands in an **earlier commit** than the
sync-loop changes themselves. The dangerous failure mode identified in §5.1/§5.2 is
mechanical and checkable: **a fingerprint must never be stored unless every constituent
network write for that key/slot succeeded.**

`scripts/check_sync_hash_skip_atomicity.dart` (new gate; no number — filename is the
identity per rule 24): source-greps `sync_workout.dart` and `sync_nutrition.dart`
(comment-stripped) and asserts, per domain:
1. The success-flag variable (`exlogBundleSynced` / `nlogSlotSynced`) is declared `= true`
   before the first write attempt in its function.
2. **What the gate actually checks, stated precisely (corrected by plan-review round 1,
   finding I4 — the original wording overclaimed this):** it counts occurrences of
   `<flagName> = false;` in the source and compares that count against a hardcoded expected
   value per domain (exlog: 1 — the per-set catch; nlog: 2 — item catch + vacuum catch), the
   same "exactly N call sites" style `sync_scheduled_payload_hash_index_writer_to_reader_test.dart`
   already uses for `schedHashIndex[date] = schedFp(...)` (count 3). **This can only detect a
   changed count, never verify "every catch block between declaration and function boundary"
   structurally** — a *new* swallowing catch that forgets to set the flag false leaves the
   count exactly where it was, which the gate cannot distinguish from "nothing changed,
   still correct". Closing that gap needs real catch-block-boundary analysis, which this
   batch does not implement (the count-comparison is the cheap, mechanically-checkable
   approximation, not a claim of full coverage — say so rather than let the prose claim more
   than the code does).
3. The fingerprint-store assignment (`exlogHashIndex[key] = fp` / `nlogHashIndex[slotId] =
   fp`) is textually nested inside an `if (<thatFlag>)` block.

Since this is a genuinely new mechanism (nothing today violates it, because it doesn't exist
yet), the gate ships **hard-fail from its first commit**, not warn-only-for-24h — §4.11 point
2's baseline period is for gates retrofitted onto an existing codebase with existing
violations to measure; there is nothing to baseline here. Ships mutation-proven per rule 24
(a test that removes the `if (flag)` guard, or removes one of the `flag = false` sets, must
redden).

## 7. SoT registry + documentation

Two new concepts in `docs/sot_registry.yaml`, mirroring `sync_scheduled_payload_hash_index`'s
exact shape (description, writers, readers, hive, cloud, sync_methods, regression_test,
behavioral_test_path, class_constraints):
- `sync_exercise_log_payload_hash_index` — sole writer+reader `_syncExerciseLogs`.
- `sync_nutrition_log_payload_hash_index` — sole writer+reader `_syncNutritionLogs`.

`docs/architecture/sync.md` gets a new subsection ("Sync fingerprint-skip pattern") — verified
absent today (grepped the whole file for "fingerprint"/"hash"/"H1b": zero matches) despite the
pattern being in production since 2026-06-27. This closes that documentation gap for all
three instances (scheduled_workouts + the two new ones), not just the new work.

`lib/core/services/CLAUDE.md`'s SoT mapping table gets two new rows alongside the existing
`sync_fanout_workout_domain` / `sync_fanout_nutrition_domain` entries.

## 8. Testing

Per domain, mirror the 6-group template from
`sync_scheduled_payload_hash_index_writer_to_reader_test.dart`:
1. Fingerprint stability + field-sensitivity (same payload → same fingerprint; any field
   change, including a key appearing/disappearing, flips it).
2. Skip-decision semantics: matching fingerprint → skip; null stored fingerprint (never
   pushed) → always push; kill-switch enabled → always push. (No status-carve-out group,
   per §5.1/§5.2's deliberate simplification.)
3. Prune: drops entries for keys/slots no longer present, keeps live ones with fingerprint
   intact.
4. Exact fingerprint-write call-site count (1 per domain — no branching recovery paths).
5. Real Hive `Box` round-trip (put → get → drives the skip decision correctly through the
   dynamic-typed Map Hive returns).
6. **New for this batch, not in the template:** an edited row (same key, changed content) is
   never wrongly skipped — this is the mutation-style regression test for the exact hazard
   §3/§4-C exists to avoid.

Plus one behavioral test per domain proving the atomicity requirement from §5.1/§5.2: a
simulated per-set (or per-item/vacuum) failure must leave NO fingerprint stored for that
key/slot, so the next pass retries it — this is what the §6 gate checks statically; this test
proves it dynamically.

`test/contracts/sync_fanout_contract_test.dart` requires no changes — it only asserts helper
NAMES appear in the fan-out body (verified by direct read), and this batch doesn't rename or
remove `_syncExerciseLogs`/`_syncNutritionLogs`.

## 9. Rollout posture

Ships with the skip **enabled by default** (kill-switches as the revert path), matching the
H1b convention (`disable_sched_hash_skip` reverts to old behavior; new behavior is not itself
behind a default-off flag). This is a live production bug actively degrading the founder's
account today — there is no "default OFF, flip later" case to make. Full §4.12 ×2
context-blind review applies (not the §4.12.4 ship-dark tier, which requires default-OFF +
byte-identical-when-off, neither of which applies here).

## 10. Open items for the implementation plan

- Exact commit sequencing: §6 gate commit → exlog commit → nlog commit → docs/SoT commit, or
  some consolidation — writing-plans' call, following §4.12.7 (execution mode decided at
  batch start).
- Whether exlog and nlog land as two separate tasks/commits or one — both are small,
  independent, zero file overlap; likely two tasks under one plan.
