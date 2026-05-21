---
name: writer-reader-drift-detector
description: Apply this skill when a symptom suggests Hive/Postgres state was written but isn't being read correctly (or vice-versa). Codifies the 9-instance recurring bug class. Self-evolving.
type: process
priority: high
self-evolving: true
---

# Writer/Reader Drift Detector — ICANBEFITTER

> Project-local skill. The most recurring bug class on this codebase as of B5 of audit 2026-05-20 — **9 instances** documented in `feedback_writer_reader_field_drift_recurring.md`. Every batch since Test #6 has surfaced one.

---

## 0. When to invoke

Trigger phrases from the founder (any of these → invoke):
- "shows old value"
- "isn't updating"
- "stale after restart"
- "writes but doesn't read"
- "saved but lost"
- "logged but missing"
- "X was supposed to be Y"
- "data didn't persist"
- "shows in one place but not another"
- "phone 1 sees X, phone 2 sees Y" (cross-device drift)

Trigger contexts:
- Hive read returns null / wrong field after a known write
- Cloud row exists but UI shows nothing (or stale)
- Restore on second device omits a field that was visible pre-restart
- "Today" row appears but data is yesterday's
- Tab card empty after a write that should have populated it

---

## 1. Methodology — five-step writer/reader map

### Step 1 — Capture the bug shape (NO HALLUCINATION)

Before touching any code, write down (in your response, or a scratch file):
- **Symptom path**: which screen, which field, what the founder expected vs saw
- **Reproduce conditions**: cold-start vs hot, free vs PRO, signed-in user, IST time, day-of-week
- **Suspected concept**: what SoT registry concept might be involved (`exercise_log_keys`, `workout_schedule`, `profile.full_name`, etc.)

DO NOT guess at root cause yet. Drift bugs almost always look obvious and almost always turn out to be the OTHER side of the contract.

### Step 2 — Identify writer(s) by file:line

```
grep -rn "<box-name>.put(.*<concept>" lib/
grep -rn "<box-name>\['<key-pattern>'\] = " lib/
```

For Hive: search for every `box.put(key, value)` writing to the concept's Hive key family. For Postgres: every `.from('<table>').insert/upsert/update`.

Output:
```
Writer:  lib/path/file.dart:LINE  function/method name  ← writes key 'X_{date}'
Writer:  lib/path/file.dart:LINE  function/method name  ← writes key 'X_{date}_v2' (DRIFT?)
Cloud writer: supabase/functions/<fn>/index.ts:LINE
```

If more than one writer for the same concept, you've ALREADY found half the bug. Per `feedback_source_of_truth_audit.md` — patching only the reader (or only the writer) is the recurring anti-pattern.

### Step 3 — Identify reader(s) by file:line

```
grep -rn "<box-name>.get(.*<concept>" lib/
grep -rn "<box-name>\['<key-pattern>'\]" lib/
```

For every reader, note:
- **Key formula used** — is it `'X_$dateKey'`, `'X_${user}_$dateKey'`, `'X_$dateKeyIST'`, etc.?
- **Field-name** within the value — `caloriesPer100g` vs `calories_per_100g` vs `kcal`?
- **Type expectation** — `int` vs `double` vs `String`?

```
Reader:  lib/path/file.dart:LINE  ← reads key 'X_{date}', expects field 'calories_per_100g'
Reader:  lib/path/file.dart:LINE  ← reads key 'X_{date}_v2', expects field 'caloriesPer100g'
```

### Step 4 — Compare writer × reader matrix

Build a literal 3-column table:

| Aspect | Writer side | Reader side | Match? |
|---|---|---|---|
| Hive box | `customBox` | `userBox` | ❌ |
| Key formula | `'workout_$dateKey_${user.id}'` | `'workout_$dateKey'` | ❌ |
| Field name | `caloriesPer100g` | `calories_per_100g` | ❌ |
| Field type | `double` | `int?` | ❌ |
| Date key generator | `formatDateKey(now)` (local) | `istDateStr(now)` (IST) | ❌ |
| Map shape | nested `{nutrition: {...}}` | flat `{...}` | ❌ |

ANY ❌ is the bug. Most drift bugs are exactly ONE mismatch — fix that, both sides line up.

### Step 5 — Cross-check SoT registry + diagnose history

```
# Is this concept in the SoT registry?
grep -A 20 "<concept>:" docs/sot_registry.yaml

# Does the registry list writers AND readers? Does it match reality?
# If registry contract is correct + reality is broken → fix code to match registry
# If registry is stale → fix registry FIRST, get founder approval, then fix code
```

Then:
```
# Has this drift been fixed before?
grep -l "<concept>" docs/diagnoses/*.md
```

If prior fix exists, READ that diagnose-doc — most drift bugs in this codebase have been fixed at least twice. The 9th instance of `exlog_*` key-formula drift in Test #16.1 cited 7 prior batches.

---

## 2. The 9 documented instances (precedent)

Per `feedback_writer_reader_field_drift_recurring.md`:

