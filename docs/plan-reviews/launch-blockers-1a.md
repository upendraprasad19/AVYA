---
branch: launch-blockers-1a
date: 2026-08-25
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/a51a2ba9de14-review.md
hermes: accepted
hermes_report: docs/audit/2026-08-25-hermes-launch-blockers-1a.md
---

# Plan-review record — launch-blockers-1a (catastrophic)

Keystone record for the §4.12 merge gate. Catastrophic because the batch touches
`supabase/functions/razorpay-webhook/` — path-keyed, even though the change there is comment-only.

## What this batch is

The **converged half** of a go-live audit, split from a larger batch per §4.12.1.

- **OI-97 / `c2b8e5`** — paywall letterhead read "PRO is a PRO feature" on the three payment
  entry points.
- **`d8f2c1`** — the sign-up consent checkbox was pre-ticked (DPDP §6(1)).
- **`f3c7d2`** — load-dependent flake in the entitlement CQRS test.
- **Webhook docstring** — named a `RAZORPAY_WEBHOOK_SECRET` that is read nowhere; following it
  when creating the LIVE webhook fails every payment's HMAC silently.
- **`/build-apk --bundle`** — Play cannot accept an APK.
- **`docs/operations/GO_LIVE_CHECKLIST.md`** — the artifact the audit produced.

## Review history — and an honest account of the round counts

**This record's `review_rounds: 2` is not a formality; the rounds materially changed the code.**

**Round 1 — B-pass on the unsplit batch** (`docs/reviews/eb37932a4218-review.md`, 3 findings, all
fixed). The sharpest was the OI-98 restore leg reaching one of four restore entry points, missing
the reinstall path, certified by a test asserting a COUNT that two branches of one function
satisfied.

**Round 2 — Hermes, five parallel Opus lenses** (L1, L11, L15, L16/L37, L39) on the post-round-1
code. It found **two P0s that broke both headline fixes**:

- The OI-89 bodyweight guard keys on `equipment_tier`, which `docs/sot_registry.yaml` itself
  declares deliberately over-tagged (*"over-tags tolerated"*). Four bundled rows are tiered
  `bodyweight` while `equipment_needed` names real kit — so `Chin Up` (pull-up bar), one of the
  three exercises the bug reported, still reached a no-equipment user. Reproduced by driving the
  real `pickV4`.
- The OI-98 fix reads the newest snapshot row, which `splash_screen:189`'s push — fired 14 lines
  before `checkAndSync()`, through a leading-edge coalescer — overwrites with the all-enabled
  default first. Confirmed against live prod: of 126 snapshot rows, 14 carry prefs and every one
  is 10 keys with `off_count=0`.

**The split decision.** §4.12.1: *"When successive reviews keep surfacing new material issues, that
is the signal the unit is too large — split it and ship the smallest converged piece, don't review
the large thing a fifth time."* Round 2 surfaced ~15 new findings including two P0s, so the
plan-engine and sync/restore work was removed to `launch-blockers-1` @ `d45d7182` and is NOT in
this branch.

**Round 3 — B-pass on the split diff** (`docs/reviews/a51a2ba9de14-review.md`, 6 findings, all
accepted, no P0). A seventh lens, `split_self_consistency`, was added specifically to catch a doc
in this half asserting a fix that is not in the tree; it returned clean and independently verified
the checklist's STILL-OPEN framing against the live exercise library.

**On `hermes: accepted`, stated precisely.** The Hermes pass ran against the SUPERSET
(`d45d7182`), not against this exact diff. Everything it flagged in the half that remains here was
fixed; everything it flagged in the removed half went with that half. No Hermes finding against
this content is outstanding. Recording it as accepted, with the scope stated in the report itself
(`docs/audit/2026-08-25-hermes-launch-blockers-1a.md`), is the honest reading, and the distinction is written here rather than left for someone to infer from
two different hashes.

## Ground truth verified

Not accepted on reviewer prose — each re-checked against code or live state by the author:

- The four over-tagged library rows, by parsing `assets/data/exercise_library.json` directly.
- `splash_screen`'s push-before-`checkAndSync` ordering, and `SyncCoalescer` being leading-edge.
- `_buildSnapshot` does not exist in `lib/` (the real method is `compileDailySnapshot`) — a
  phantom symbol the author had cited in six places, all in the removed half.
- OI-75 is CLOSED, contradicting a claim in the removed half's diagnose-doc.
- `subscription_service.dart:275` is `writeSubscriptionState`, not `_downgradeLocally` (`:1152`).
- The webhook file reads `RAZORPAY_KEY_SECRET` and never `RAZORPAY_WEBHOOK_SECRET`.
- Full suite on this branch: **4827 passed, 7 skipped, 0 failures**, run uninterrupted and alone.
- `flutter analyze`: no new issues (the unsplit batch measured 262, byte-identical to the `main`
  baseline).

One claim the author made and then **refuted himself** before acting: that the lens registry
defined only 24 lenses and Hermes' default set pointed at phantom ones. All 53 exist; the first
grep was anchored to line-start and required a non-bold ID, so it missed every bolded row.
Recorded because the near-miss was rewriting correct documentation.

## Known open risks carried into launch

Both are checklist rows, not silent omissions:

1. **The bodyweight-plan defect is NOT fixed** (`GO_LIVE_CHECKLIST.md` §6). The durable fix keys
   on `equipment_needed` via `EquipmentVocab.fromProfile`.
2. **Google OAuth has no consent gate** (`GO_LIVE_CHECKLIST.md` §3, founder row 3.5). Those users
   get `terms_accepted_at` auto-stamped by a pre-existing fallback. Fixing it is a UX decision
   about where consent sits in a redirect flow, which is why it is a founder row.
