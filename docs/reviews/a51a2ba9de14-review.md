---
reviewed_at: 2026-08-25T11:20:00+05:30
staged_against: a51a2ba9de14
reviewed_diff_hash: d461543ec71c
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, split_self_consistency]
findings_count: 6
verdict: accepted
---

# Code Review (B-pass) — launch-blockers-1a — `a51a2ba9de14`

Fresh Sonnet subagent, no conversation context. Catastrophic tier (touches
`supabase/functions/razorpay-webhook/`).

**This is the SPLIT half.** A larger batch (`launch-blockers-1` @ `d45d7182`) was reviewed by a
B-pass and a five-lens Hermes pass, which found two P0s that broke both of its headline fixes. Per
§4.12.1 the unit was split; the plan-engine (OI-89) and sync/restore (OI-98) work was REMOVED and
is not under review here. A seventh lens — `split_self_consistency` — was added specifically to
catch a doc in this half asserting a fix that is not in the tree.

**Two hashes.** Reviewed at `d461543ec71c`; all six findings fixed in-batch per
`feedback_no_deferrals.md`, moving the diff to `a51a2ba9de14`. The delta is exactly those fixes
plus the new diagnose-doc recording one of them. Every finding was verified against the code by
the author before acting.

---

## Finding 1 — P1 — guard_without_its_mirror — Google OAuth has no consent gate

- **claim:** `_privacyAccepted` gates exactly one widget, the email CREATE ACCOUNT button (`sign_in_screen.dart:1023`). `signInWithGoogle()` (`:365`) — the primary CTA — has no gate, and those users hit the pre-existing `ensureTermsConsentFallback` (b3f9e7, untouched), which auto-stamps `terms_accepted_at` from `created_at` with no user gesture. After this batch the app runs two consent regimes: an explicit tick on the secondary route, a backdated timestamp on the primary one.
- **verification:** `grep -n "_privacyAccepted" lib/features/auth/screens/sign_in_screen.dart` → 111, 1012, 1014, 1015, 1023, 1033 — none near `:365`.
- **resolution:** Recorded as **founder row 3.5** in `docs/operations/GO_LIVE_CHECKLIST.md` with a full warning block, and in diagnose `d8f2c1`'s impact_analysis as a KNOWN RESIDUAL. NOT silently patched: gating the primary sign-in affordance means deciding where consent sits in a redirect flow (pre-launch, or post-redirect) — a UX decision, not a copy fix. The checklist is the artifact whose job is carrying launch blockers, so a Play submission cannot happen without reading it.
- **status:** accepted

## Finding 2 — P2 — writer_reader_drift — diagnose-doc cited the wrong method

- **claim:** `f3c7d2`'s `writers:` cited `subscription_service.dart:275` as `_downgradeLocally`. Line 275 is inside `writeSubscriptionState` (declared `:259`) — an ACTIVATION write with opposite semantics. The real `_downgradeLocally` is at `:1152`.
- **verification:** `grep -nE "Future<void> writeSubscriptionState|Future<void> _downgradeLocally" lib/core/services/subscription_service.dart` → 259 and 1152.
- **resolution:** Corrected to `:1152`, with the mis-citation recorded in the entry itself. Exactly the error §4.1's name-by-file:line rule exists to prevent, in the doc written to demonstrate that discipline.
- **status:** accepted

## Finding 3 — P3 — writer_reader_drift — citation matches neither file state

- **claim:** `c2b8e5` cited `_featureSubtitle`'s switch at `:104`. It is `:75` pre-fix and `:134` post-fix.
- **verification:** `git show HEAD:lib/shared/widgets/paywall_sheet.dart | grep -n "switch (widget.feature)"` → 75; staged → 134.
- **resolution:** Corrected to `:75`, matching the doc's other citations' pre-fix convention, with the post-fix line noted.
- **status:** accepted

## Finding 4 — P3 — guard_without_its_mirror — render-site test is rename-brittle

