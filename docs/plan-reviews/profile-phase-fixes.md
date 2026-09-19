---
branch: profile-phase-fixes
date: 2026-08-30
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/56e7d3cf49d0-review.md
---

# Plan-review record — profile-phase-fixes (platform)

Keystone record for the §4.12 merge gate. Platform tier because
`lib/core/services/sync/sync_profile.dart` is path-pinned platform in
`docs/blast_radius.yaml:63` (`lib/core/services/sync/**`). Verified by running
`dart run scripts/blast_radius_from_diff.dart` against the staged file list —
`Blast-radius: platform`, not assumed from the registry by eye.

## What the branch is

Three fixes bundled from one founder observation session on a private-window
sign-in as `upendraprasad19@gmail.com`:

1. **Full-name restore race** (`sync_profile.dart`) — diagnose `d4e9a2`. The
   `public.users` SELECT feeding the restore's profile-map merge had no retry, so
   a token expiring mid-restore could return an RLS-filtered empty result (HTTP
   200, `null`, no exception — indistinguishable from "no such row") and silently
   drop `full_name` while the rest of the restore succeeded. Extracted into
   `_fetchUsersRowForRestore`: proactive `ensureFreshToken()`, then one retry
   behind a hard `auth.refreshSession()` on an empty first result, mirroring the
   existing `c2e9f4` precedent for the identical ambiguity.
2. **Phase-2 "missing Phase I" tripwire** (`workout_schedule_read_service.dart`)
   — diagnose `b7f1c8`. A session-scoped, per-account telemetry tripwire on the
   strict-empty + `currentPhase > 1` branch. Observability only: the return value
   is byte-identical in every branch.
3. **DEPLOYMENT label hardcode** (`train/screen.dart` + `hold_week_labels.dart`)
   — diagnose `b7f1c8`. A literal `'DEPLOYMENT 01'` that rendered for every
   account at every phase, replaced by a pure `deploymentEyebrowLabel` formatter
   driven by `plan.phase`.

## Ground truth verified

Every live-data claim in both diagnose-docs was re-queried directly against
Postgres (`dedsavbjuwgarrhphgnl`) rather than carried forward from prose — by me
and independently by both review rounds:

- 6 `profile_full_name_empty_at_read` rows, split 4x `upendraprasad19@gmail.com`
  / 2x `anoopdd13@gmail.com`, all `platform: web`.
- Exactly 2 accounts with `user_progress.current_phase > 1` (of 17 total), both
  matching their cited states exactly.
- The `deployments_complete = current_phase - 1` invariant holds across all 17
  accounts (15x(1,0), 2x(2,1)), not merely the 2 cited.
- `client_errors` retains from 2026-08-01 only — which is why the OI-150
  mechanism below could be neither confirmed nor excluded from telemetry.

## Review rounds

**B-pass** (`docs/reviews/56e7d3cf49d0-review.md`) — fresh context-blind
subagent, 8 lenses. **6 findings, 0 false alarms, all resolved.** Two were real
code gaps: the retry was unreachable on the primary (C3 single-call) restore path
(now logs `restore_users_row_null_via_singlecall` distinctly there), and the
hard-refresh call had no catch of its own (now wrapped, logs
`restore_users_row_retry_threw`). One corrected a factual error in my own live-data
investigation: the second telemetry account was `anoopdd13@gmail.com`, not
`amar@gmail.com` as originally written. Three were citation/reasoning fixes.

