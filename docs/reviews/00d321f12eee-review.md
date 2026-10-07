---
reviewed_at: 2026-08-15T21:40:00+05:30
staged_against: 00d321f12eee
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 1
verdict: accepted
---

# Code Review (B-pass) — 00d321f12eee

Branch `sync-e2e`. Blast radius **platform**, so `bpass: accepted` is required by
§4.12.3 but Hermes is not. Fresh context-blind Sonnet reviewer over the staged
diff; all five lenses run.

**No P0 or P1 was found in the staged diff.** One P2, fixed below.

## Finding 1 — P2 — blast_radius_mismatch — FIXED

- **file:line:** `.github/workflows/test.yml:406-414` (the `Run Edge Function
  tests` step, which the diff did NOT touch)
- **claim:** The diff added `--concurrency=1` to the `Run Supabase tests` step
  with the stated principle *"integration suites sharing one cloud account
  cannot run concurrently"* — and left the sibling step in the same job, which
  has the identical property, unpinned.
- **verification (re-run by me, not taken from the reviewer):**

  ```
  grep -n "concurrency" .github/workflows/test.yml
  # -> 17 (the workflow-level GitHub concurrency group), 389 (my new comment),
  #    399 (the flag). Nothing on the edge_functions step.

  grep -n "testEmail\|\.delete()" test/edge_functions/*.dart
  # -> ai_proxy_test.dart:67    email: SupabaseTestHelper.testEmail
  #    pgvector_test.dart:79    email: SupabaseTestHelper.testEmail
  #    pgvector_test.dart:98    client.from('memory_embeddings').delete()...
  #    pgvector_test.dart:110   client.from('memory_embeddings').delete()...
  ```

  Two suites, one QA account, deletes in `setUp`/`tearDown`, default parallel
  concurrency. Same class, same job.
- **fix:** `--concurrency=1` added to that step too.
- **status:** fixed

**Why this one matters more than its severity suggests.** It is the repo's most
recurrent self-inflicted class — fixing the instance and leaving the mirror
(`feedback_mistake_guard_without_its_mirror.md`, 12 instances across 4 sessions).
I had just *written the general principle in a comment* and then applied it to
exactly one of the two places it governs. The rule was never "`test/supabase/`
needs serialising"; it was "integration suites sharing one cloud account cannot
run concurrently", and that is true of every step in this job.

## Lenses that returned clean — what was checked, and what it returned

- **writer_reader_drift** — every asserted cloud column checked against
  `backups/live_schema_columns.json` and against the writer that produces it.
  `workout_logs` carries `workout_name`/`date`/`duration_seconds` and **no**
  `exercise_name`; `weight_logs` carries `weight_kg`/`date`/`notes`;
  `nutrition_log_items` carries `food_name`/`item_index`. Every seeded Hive
  field is read by its writer — including `item['name']` → `food_name`
  (`sync_nutrition.dart:375`) and the `log['type'] != 'weight_log'` filter
  (`sync_health.dart:214`) that T5's seed satisfies.
- **function_exception_swallow** — all three writers swallow per-key to
  telemetry and none of the three forwarders is `_safeRestoreOp`-wrapped, so a
  broken writer produces zero rows rather than an exception; `rows.single` then
  throws `StateError`. The `_ensureSessionOpen()`-returns-null path lands in the
  same place. **No vacuous-pass route found** — which is the property the whole
  change depends on.
- **secrets_in_tree** — grep for credential-shaped literals over all three code
  files returned nothing; every credential is `String.fromEnvironment`.
- **unawaited_no_error_sink** — no `unawaited(` in the new test code; every call
  is awaited.

## Specific checks requested

| check | result |
|---|---|
| `setUpAll` order | Correct. `debugMarkInitializedForTests()` precedes `openForUser`, which reads `migrationBox` through `getBox` (`hive_user_session.dart:295`). |
| double `Hive.close()` in `tearDownAll` | Safe. `closeAll()` closes only the 7 namespaced boxes; the first `Hive.close()` takes the shared ones; `close()` is idempotent. |
| `setUp` clear-list complete | Yes — covers every box any test seeds. `exerciseBox`/`foodBox` correctly left unopened; neither writer touches them. |
| T4's `parent['id']` | Present. `queryTable`'s `.select()` takes no args, so it defaults to `*`. |
| `--concurrency=1` side-effects | Scoped to the one step; no global `concurrency:` in `dart_test.yaml`. |
| consumers of the changed helper | Exactly two live callers of `SupabaseTestHelper.init(` — `sync_service_test.dart:30`, `auth_restore_test.dart:25`. Neither depends on the old raw-`Supabase.initialize` behaviour. |

## Verdict

One P2, fixed in the same batch (§4.2). Nothing outstanding. **verdict: accepted**
