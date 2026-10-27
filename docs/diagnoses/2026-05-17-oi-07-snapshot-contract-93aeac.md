---
bug_id: 93aeac
date: 2026-05-17
batch: audit-2026-05-17 OI-07 closure (snapshot contract manifest)
status: fixed
symptom: |
  `AiCoachRepository.buildAiContext()` emits ~48 keys into a JSON blob.
  13 Edge Functions consume it via two paths: (A) ai-proxy /
  ai-media-proxy stringify the whole blob into the Gemini system prompt;
  (B) `daily-snapshot` persists it into
  `user_daily_snapshots.snapshot_json`, and 11 cron-driven functions
  read INDIVIDUAL fields off that column. No test or document pins
  which fields each function reads. The F3-1.1
  (`coach_notes` vs `coaching_notes` rename, 2026-05-16) bug was an
  instance of this cross-system writer/reader drift class — silent for
  10+ days until founder observation surfaced it.
concept: ai_snapshot_building
sot_registry_entry: ai_snapshot_building
writers:
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: buildAiContext, line: 34 }
readers:
  - { file: supabase/functions/ai-proxy/index.ts, method: prompt_passthrough, line: 716 }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: prompt_passthrough, line: 488 }
  - { file: supabase/functions/morning-alert/index.ts, method: generateDataDrivenAlert, line: 32 }
  - { file: supabase/functions/morning-alert/index.ts, method: generateFreeAlert, line: 112 }
  - { file: supabase/functions/streak-guardian/index.ts, method: processUser, line: 150 }
  - { file: supabase/functions/protein-gap-alert/index.ts, method: processUser, line: 174 }
  - { file: supabase/functions/workout-window-closing/index.ts, method: processUser, line: 196 }
  - { file: supabase/functions/expiry-reminder/index.ts, method: processUser, line: 79 }
  - { file: supabase/functions/weekly-recap-ready/index.ts, method: processUser, line: 52 }
  - { file: supabase/functions/future-prediction/index.ts, method: handler, line: 257 }
  - { file: supabase/functions/beat-my-coach/index.ts, method: handler, line: 176 }
  - { file: supabase/functions/rolling-context/index.ts, method: handler, line: 256 }
  - { file: supabase/functions/daily-snapshot/index.ts, method: handler, line: 284 }
hive_key_prefix: "n/a — snapshot is a JSON blob, not a Hive key prefix"
hive_key_formula: "n/a — snapshot is a Map<String, dynamic> returned by buildAiContext"
sync_methods: [pushSnapshot]
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [user_id, snapshot_date, snapshot_json, created_at]
contract_test_path: test/contracts/snapshot_contract_self_consistency_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — snapshot is built per-call from already user-scoped Hive boxes; no shared state to guard"
forbidden_patterns_checked:
  - { pattern: "snapshot key emitted but missing from manifest", absent: true }
  - { pattern: "manifest reader cited but file:line does not resolve", absent: true }
proposed_fix: |
  Build `docs/snapshot_contract.yaml` — the explicit manifest of every
  field emitted by buildAiContext + every Edge Function reader. Two
  consumption paths are documented:

  (A) prompt_passthrough — ai-proxy + ai-media-proxy JSON.stringify the
      whole blob into the Gemini system prompt. They do NOT read
      individual fields. Every key is implicitly consumed by both
      (recorded once as `prompt_passthrough_consumers`).

  (B) Per-key reads off `user_daily_snapshots.snapshot_json`. 11 cron
      functions read individual fields. These per-key reads are the
      only contract that risks silent drift; they are enumerated as
      `readers: [...]` on each key.

  Three categories enumerated:
    - `keys:` — 48 entries emitted by buildAiContext.
    - `extra_server_written_keys:` — 4 keys written by OTHER Edge
      Functions into snapshot_json (fitness_summary, future_prediction,
      beat_my_coach, morning_alert).
    - `orphan_readers:` — 11 keys READ by cron functions but NOT
      emitted by today's buildAiContext (debt list:
      `current_streak_weeks`, `current_streak_days`, `today_workout_name`,
      `total_workouts_done`, `recent_pr_exercise`, `recent_pr_weight`,
      `current_weight_kg`, `target_weight_kg`, `yesterday_calories`,
      `daily_calorie_target`, `daily_targets.protein`).

  Self-consistency pinned by
  `test/contracts/snapshot_contract_self_consistency_test.dart` (5
  tests): every key entry has reader-coverage signal; every file:line
  resolves; summary stats present; orphan_readers enumerates drift
  classes.

  Every reader citation was MANUALLY verified by reading the actual
  Edge Function code at the cited line per
  `feedback_audit_findings_require_live_verification.md`.

  The GATE that enforces this manifest against live source is OI-03
  (separate batch). This batch builds only the manifest.
regression_test_planned:
  - test/contracts/snapshot_contract_self_consistency_test.dart
---
# Body

## Symptom

`AiCoachRepository.buildAiContext()` is the canonical builder for the
JSON snapshot sent with every AI coach turn and persisted to
`user_daily_snapshots.snapshot_json` for cron functions. It emits ~48
top-level keys (verified via direct grep of `'<key>':` patterns in the
return Map at lines 46-187 of `ai_coach_repository.dart`).

13 Edge Functions consume the snapshot. Two distinct consumption paths
exist:

