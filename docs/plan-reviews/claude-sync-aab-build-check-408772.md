---
branch: claude/sync-aab-build-check-408772
date: 2026-09-30
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/sync-aab-build-check-408772-bpass.md
---

# Plan-review record — live Razorpay rollout: order tagging + Vercel build-skip fix (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `git diff main...HEAD --name-only | dart run scripts/blast_radius_from_diff.dart -`
→ `platform`, driven by `supabase/functions/create-razorpay-order/index.ts` falling through to
the "any other Edge Function is platform-tier by default" catch-all in `docs/blast_radius.yaml`
(`create-razorpay-order` has no explicit pin — only `razorpay-webhook`, `verify-payment`,
`delete-account` are pinned `catastrophic`). `vercel.json` is separately pinned `account`.

## What this branch is

Three commits, retroactively reviewed after landing (all work was additive/config, done in direct
response to the founder's live requests this session — not pre-planned):

1. **`8113406c`** — `vercel.json`: flip `ignoreCommand` from "skip only `oi/*` branches, build
   everything else" to "build ONLY `main`, skip everything else". Fixes a Vercel Pro billing
   spend spike: 38 wasted preview builds across 23 throwaway branches in 6.2 days, vs. 33
   legitimate `main` builds.
2. **`4bcd41d8`** — `supabase/functions/create-razorpay-order/index.ts`: add `source: "AVYA_app"`
   + `billing_cycle` to the Razorpay order `notes` object, purely for dashboard reconciliation on
   the live Razorpay account shared with the separate website — never read back for entitlement
   (verified: both readers, `razorpay-webhook` and `verify-payment`, only ever read
   `notes.user_id`/`notes.promo_code`). Plus a `.gitignore` entry for the local-only
   `.claude/.razorpay_live.env` credential handoff file used earlier this session.
3. **`ce709fd9`** — OI-274 filed (Vercel Flutter SDK re-cloned on every build, ~1/3 of build time
   wasted — Build Output API v3 migration needed to fix, explicitly deferred per founder's "we
   will pick up later") + a correction to a 2026-06-05 design doc's unverified assumption that
   Vercel's build cache already persists the `flutter/` directory (it doesn't — confirmed live via
   two consecutive deployments' build logs).

No kill-switch, no diagnose-doc required (none of the 3 commits match `^(fix|bug|regression)` —
verified via `git log main..HEAD --format="%s"`), not ship-dark-eligible (no flag, nothing gated
OFF by default) — full ×2 review applies per §4.12.1, not the §4.12.4 lighter tier.

## Rounds

| Round | Kind | Findings |
|---|---|---|
| 1 | Self-review while authoring, ground-truth-verified live against the actual code (not assumed from memory or from the founder's framing) | Read `create-razorpay-order/index.ts` in full before editing; grepped every `.notes` reader in the repo (`razorpay-webhook`, `verify-payment`) and confirmed neither reads `plan`/`source`/`billing_cycle` for entitlement — only `user_id`/`promo_code`. Ran `deno check --node-modules-dir=none` on the edited function (clean). Traced the WEB CLIENT's actual Razorpay-checkout key path (`lib/core/services/razorpay_service.dart`) and confirmed it opens checkout with the build-time `AppConstants.razorpayKeyId` constant, never the server's `key_id` response field — this is what surfaced the "server live, client bundle stale until redeploy" finding reported to the founder. Verified `.claude/.razorpay_live.env` is gitignored via `git check-ignore -v` before ever writing real credentials to it. |
| 2 | Context-blind B-pass (fresh Sonnet, `docs/reviews/sync-aab-build-check-408772-bpass.md`), all 8 lenses | 4 findings (0 P0, 1 P1, 1 P2, 2 P4); 0 false_alarm. P1 (missing plan-review record — this file) and P2 (leftover live secret file on disk past its stated purpose) both fixed in this same batch immediately after the review landed. The 2 P4s (Razorpay `notes` 15-key cap headroom; a dormant Deploy-Hook edge case in the new `ignoreCommand` with no live trigger in this repo) accepted with no code change. Independently re-verified the `notes` reader claim, the `plan` validation-gate claim (ternary safety), and the design-doc's numeric self-consistency (57–70s / ~180s ≈ 1/3) from scratch, by separate methods, rather than trusting round 1's framing. |

**Converged at round 2**: the B-pass surfaced zero material code defects — the writer/reader
analysis, the plan-validation-gate trace, and the build-skip logic trace all independently
confirmed round 1's conclusions by re-deriving them, not by reading round 1's prose. The two real
findings were process-state gaps (an artifact not yet written, a cleanup not yet done), both
closed within this same batch rather than argued over or split into a follow-up.

## Ground truth

Every consequential claim in the shipped diff was verified against the real files or live
platform state, by the author (round 1) and independently re-confirmed by a fresh reviewer with
no shared context (round 2):
- `notes` field readers: grepped, not assumed — `razorpay-webhook/index.ts:458-459`,
  `verify-payment/index.ts:437,465`.
- `plan` validation gate precedes the `notes:` block with no reassignment between them —
  confirmed both rounds independently by tracing the same function from two different starting
  points.
- Vercel's `ignoreCommand` exit-code contract (0=skip, 1=build) — confirmed against this repo's
  own prior documentation of Vercel's platform behavior.
- Build-log evidence for the Flutter SDK re-clone (218.7 MB Dart SDK download, 136 kB cache
  upload) — read directly via `list_deployment_events` on two consecutive `avya` deployments, not
  inferred.
- Both live-key handoff destinations (Supabase secrets, Vercel dashboard env var) independently
  confirmed complete before the leftover `.claude/.razorpay_live.env` file was deleted.
