---
reviewed_at: 2026-09-30T00:45:00+05:30
staged_against: main...HEAD (ce709fd9, 3 commits, nothing staged — whole-branch review)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
---

# Code Review — claude/sync-aab-build-check-408772 (platform)

Whole-branch review (nothing staged, all 3 commits already landed):
`8113406c` (vercel.json ignoreCommand flip), `4bcd41d8` (Razorpay order `notes` tagging +
`.gitignore` entry), `ce709fd9` (OI-274 filing + design-doc correction). Reviewed against
`git diff main...HEAD`, blast-radius `platform` per `blast_radius_from_diff.dart` (driven by
`create-razorpay-order/index.ts` falling through to the Edge-Function default tier).

Dispatched to a fresh, context-blind Sonnet subagent with no memory of how the diff was written.
All claims below were independently verified by the subagent by reading the actual files, not by
trusting the author's (this session's) summary.

## Lens 1 — writer_reader_drift (Razorpay order `notes` object)

Clean. Grepped every `.notes` reader in the repo: `razorpay-webhook/index.ts:458-459` reads only
`notes.user_id`/`notes.plan` (diagnostic-only, explicitly discarded); `verify-payment/index.ts:437,465`
reads only `notes.user_id`/`notes.promo_code`. Neither reads the new `notes.source`/`notes.billing_cycle`
keys. `docs/architecture/payment.md` rule 1 (plan derived from on-wire amount, never from `notes`)
matches the code. No collision, no shadowing.

**Finding 1 — P4 — informational.** Razorpay's Orders API caps `notes` at 15 key/value pairs.
Current object holds 5 keys max (`user_id`, `plan`, `source`, `billing_cycle`, optional
`promo_code`) — nowhere near the limit. Flagged only so a future addition to this object
re-derives the count rather than assuming headroom.
- **status:** accepted, no code change (informational only)

## Lens 2 — function_exception_swallow

Not applicable — confirmed via `grep -n "functions.invoke\|unawaited(" ` over the full diff: zero
matches.

## Lens 3 — blast_radius_mismatch

`create-razorpay-order/**` has no explicit pin in `docs/blast_radius.yaml`'s `paths:` list (only
`razorpay-webhook`, `verify-payment`, `delete-account` are pinned `catastrophic`) — it falls
through to the documented "any other Edge Function is platform-tier by default" catch-all.
`vercel.json` is explicitly pinned `account` tier. Branch-wide `platform` tier is consistent.
Diagnose-doc requirement (rule 22) does not apply — none of the 3 commit subjects match
`^(fix|bug|regression)` (`docs:`, `feat:`, `chore:`), confirmed via `git log main..HEAD --format="%s"`.

**Finding 2 — P1 — process gap (not a code defect).** No `docs/plan-reviews/claude-sync-aab-build-check-408772.md`
existed at review time — required for a `platform`-tier merge per §4.12.3.
- **status:** fixed in same batch — plan-review record written immediately after this review,
  citing this file as the `bpass_review`, with round 1 = this session's own ground-truth-verified
  self-review (webhook/verify-payment reader grep, `deno check`, live client-key-path trace done
  earlier in the session) and round 2 = this B-pass.

## Lens 4 — secrets_in_tree

No credential-shaped literal committed in the diff — the one `rzp_live_...` string in
`.gitignore`'s new comment is an illustrative placeholder inside a comment describing the
gitignored file's expected shape, not a real key (verified by reading the full comment block).