1. **Test #6 (2026-05-01)** — Multi-set workout calorie burn double-counting. Writer wrote per-set, reader summed all sets including the count multiplier.
2. **Test #8 (2026-05-03)** — AI snapshot 4 fields silent regression. ai_coach_repository.dart drifted from snapshot_contract.yaml.
3. **Test #12 (2026-05-06)** — Receipt IST integrity. Writer used `formatDateKey(local)`, reader used `istDateStr`.
4. **Test #12.6 (2026-05-07)** — Restore 6/16 keys wrong. `_restoreXxx` keys formula didn't match `_syncXxx` keys formula.
5. **Test #15.3 (2026-05-12)** — Writer/reader drift class batch (6 separate fixes a8f1c2/7c4e1a/a13a01/9e2c1a/8f3d22/6e1b45).
6. **Test #15.4 B2 (2026-05-13)** — muster→profile SoT bridge. Onboarding writer wrote to one location; profile reader read from another.
7. **Test #16 (2026-05-15)** — Swap-picker customBox drift. customBox key formula in writer didn't match reader.
8. **Test #16.1 (2026-05-16)** — 3 rogue `exlog_*` key formulas. Writers in 3 unrelated paths used non-canonical formulas.
9. **Test #16.2 (2026-05-16)** — `logPR` AI coach tool bypass. AI coach tool wrote directly to Hive instead of through WriteService.

---

## 3. The fix recipe

Once writer × reader mismatch is identified:

1. **Decide canonical side** — usually whichever matches the SoT registry. If registry is silent, founder chooses (cite the choice in the diagnose-doc).
2. **Migrate the wrong side** — code change. If Hive keys differ, write a `HiveKeyMigrator` runs-once migration (precedent: `ExlogKeyMigrator v8` in Test #16.1, `UserConfigMigrator v2` in Test #11.1).
3. **Write a BEHAVIORAL contract test** (NOT source-grep — per `feedback_source_grep_false_confidence.md`):
   ```dart
   test('writer X persists field that reader Y can fetch', () async {
     await writerY.write({...});
     final result = await readerX.read(...);
     expect(result.field, equals(expected));
   });
   ```
   File path: `test/contracts/<concept>_behavioral_test.dart`.
4. **Update SoT registry** — add the writer/reader pair under the concept. Set `reader_manifest_complete: true` and list every reader in `readers:`. Add `behavioral_test_path:`.
5. **Add a source-grep CONTRACT test** alongside (catches future regressions to the wrong-formula pattern):
   ```dart
   test('only canonical key formula in use', () {
     final files = Directory('lib').listSync(recursive: true);
     for (final f in files) {
       final source = stripComments(f.readAsStringSync()); // per feedback_source_grep_strip_comments_first.md
       expect(source.contains("'old_key_'"), isFalse,
         reason: '${f.path} still uses old key formula');
     }
   });
   ```
6. **Diagnose-doc** at `docs/diagnoses/<date>-<slug>-<id>.md` with:
   - `recurrence: true` field
   - `related_bugs:` list with all prior diagnose IDs from §2 above
   - `touched_layers_checked:` with at least Hive (tier 2) + Postgres (tier 3-4) + Client code (tier 1) verified

---

## 4. Common pitfalls

- ❌ Patching the reader only — the writer keeps producing wrong data forever
- ❌ Patching the writer only — old Hive rows from the wrong-format writer still exist
- ❌ Assuming "the field name doesn't matter, it's stringly-typed Hive" — readers expect specific shapes
- ❌ Writing a source-grep test only — passes while runtime stays broken (caught Test #16.1 → 9th instance)
- ❌ Not running the HiveKeyMigrator on cold-start for existing users
- ❌ Ignoring the IST vs local-time axis — even when key formula matches, time zone mismatch causes today/tomorrow drift

---

## 5. Verification gates

- `scripts/check_writeservice_only.dart` (Gate 7) — direct Hive writes outside WriteServices
- `scripts/check_reader_manifest_complete.dart` (existing) — every SoT concept lists writers AND readers
- `scripts/check_no_raw_ispro_read.dart` (Gate 34) — example of a concept-specific writer-bypass gate
- `scripts/check_sot_behavioral_test_paths.dart` (Gate 42, lands B5 D2) — every SoT entry has `behavioral_test_path:` or `behavioral_test_required: true`

If a writer/reader drift fix lands, the gate that would have caught it MUST be added in the same batch per CLAUDE.md §4.11.

---

## 6. Anti-patterns surfaced (self-evolving)

### 6.1 "It's just a string typo in the key"
This was wrong every time in the 9 instances. The writer-bypass / formula-drift / IST-shift / field-rename was always somewhere in the producer pipeline. Don't trust "obvious quick fix."

### 6.2 "Source grep test catches it"
Source-grep tests check PRESENCE of strings. They do not catch:
- Writer using one key + reader using another (both strings are present, both pass grep)
- Field-name mismatch within the value (e.g. `kcal` vs `calories`)
- IST vs local time zone in the same date-key formula
- Map-shape drift (nested vs flat)

Behavioral tests catch all of these.

### 6.3 "We have the SoT registry, that's enough"
The SoT registry is a contract; it doesn't enforce itself. A registry entry can drift from reality. Always re-verify file:line citations from the registry before trusting them. Per `feedback_audit_findings_require_live_verification.md`.

---

## Self-evolution

Append a 10th, 11th, Nth instance to §2 when a new drift bug ships. Update §6 with new pitfalls. New skill files when drift bugs cluster around a sub-pattern (e.g. "cron-scoped drift" or "Edge-Function payload drift").

Last evolved: B5 D1 of tech-debt audit 2026-05-20 (initial creation; 9-instance recurrence threshold met).
