# FOB-5 — hold telemetry + the engagement-metric channel filter (OI-60 blocker 2) · 2026-08-20

Branch `claude/oi-pending-hold-weeks-1od97o` · commits `2c07a4f`, `e44de64`, `9e02370`, `a41b530`
Diagnoses `c7a3b9` (metric + telemetry) and `b2e9f4` (the pre-push gate)
Closure `docs/audit/fob5-hold-telemetry.closure.yaml` (12/12 terminal) · B-pass `de874b85c95c`
Migration 120 applied live · `admin_metrics_daily` backfilled (authorized)

## What this batch was, and what it turned into

FOB-5 as filed was one line: *"add `where channel = 'app'` to `ai_messages_today`."*
It shipped as twelve findings across two diagnose-docs, and the single most
useful act of the whole batch was **refusing to do what the filing said**.

## Five things worth carrying forward

**1. The filed fix was wrong, and only a live query could show it.**
`channel = 'app'` matches **7 of 116 rows**. Applying it would have replaced a
5.3× overcount with an ~89% *undercount* — a worse number that looks like a fix,
and one nobody would have questioned because the metric moved in the expected
direction. The repo already held the right answer: `_coachChatChannels =
{app, chat, in_app_orphan}` at `coach_interaction_repository.dart:282`. §4.9
("verify an audit finding's claimed cloud state before applying it") is what
caught it, and it is worth more than it costs. **A filing is a hypothesis.**

**2. DROP + CREATE resets the ACL. This one bit, live.**
Three added columns force a `DROP` (42P13 forbids changing a return type via
`CREATE OR REPLACE`), and a fresh function picks up Supabase's default
privileges on schema `public`, which grant EXECUTE to `anon` and
`authenticated`. Migration 101's `revoke all ... from public`, copied verbatim,
does **not** remove those — PUBLIC and an explicit role grant are different
things. A SECURITY DEFINER function was anon-executable for minutes. Caught by
walking **tier 8** of the 12-tier checklist, not by any gate.

**3. The mirror of (2) is the one that generalises: the GUARD had gone blind.**
`admin_metrics_functions_role_revoke_test.dart` asserts that *migration 103*
carries the role revokes. 103 stopped owning that function's ACL the instant 120
replaced it — so on a replay past 120 the protection comes only from 120's own
revoke lines, and deleting them re-opens the leak **while the test stays green**.
Fixing the live ACL and hardening the `.sql` would have felt like closing it.
The durable statement: *when a fix moves ownership of an invariant from one
artifact to another, the test that pins it must move too — or be rewritten to
name the invariant instead of the artifact.* The replacement asserts over the
whole migration set, so 121, 122 … are covered on arrival.

**4. A gate that fails what CI passes trains you to disarm every gate.**
`pre-push.sh` ran a bare `flutter test`; CI runs `flutter test test/
--exclude-tags golden` under `TZ: Asia/Kolkata` pinned at *workflow* level (which
is why it hid — it is not on the job step). Four failures, none touched by the
diff. This had already consumed **two separate one-push `--no-verify`
authorizations** before anyone asked why. That is the real cost: not the minutes,
but the steady conversion of an operator into someone who reaches for the bypass
by reflex. Fix the cause; a false red has no other exit.

**5. The fix was correct, tested, mutation-proven — and still did nothing.**
`.git/hooks/pre-push` is a `cp`, not a symlink, and it was stale. The push failed
with the *identical* four failures. Every signal available said the gate was
fixed. This is OI-104's second occurrence in nine days, and it adds something the
entry lacked: **no test can catch this class**, because a test that reads
`scripts/pre-push.sh` is reading the source while a different file is what runs.
The proposed hash check is not redundant with test coverage — it is the only
instrument that can see it. And the failure mode is a false *negative on your own
fix*, whose natural next move is, again, `--no-verify`.

## Two process notes

**OI-108 is real; I hit it.** `safe_commit.sh` takes the message positionally and
hands it to `git commit -m`, so `-F <file>` committed with the subject `-F`.
Reset and re-committed. Worth fixing — it is a few lines.

**The catastrophic tier is not satisfiable from this session.** The migration
pushed blast-radius to `catastrophic`, which needs `review_rounds >= 2` +
`hermes: accepted`. Subagent dispatch is unavailable here, so the B-pass ran
**inline, by the same context that wrote the code** — recorded as such at the top
of the review rather than dressed up as independent. The plan-review record says
`verdict: needs_round_2_and_hermes`, which correctly leaves the branch
**mergeable-blocked**. Writing `converged` would have bought a merge with a
fabricated review; the anti-fabrication clause in that gate exists for exactly
that temptation. The branch is safe to push and not ready to merge.

## The backfill, and the bug inside the fix

`admin_metrics_daily` held 25 rows under the old definition (15 divergent, series
total 58 → 8). Founder authorized the UPDATE. **The first recompute statement was
wrong**: `update ... from (select * from recomputed) r where r.d = m.snapshot_date`
is an INNER join, and 13 of the 15 rows needed to become `0` *precisely because*
those days had no qualifying interactions — so `recomputed` has no row for them
and the join skips them. The preview read correctly only because it used a LEFT
join. It surfaced **only** because the first attempt hit a connection timeout,
forcing a state re-check before the retry; a clean run would have reported
"15 rows updated" and left 13 wrong. Carry forward: *a preview query and its
UPDATE must have the same join semantics, or the preview is not a preview.*