- **claim:** The new "THE RENDER SITE" group greps literal identifiers, so a purely cosmetic rename of `_featureTitle` reddens it — a false positive, not a caught regression. Mutation-confirmed by the reviewer.
- **resolution:** The comment now states the cost plainly and instructs updating both strings on a rename. The trade is kept deliberately: a rename-brittle guard beats no guard on the one line whose reversion silently restores the tautology on every payment surface, with all other tests green.
- **status:** accepted

## Finding 5 — P3 — missing diagnose-doc for the consent flip

- **claim:** The `_privacyAccepted` change is a real fix with a regression test, but had no diagnose-doc, while the checklist marked it DONE. Rule 22 requires one for any `fix:` commit.
- **resolution:** Added `docs/diagnoses/2026-08-25-consent-checkbox-pre-ticked-d8f2c1.md`, validated. It also became the right home for Finding 1's residual.
- **status:** accepted

## Finding 6 — P4 — drain guard changes the blast radius of a flake

- **claim:** `_drainAndClearEntitlementKeys` throws from `setUp`, so a non-convergence fails the WHOLE FILE rather than one assertion. A strict improvement over silent misattribution, but a change in failure SHAPE.
- **resolution:** Named explicitly in `f3c7d2`'s impact_analysis rather than left implied. No code change — the loud failure is the intent.
- **status:** accepted

---

## What the reviewer checked that returned clean

- **split_self_consistency:** `git diff --cached | grep -n "a7d4f1|OI-89|OI-98|notification_prefs|_restoreNotificationPrefs"` → zero. `equipment_tier`/`bodyweight` appear only in the checklist's explicit STILL-OPEN section, and the reviewer independently verified that claim against `assets/data/exercise_library.json` — `Chin Up` and `Standing Calf Raise` are genuinely tiered `bodyweight` with `equipment_needed` naming a pull-up bar and a barbell. No staged file touches `plan_engine/`, `sync`, or `restore` paths.
- **blast_radius_mismatch:** the webhook change is comment-only and the new comment is TRUE — `verifySignature(rawBody, signature, RAZORPAY_KEY_SECRET)` at `:263`, no `RAZORPAY_WEBHOOK_SECRET` read anywhere in the file. The DELETED line was the lie. Corroborated against `docs/audit/2026_06_11_audit_closures.yaml:93`.
- **writer_reader_drift (sentinels):** 14 real feature cases and 30 `showPaywallSheet(` call sites audited; no real label equals `'PRO'`/`'PRO Upgrade'` trimmed+lowercased. `paywall_shown` logs the raw value, so the two sentinels stay distinguishable in the funnel while the letterhead is correct for both — the fix for the telemetry collapse holds.
- **secrets_in_tree:** zero matches for `rzp_(live|test)_`, `sk_live`, `AIza`, `eyJ…`, `-----BEGIN`.
- **function_exception_swallow / unawaited_no_error_sink:** no PostgREST or Edge Function call is touched; the only `unawaited(` hits are comments referencing the unmodified `subscription_service.dart:458`.
- **Mutations run:** reverting `title: _featureTitle` reddens 2 groups; reverting `_privacyAccepted` to `true` reddens the regex assertion; reverting the drain to the single-pass delete passes idle (consistent with the doc's own "0-in-9 idle" claim — the reviewer did not attempt the load reproduction).

## Founder triage notes

All six **accepted**. Five fixed in-batch; Finding 1 is recorded as an explicit founder decision
row rather than patched, with the reason stated.

The pass earns its keep twice. Finding 1 is a genuine pre-launch compliance risk that only became
visible BECAUSE the email path was fixed — the kind of thing that reads as an inconsistency to a
reviewer and would have been found by them instead of us. Finding 2 is the sharper lesson: a
diagnose-doc written to demonstrate file:line discipline contained a file:line error conflating an
activation writer with a downgrade writer.