1. **prompt_passthrough**: `ai-proxy` (line 716) and `ai-media-proxy`
   (line 488) `JSON.stringify` the whole blob into the Gemini system
   prompt. They never read individual fields.

2. **per-key reads**: 11 cron functions read specific fields off the
   persisted `snapshot_json` column. These are the drift-prone reads.

Today, no test or document pins the contract. The 9th instance of the
writer/reader drift bug class — `coach_memory.coach_notes` upward sync
(F3-1.1, fixed 2026-05-16) — was a member of this exact class.

## Investigation

Two parallel greps:

- **Writer side**: read `ai_coach_repository.dart` start to finish,
  enumerated every `'<key>':` emitted into the return Map of
  `buildAiContext`, plus the spread-operator helpers
  (`_computeDataWindowGrounding`, `_getInductionAndMusterKeys`).
  Result: 48 top-level keys.

- **Reader side**: grep `snapshot[._]`, `snap[._?\[]`,
  `snapshot_json\.` across all `supabase/functions/*/index.ts`. Found
  13 functions touching the snapshot. Manually verified each cited
  line:
  - ai-proxy: opaque passthrough (line 716)
  - ai-media-proxy: opaque passthrough (line 488)
  - daily-snapshot: writer (persists `snapshot_json` to table)
  - rolling-context: writes `fitness_summary` into snapshot_json
  - morning-alert: reads 11 top-level fields off `snap.*` (lines
    32, 112-121)
  - streak-guardian: reads 5 top-level fields (lines 150-153) +
    notification_preferences (line 132)
  - protein-gap-alert: reads daily_targets + notification_preferences
    (lines 174, 197)
  - workout-window-closing: notification_preferences only (line 196)
  - expiry-reminder: notification_preferences only (line 79)
  - weekly-recap-ready: notification_preferences only (line 52)
  - future-prediction: self-read `future_prediction` (line 257)
  - beat-my-coach: self-read `beat_my_coach` (line 176)
  - weekly-report: only reads snapshot.id for FK (line 511; not a
    per-field read; excluded from per-key contract).

**Key finding**: 11 of the per-key reads in morning-alert /
streak-guardian / protein-gap-alert reference fields NOT emitted by
`buildAiContext`:

| Reader expectation                | Writer reality                              |
|-----------------------------------|---------------------------------------------|
| `snap.current_streak_weeks`       | `snapshot.progress.current_streak_weeks`    |
| `snap.current_streak_days`        | NOT EMITTED (reader falls back to weeks*7)  |
| `snap.today_workout_name`         | `snapshot.today_workout.type`               |
| `snap.total_workouts_done`        | `snapshot.progress.total_workouts_done`     |
| `snap.recent_pr_exercise`         | `snapshot.pr_timeline_summary.recent_prs[0]`|
| `snap.recent_pr_weight`           | same nested path                            |
| `snap.current_weight_kg`          | `snapshot.profile.current_weight_kg`        |
| `snap.target_weight_kg`           | `snapshot.profile.target_weight_kg`         |
| `snap.yesterday_calories`         | NOT EMITTED                                 |
| `snap.daily_calorie_target`       | NOT EMITTED                                 |
| `snap.daily_targets.protein`      | NOT EMITTED (reader explicitly notes this)  |

These are documented under `orphan_readers:` in the manifest so OI-03's
gate can warn (not fail) on them — they're known debt for the
next-batch remediation, not gate violations.

Also documented under `extra_server_written_keys:` are 4 keys that are
WRITTEN by other Edge Functions into `snapshot_json` (not by
buildAiContext) but ARE read off the same column:
`notification_preferences`, `fitness_summary`, `future_prediction`,
`beat_my_coach`.

## Fix

Created `docs/snapshot_contract.yaml` (530 lines) with three sections:
- `keys:` — 48 emitted keys with writer_line + reader/passthrough flag
- `extra_server_written_keys:` — 4 server-written keys
- `orphan_readers:` — 11 documented drift entries

Pinned by `test/contracts/snapshot_contract_self_consistency_test.dart`
(5 tests):
1. writer block points at AiCoachRepository.buildAiContext
2. every keys: entry has at least one of {readers, prompt_passthrough,
   intentionally_orphan}
3. every file:line citation resolves to a valid file + line range
4. summary stats present
5. orphan_readers enumerates drift_class entries

OI-07 in `docs/audit/open_issues.md` marked CLOSED.

## Verification

- Manifest contains 48 `- key:` entries (matches buildAiContext emit
  count from grep).
- All reader citations cross-referenced against actual file:line in
  `supabase/functions/*/index.ts` (per
  `feedback_audit_findings_require_live_verification.md`).
- Self-consistency test asserts the writer file matches the canonical
  AiCoachRepository and every file:line resolves.

## Follow-ups (next batches)

- **OI-03** — build `scripts/check_snapshot_contract.dart` that source-
  greps both sides and fails on any drift NOT documented in this
  manifest.
- **orphan_readers cleanup** — 11 entries to either fix on writer
  (emit top-level aliases) or remove on reader. Largest contributor
  is morning-alert milestone-template path; safest first step is to
  emit aliases.
- **notification_preferences writer** — 5 cron functions read this
  key but no current writer path emits it. Likely a debt from a
  retired path; needs re-introduction or read-side cleanup.
