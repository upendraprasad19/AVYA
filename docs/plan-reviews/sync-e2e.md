---
branch: sync-e2e
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
tier: full
blast_radius: platform
reviewed_at: 2026-08-15T21:45:00+05:30
bpass_review: docs/reviews/00d321f12eee-review.md
---

# Plan review record — sync-e2e

Makes `test/supabase/sync_service_test.dart` T3/T4/T5 drive the real production
SyncService writers instead of hand-rolling their own `.upsert()` payloads.
Diagnose-doc: `docs/diagnoses/2026-08-15-sync-tests-reimplemented-the-writer-b6e1d4.md`.

Blast radius **platform** (measured on the staged set, not predicted), so the
×2 review + `bpass: accepted` are required and Hermes is not.

## Review rounds — 2, both context-blind, both before execution

An earlier design (v1) drove `weeklyFullSync()` and went through **three** rounds
that each found a *different* unconditional-failure mechanism. Per §4.12.1 that
is the split/redesign signal, and it was taken: v1 was replaced rather than
patched. The rounds below are on v2, and are what the count refers to.

- **Round 1 (Sonnet) — SOUND, 4×P2.** All four verified by me at file:line
  before acceptance:
  1. *"one writer, one table" was false for nutrition* — `_syncNutritionLogs`
     also writes `nutrition_log_items` (`sync_nutrition.dart:359`), and the slot
     merge always materialises `'items': []` (`:31`). The
     no-`cleanupTables`-extension conclusion survived, but on a basis I had not
     established: `nutrition_log_items.log_id` is `ON DELETE CASCADE`. A right
     answer from a wrong premise is not verification.
  2. *A second consumer of the changed helper was never enumerated* —
     `auth_restore_test.dart:25`. Unaffected, for a specific reason, and re-run
     rather than argued.
  3. *Hive init ordering inverted* — `openForUser` reads `migrationBox` before
     `HiveService` was marked initialised; the resulting `StateError` is
     swallowed.
  4. *The discrimination control was too weak* — reverting to `id` +
     `onConflict:'id'` need not redden a value assertion, since `id` is a valid
     PK column.
- **Round 2 (Opus, on the hardened plan) — UNSOUND, 1×P1 + 5×P2.** Aimed
  deliberately at round 1's corrections, which is where it found things:
  - **P1: `rows.single` was justified by an exclusivity that does not exist.**
    Both files in `test/supabase/` sign in as the same QA account and both
    `DELETE` 12 tables in `setUp`, and CI ran them with the dart runner's
    default parallel suites. One could wipe the other's rows between write and
    read — failing with a *correct* writer. Pre-dates this batch; this batch
    widens the window. Fixed with `--concurrency=1`.
  - **My round-1 ordering fix was correct but I overstated it.** The swallowed
    `StateError` falls through and the migration runs anyway, so behaviour is
    identical in both orders; what actually does the work is the added
    `Hive.openBox('migrationBox')`, because `getBox` ends in `Hive.box(name)`
    and needs the box OPEN, not merely `_initialized`. Order kept, claim dropped.
  - **The T4 discrimination control could not fire the mechanism it named** —
    `mergeNutritionLogsBySlot` builds a fresh map with no `id`, so "reinstate
    the Hive string id" gives `23502`, not `22P02`. It would still have
    reddened, which is exactly why it mattered: a control that reddens for the
    wrong reason still reads as proof.
  - **The override branch's stated rationale was fiction** — `grep -rn
    "init(url:" test/` returns zero. The "loopback wiring test" it was kept for
    does not exist; the claim came from a stale doc comment.

Two rounds, and the second found classes the first did not — but the *design*
never moved across either round, and round 2's P1 is a pre-existing CI-config
bug rather than a defect in the change. That reads as convergence, not as a unit
needing a further split.

## B-pass — `docs/reviews/00d321f12eee-review.md`, verdict accepted

No P0/P1 in the staged diff. One P2, fixed: I had added `--concurrency=1` to the
Supabase step **and left the Edge Function step in the same job unpinned**,
having just written the governing principle in a comment above the one I fixed.
Both `test/edge_functions/` files sign in as the same QA account and
`pgvector_test.dart:98,110` deletes `memory_embeddings`. Fixing the instance and
leaving the mirror is this repo's most recurrent self-inflicted class.

## Ground truth verified

Every claim checked directly, at file:line, not taken from a subagent:

| Claim | How verified |
|---|---|
| The boxes are user-namespaced | `hive_service.dart:226-229` → `wrapUserScopedBox` → `namespacedBoxName` (`hive_user_session.dart:88-105`) |
| The forwarders open the session | `sync_workout.dart:2017`, `sync_nutrition.dart:846`, `sync_health.dart:545` → `_ensureSessionOpen` (`sync_service.dart:453`) → `ensureOpenedForCurrentSession` |
| `weeklyFullSync()` does NOT | `sync_service.dart:973-976` reads `_supabase.currentUser?.id` directly |
| `SupabaseService.currentUser` is gated | `supabase_service.dart:81` (`if (!_initialized) return null`), while `client` (`:58`) is not |
| The dart-defines match | `AppConstants` (`app_constants.dart:11-12`) and the helper (`:35-36`) read the same two `String.fromEnvironment` names |
| Nutrition key predicate | `_nutritionLogsRaw()` (`sync_nutrition.dart:428-438`) — `nutritionBox`, `nlog_` prefix |
| Writers swallow per-key, in-loop | `sync_workout.dart:168-176`, `sync_nutrition.dart:414-422`, `sync_health.dart:227-234` |
| Columns exist | `backups/live_schema_columns.json` — `workout_name` present, `exercise_name` absent |
| Blast radius | `blast_radius_from_diff.dart` on the STAGED set → `platform` |
| CI has no concurrency pin | `grep -n concurrency .github/workflows/test.yml` + `dart_test.yaml` |

## Convergence

`converged`. Every finding across both rounds and the B-pass is terminal: fixed,
or refuted with the refutation recorded, or accepted with its residual stated.
`flutter analyze test/supabase/` is clean and the whole directory is 20/20 green
without dart-defines, including the 14-test credential-free guard suite — so the
helper change did not break the define-less `Unit Tests` job.

## NOT claimed — the honest limit

**That these three tests pass, or that they discriminate.** The QA credentials
exist only as GitHub secrets; local `.env` has `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `RAZORPAY_KEY_ID` and nothing else, so the suite skips
locally and I never handle the password. CI settles the live pass. CI does **not**
settle discrimination — that would mean pushing a deliberately broken writer.

What stands in its place is a link-by-link argument, and it is strictly weaker
than a run: the failure modes are *observed* (today's tests fail with exactly
`PGRST204` and `22P02` against correct writers, i.e. the live cloud rejecting
those shapes); the writers' catch is per-key in-loop, so a rejection leaves zero
rows; `rows.single` on `[]` throws. Each link verified, the composition never
executed. Anyone with the credentials closes it in one command — mutate
`sync_workout.dart`'s projected `'workout_name'` to `'exercise_name'`, run the
file, confirm T3 reddens, revert.
