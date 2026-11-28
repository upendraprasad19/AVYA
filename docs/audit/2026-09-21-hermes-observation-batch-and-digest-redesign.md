---
hermes_pass_id: 2026-09-21-hermes-observation-batch-and-digest-redesign
ran_at: 2026-09-21T20:00:00+05:30
batch_scope: working-tree (branch claude/strange-merkle-c2d0b9 vs main)
lens_set: [L1, L21, L22, L23, L31, L34, L35, L40]
agents_dispatched: 8
findings_total: 12
findings_by_severity: { P0: 2, P1: 3, P2: 6, false_alarm: 1 }
verdict: accepted
---

# Hermes Pass — observation-batch-and-digest-redesign

> ⚠ **Provenance note, per this skill's own 2026-09-11 lesson.** This report
> was consolidated after a context compaction that destroyed the raw
> per-lens dispatch transcripts (8 parallel Opus agents, one per lens
> below). Rather than recall findings from a summary, every finding listed
> here is backed by a concrete artifact produced THIS session while fixing
> it — a diagnose-doc with file:line citations, a mutation-proof, or a live
> SQL verification query actually run against `dedsavbjuwgarrhphgnl` — not
> by memory of the original agent output. The `false_alarm: 1` count below
> is therefore a FLOOR, not a reconstruction of the original dispatch's
> full tally: one specific false-alarm (L34 #2) is independently
> re-confirmed against this batch's own spec review history; any other
> false alarms the original 8 agents raised were not preserved through the
> compaction and are not re-claimed here rather than guessed at.

## Why this pass ran

This batch's blast-radius classifies **catastrophic** by content rule —
migrations 138, 139, and 140 (added mid-batch to fix findings below) each
define a `SECURITY DEFINER` function, which
`scripts/blast_radius_content_rules_lib.dart` force-escalates regardless of
path glob. Per `docs/blast_radius.yaml`'s `requires:` list and
`scripts/check_plan_review_record_exists.dart`, a catastrophic-tier merge
hard-requires `hermes: accepted` in the plan-review record. This pass was
self-triggered (per `feedback_mistake_review_not_self_triggered.md` — never
wait to be asked) after re-reading the gate's own source confirmed the
requirement, rather than proceeding straight to commit/push/merge.

## Summary

- 2 P0, 3 P1, 6 P2, 1 false_alarm — **all 12 real findings fixed in-batch**;
  2 additional genuinely pre-existing, out-of-scope findings filed as
  tracked OIs (not fixed here, per §4.2's own scope-creep guidance — a
  cross-cutting, pre-existing gap outside this batch's declared scope is a
  new OI, not silent scope expansion).
- **Ship-blockers (P0), both resolved:**
  1. `alert_cron_failures`'s unbounded stuck-window ALREADY misfiring in
     production (public.alerts id=40 fired on stale data) — fixed via
     migration 140.
  2. `GEMINI_API_KEY` could leak into the founder's Telegram digest through
     an unredacted `fetch` TypeError — fixed via `redactSecrets` in
     `gemini.ts`, wired at every message-construction site touching an
     exception or upstream response body.
- **Filed, not fixed (genuinely pre-existing, cross-cutting, out of this
  batch's declared scope):**
  - OI-238 — 5 of the 6 Gemini-calling Edge Functions have no server-side
    exhaustion telemetry at all (only `ai-proxy` + `tool-loop.ts` do, per
    OI-226's own explicitly narrower scope).
  - OI-239 — acknowledging any `alert_*` cron job's page re-arms its dedup
    window instead of waiting out the original interval; a systemic
    property of all 6 `alert_*` jobs' shared idiom, needing a design
    decision across all 6, not a one-line fix in the job that surfaced it.
- **Reviewed, found NOT to be a new defect:** L34 #2 (the digest's
  warn-severity downgrade on a repeat alert within the dedup window) — this
  was an explicitly reviewed and accepted design tradeoff in the batch's
  own spec review rounds (`docs/superpowers/specs/2026-09-21-observation-
  batch-and-digest-redesign-design.md`, "Open questions for plan review —
  status after round 1", item 1: "VERIFIED ACCURATE by review round 1...
  Proceeding as specced"), not a new regression this pass introduced or
  missed.

## Findings by lens

### L1 — writer/reader drift

- **F1 (P1, REAL, fixed):** `computeNewMrr` summed a yearly subscription's
  full booking price (₹2999) directly instead of dividing by 12 — MRR is a
  monthly figure. `telegram-admin-bot`'s own `/revenue` command already
  divides yearly by 12; this new writer failed to reuse that reader-side
  convention. Fixed: `founder_digest_content.ts:218`.
- **F2 (P0, REAL, fixed — same defect group as L31/L35 below):**
  `alert_cron_failures`'s stuck-job branch reads `cron_call_log.status`
  as if it reliably distinguishes "running" from "crashed" — it cannot,
  since `logCronEnd` (the writer) never runs on a crash/timeout. See L31/L35
  for the full writeup; grouped here as one fix (migration 140).
- **F3 (P1, REAL, fixed):** `private.set_subscription_cancelled_at()` only
  wrote `cancelled_at` forward; the ONLY writer of `status='cancelled'`
  (a manual dashboard edit, confirmed live — no application code writes it)
  can just as easily reverse it, and the trigger had no branch for that
  direction. Fixed: migration 140.

### L21 — Edge Function semantic correctness

- **F1 (P1, REAL, fixed — same as L1 F1):** MRR yearly/12, see above.
- **F2 (P2, REAL, fixed):** `cancelledYesterdayRead` filtered on
  `cancelled_at` alone with no `status='cancelled'` check — belt-and-
  suspenders on top of the migration 140 trigger fix. Fixed:
  `founder_digest_content.ts:852`.
- **F3 (P2, REAL, fixed):** `rolling-context`'s `summarizeMessages` sits in
  a per-user loop with `retries: 2` and no other retry on the path — worst
  case 6 Gemini calls/user, amplified across every active user in one
  nightly run, heaviest exactly when Gemini is already degraded. Halved to
  `retries: 1`. Fixed: `rolling-context/index.ts:110`.
- **F4 (P2, REAL, fixed — same defect as L23 #4):** `userNamesRead`'s two
  `fetchAllByIds` calls carried no `maxPages` bound, unlike every other
  paged read in the same file, on a synchronous Telegram-webhook-timeout-
  sensitive path (`/digest`). Fixed: `founder_digest_content.ts:915,927`.

### L22 — schema-vs-payload parity

- **F1 (P2, REAL, fixed — same as L1 F3):** trigger `BEFORE UPDATE` only —
  an INSERT carrying `status='cancelled'` directly fired no trigger at all
  and stored a NULL stamp. Widened to `BEFORE INSERT OR UPDATE` in
  migration 140.
- **F2 (P2, REAL, fixed — same as L21 F2):** `cancelledYesterdayRead`
  missing `.eq('status','cancelled')`, see above.

### L23 — service-role auth / privacy fail-open-vs-closed

- **#1 (P0, REAL, fixed):** the shared Gemini request URL carries
  `GEMINI_API_KEY` as a `?key=...` query param; Deno's `fetch` embeds the
  full request URL in a network-failure TypeError, and 3 sites in
  `gemini.ts` stringified that raw exception directly into a message that
  flows to `reportGeminiExhaustion` → `public.alerts` → the founder's
  Telegram digest. Fixed: new `redactSecrets`, wired at every
  message-construction site touching an exception or response body
  (5 call sites total, not just the one confirmed leak — closing the
  class, not the instance).
- **#2 (P2, REAL, fixed):** the extracted first name was a bare
  `.split(" ")[0]` on `users.full_name` (attacker-adjacent — seeded
  verbatim from signup metadata) with no control-character/newline
  stripping or length cap. Fixed: routed through the pre-existing
  `sanitizeIdentifier` helper (`re-engagement` already uses it for the
  same purpose).
- **#3 (P1, REAL, fixed):** privacy-fail-open — a user with no
  `coach_memory` row at all (never opened the AI coach) fell through to
  "shown," the opposite of privacy-by-default. Fixed: replaced the
  suppress-set (`privateIds`, built from `private_mode === true`) with an
  allow-set (`explicitlyVisibleIds`, built from `private_mode === false`).
- **#4 (P2, REAL, fixed — same as L21 F4):** unbounded pagination, see
  above.

### L31 — cron job efficiency / non-terminating conditions

- **F1 (P0, REAL, fixed — same defect group as L1 F2 / L35):**
  `alert_cron_failures`'s `status='started'` branch had NO upper time
  bound — a crashed-and-never-updated row pages the founder indefinitely.
  Confirmed LIVE: two rows from a 2026-09-19 04:15 UTC crashed tick were
  still `'started'` 2.5 days later, both functions had succeeded many
  times since, and `public.alerts` id=40 had already fired on this stale
  data (detected 2026-09-21 17:30 UTC) — an ACTIVE production false-alarm
  page at the time this lens ran. Fixed: migration 140 bounds the branch
  to a 6-hour lookback (chosen to stay inside sibling
  `alert_cron_function_dead`'s 8-day horizon, so a genuinely-still-broken
  job past 6h remains covered by that sibling alert).

### L34 — telemetry coverage on async failure legs

- **#1 (P2, REAL, fixed):** `tool-loop.ts`'s Gemini-exhaustion alert fired
  unconditionally, with no way for the founder to tell "user got nothing"
  apart from "user's real action (e.g. `logSet`) already succeeded in an
  earlier round; only the summarization reply failed" — the exact
  distinction the pre-existing FC2 apology-suppression guard already made
  for the user-facing text. Fixed: `hadQueuedIntent` computed once,
  threaded into both the FC2 guard (unchanged behavior) and a new `extra`
  field on `reportGeminiExhaustion`'s `context_json` (additive only —
  never changes whether the alert fires).
- **#2 (FALSE_ALARM — not a new defect):** the digest's warn-severity
  downgrade on a repeat alert within its 30-minute dedup window looked, in
  isolation, like it could bury a P0 behind a lower-severity Telegram
  notification. Checked against the spec's own review history: this was
  an EXPLICITLY reviewed and accepted tradeoff (round-1 plan review,
  "VERIFIED ACCURATE... proceeding as specced") — not a gap this batch
  introduced or this pass newly discovered. No action.

### L35 — migration reversibility / forward-compat

- **F1 (P0, REAL, fixed — same defect group as L1 F2 / L31 F1):** same
  stuck-window defect as above, from the reversibility angle: the
  original migration's lack of a bound also meant no forward-compat story
  for a crashed job ever aging out except via the 7-day
  `cleanup_cron_call_log()` sweep. Fixed alongside L31 F1.
- **F2 (P1, REAL, fixed — same as L1 F3):** `cancelled_at`'s missing
  reverse-clear branch, from the reversibility angle: a trigger that
  claims to be "self-maintaining regardless of HOW the status changes"
  needs a defined behavior for BOTH directions of that change to actually
  be reversible in practice. Fixed alongside L1 F3.

## Founder triage

Self-triaged per this project's `feedback_mistake_review_not_self_triggered.md`
precedent (the AGENT runs the review; the FOUNDER approves the converged
result, not each individual run) — every REAL finding above was fixed in
this same batch with a diagnose-doc + mutation-proof, matching §4.2's
no-deferrals policy for a self-triggered review. The 2 out-of-scope OIs and
the 1 false-alarm are the only non-`fixed` terminal states, both with an
explicit reason recorded above and in their own OI/spec citations.

## Action items

- [x] MRR yearly/12 + referral_trial known-zero-plan — fixed,
      `docs/diagnoses/2026-09-21-founder-digest-mrr-and-privacy-hardening-e5c8a2.md`
- [x] `alert_cron_failures` stuck-window bound + `cancelled_at`
      reactivation-clear + INSERT-gap — fixed,
      `docs/diagnoses/2026-09-21-hermes-pass-migration-138-139-fixes-h1a2b3.md`
- [x] `userNamesRead` privacy-fail-open + sanitizeIdentifier +
      pagination bound + `cancelledYesterdayRead` defensive filter — fixed,
      `docs/diagnoses/2026-09-21-founder-digest-mrr-and-privacy-hardening-e5c8a2.md`
- [x] `GEMINI_API_KEY` leak via `redactSecrets` + `rolling-context` retry
      amplification + `tool-loop.ts` `hadQueuedIntent` context — fixed,
      `docs/diagnoses/2026-09-21-gemini-secret-leak-and-retry-telemetry-hardening-f9d3b7.md`
- [x] filed as OI-238 on `docs/audit/open_issues.md` — owner: founder
      (5 Gemini-calling functions missing server-side exhaustion telemetry)
- [x] filed as OI-239 on `docs/audit/open_issues.md` — owner: founder
      (ack-based dedup re-arm, systemic across all 6 `alert_*` jobs)
- [x] verified_clean: L34 #2 warn-severity downgrade — already reviewed
      and accepted in the spec's own round-1 review, not a new defect