**Round 1** — independent context-blind plan review. **3 findings, all real, all
fixed.** The important one was **proven by mutation, not argued**: changing
`return retried;` to `return first;` — reintroducing the exact pre-fix defect —
left all 7 tests green, because they pinned call count, ordering and telemetry
substrings but never the return value. Also corrected an overclaim ("every
legitimate app-driven path is structurally incapable...") that had examined only
the advance-side writer, and a call-site count that was 3 when it is 4.

**Round 2** — run on the POST-round-1 hardened state, per §4.12.1. **5 findings,
all real, all fixed.** Two were demonstrated mutations against round 1's *own*
fixes — exactly what a second round exists to catch:

- The round-1-added return-value test pinned what happens *after* the retry and
  left the guard *gating* the retry unprotected: `if (false) return first;` kept
  all 8 green. That regression would force a hard refresh + second round-trip on
  every restore and discard an already-fetched `full_name` whenever the forced
  second call failed transiently.
- The tripwire tests asserted only that the event fires; replacing its entire
  message with a literal kept all 9 green, so the diagnostic payload could
  regress to nothing while still reporting "working".

Both gaps are now closed by assertions **independently verified to fail on the
exact demonstrated mutation before being accepted**. Round 2 also surfaced the
`mergeCloudProgress` mechanism (below), a SoT registry entry the batch claimed but
had not written, and a third stale line citation.

## The substantive finding: OI-150

Round 2's most valuable output was refuting a conclusion both the original
investigation and round 1 had signed off on. `b7f1c8` claimed every client-side
path was structurally incapable of producing the phase-2 anomaly. Traced end-to-end
in code, that is false:

`UserRepository.mergeCloudProgress` resolves `current_phase` as local-max-wins
(it is in `monotonicProgressFields`) but `current_week` and `phase_started_at` as
cloud-non-null-wins unconditionally (they are not). `commitPhaseAdvance` bumps all
three together locally and pushes fire-and-forget; if that push has not landed
before the next launch, `restoreLightweightAlways` — the branch every returning
user with non-empty Hive takes — reverts the week and date while keeping the
advanced phase, then writes the result back to Hive, cementing the mismatch.

That is a fully organic path to the exact observed state, requiring no raw
Postgres edit. It is **not confirmed** for either affected account (the telemetry
window cannot reach back far enough, and non-monotonic overwrites emit no event by
design), so direct QA manipulation remains equally live. The diagnose-doc's
conclusion has been rewritten to carry both hypotheses honestly instead of
claiming client-side is cleared.

**Filed as OI-150, not fixed here.** Coupling those fields is a data-integrity
change to a `platform`-tier merge function with its own kill-switch and an OI-83
history of two prior review rounds getting the field list wrong — a distinct
concept from this batch's three display/restore fixes. It is on the board with the
full mechanism traced, not left as an intention. The tripwire shipping here is
root-cause-agnostic: it fires on the symptom, so it observes this mechanism exactly
as well as the manual-edit hypothesis.

## Convergence

Round 2 returned `needs_round_3` with four bounded, mechanical items and an
explicit "I would not expect a round 4". All four are closed above, and the two
that were demonstrated mutations were re-proven against their new assertions
rather than accepted on argument. No round-3 dispatch: §4.12.1's split trigger is
*successive rounds surfacing new material issues*, and what remained after round 2
was a fixed checklist, not new territory — the substantive finding it raised
(OI-150) was resolved by filing it as its own unit, which is the split that rule
asks for.

## Verification at the point of this record

- `flutter analyze` on all touched `lib/` + test files — no issues.
- 89 tests green across the 6 touched/adjacent test files.
- Gates re-run directly: Gate 7 (SoT completeness), Gate 42 (behavioral test
  paths), `check_no_deferral_euphemism`, `check_oi_numbering_unique`,
  `check_skill_tuning_history`, `check_code_review_pass_exists`,
  `check_container_color_decoration`, `check_schema_column_refs` — all pass.
- Both diagnose-docs pass `validate_diagnose_doc.dart`.

⚠ One process note worth recording: early in this session several validations were
run as `sh scripts/_dart_bin.sh run <script>`, which silently does nothing (that
file is meant to be *sourced* — it only defines a function) and exits 0. Every
affected check was re-run against a properly resolved Dart binary. A green exit
code from a command that never ran is the same failure class this repo's own
memory files track under "bad news vs no news must not collapse".