**Finding 3 — P2 — live secret left on disk (caused by, not part of, the diff).**
`.claude/.razorpay_live.env` (correctly gitignored, confirmed via `git check-ignore -v`) still held
populated live Razorpay credentials on disk at review time, past its own stated purpose ("Delete
after the values have been pushed to Supabase + Vercel"). Both destinations were in fact already
done (Supabase secrets pushed this session; Vercel dashboard env var updated manually by the
founder per their own message).
- **status:** fixed in same batch — file deleted immediately after this review completed.

## Lens 5 — unawaited_no_error_sink

Not applicable — same diff-wide grep as lens 2, zero `unawaited(` occurrences.

## Lens 6 — guard_without_its_mirror (`vercel.json` `ignoreCommand` flip)

Traced the shell case statement exactly:
`case "$VERCEL_GIT_COMMIT_REF" in main) exit 1;; *) exit 0;; esac`.
- `VERCEL_GIT_COMMIT_REF == "main"` → exit 1 → build proceeds.
- Any other value, including empty/unset → falls to `*)` → exit 0 → skipped.
- Case-sensitive exact-string match (not a glob), so a branch literally named `main-hotfix` or
  `Main` correctly does NOT match `main)` and is skipped, not accidentally built.
- Verified Vercel's exit-code contract (exit 0 = skip, exit 1 = build) against the platform's own
  semantics as documented elsewhere in this repo.

**Consequence named and checked for silent breakage:** this removes ALL Vercel preview
deployments for every non-`main` branch (previously only `oi/*` was skipped; every other branch —
every `claude/*` working branch, every PR branch — got a full preview build). Checked whether
anything in the repo depends on that: no GitHub Actions workflow references Vercel or a preview
URL/check; no skill (code-review, hermes-pass, e2e-sim-testing) references verifying a per-branch
Vercel preview URL; the OI-allocator's own `oi/*`-specific skip becomes redundant but not broken
(still skipped, now via the catch-all `*)` arm).

**Finding 4 — P4 — informational, currently inert.** If a Vercel deployment is ever triggered
without a resolvable git ref (a Deploy Hook, or a CLI-triggered deploy with no branch), the
variable would be unset and fall to `*) exit 0` — silently skipping what might have been intended
as a production deploy. No Deploy Hook or CLI-triggered deploy script exists in this repo today
(`scripts/`, `docs/` grep clean) — this repo's only deploy path is git-push-triggered, so the edge
case has no live trigger — worth knowing if a manual/API-triggered deploy path is added later.
- **status:** accepted, no code change (informational, no current trigger)

## Lens 7 — missing_input (`billing_cycle` ternary)

Clean. Traced `plan`'s full lifecycle in `create-razorpay-order/index.ts`: `body?.plan` →
`String(...)` → validated at `if (plan !== "monthly" && plan !== "yearly") return err(400, ...)`
(~30 lines above the diff) → never reassigned before the `notes:` block. By the time
`billing_cycle: plan === "monthly" ? "monthly" : "annual"` runs, `plan` is provably one of exactly
`"monthly"`/`"yearly"` — the ternary's implicit "anything not monthly is annual" is safe because
the validation gate already eliminated every third value.

## Lens 8 — asserted_fixture_value (design-doc correction + OI-274)

Clean. Numbers cross-checked for internal consistency: 57–70s / ~180s ≈ 31.7%–38.9% (avg ~35%) —
"roughly a third" is a fair characterization. 57–70s (SDK bootstrap) + 107–127s (flutter build web,
a separate, unaddressed cost) = 164–197s, bracketing the stated ~180s total — consistent. The doc
appropriately hedges: it states the reuse branch "has therefore never fired in production" as an
observed fact from two specific deployment IDs read via `list_deployment_events`, cited in OI-274's
own `Verified:` field — not as a permanent platform-behavior claim — and explicitly frames the fix
as needing its own test cycle against a non-`main` deploy before landing on `main`.

## Founder triage notes

No P0/P1 code defects. The 2 real findings (missing plan-review record, leftover secret file) were
both process/hygiene gaps caused by the state of the branch at review time, not bugs in the diff's
logic — both fixed in the same batch (plan-review record written; secret file deleted) before
merge. All 4 informational findings (P2/P4) are accepted as-is with no code change: `notes` key
count has headroom, the Deploy-Hook edge case has no live trigger, and the `Cache the Flutter SDK`
prose correction is appropriately hedged.
