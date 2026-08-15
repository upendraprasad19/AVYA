---
hermes_pass_id: 2026-08-15-hermes-supabase-creds-test6
ran_at: 2026-08-15T17:30:00+05:30
batch_scope: acffbd43..HEAD (branch supabase-creds-test6)
lens_set: [credential_identity_dataflow, destructive_op_safety, ci_semantics_false_green, claim_honesty_completeness]
agents_dispatched: 4
findings_total: 12
findings_by_severity: { P0: 0, P1: 4, P2: 6, P3: 1, false_alarm: 1 }
verdict: accepted
---

# Hermes Pass — supabase-creds-test6

Required by §4.12.3: blast-radius is **catastrophic**, so `hermes: accepted` gates
the merge alongside the B-pass. Four Opus lenses, dispatched in parallel,
context-blind. Lens set is stated inline rather than by `LENS_REGISTRY.md` id —
the registry was not loaded, and naming ids I had not read would be a fabricated
citation.

## Findings and disposition

### P1 — the credential guard was wired to 95 of 96 sign-in sites (2 lenses, independently)

`integration_test/flows/auth_flow_test.dart:76` types `kTestEmail` directly rather
than calling `signInWithTestUser`, so it never reached the guard. Its only
assertion is that the sign-in screen is still shown — which an EMPTY email
satisfies too, so the test would have silently degraded from "a wrong password is
rejected" to "nothing happened", and stayed green.

This is the **second** false enforcement claim about the same guard in this batch:
the B-pass found it defined with zero call sites, my fix called
`signInWithTestUser` "the single choke point every device flow passes through",
and that was false for exactly one test. **FIXED** at that site.

### P1 — OI-115's write-boundary bullet was unaddressed

The board calls `ai_proxy_test.dart`'s writes "the same boundary question" as the
deletes; the first pass guarded only deletes. Three live `ai-proxy` calls insert
rows and spend quota on whatever account the credential names, with no membership
check. **FIXED** — `assertDisposableTarget` after sign-in there. Without it,
closing OI-115 would have been a partial.

### P1 — the seed's safety warning was a guard written as a comment

It instructed the operator to run a check by hand. **FIXED** — now an executable
`DO $$ … RAISE EXCEPTION` block that refuses a non-loopback server. While fixing
it I wrote in an override flag the code does not implement, caught it, and removed
it rather than shipping a documented mechanism that does not exist.

### P1 — **FALSE ALARM**: "the four-input guard turns the job green without running"

The lens asserted the repo has "exactly two secrets configured", inferring it from
the repo's own comments about the 2026-08-12 addition rather than querying.
`gh api repos/:owner/:repo/actions/secrets` lists **four**, with
`SUPABASE_TEST_EMAIL` / `SUPABASE_TEST_PASSWORD` updated 2026-08-14T17:49Z. The
guard is satisfied and the steps run. Recorded because the reasoning was sound and
only the input set was wrong — the third time this class arrived from a reviewer
in this batch.

### P2 — a silently non-idempotent seed insert

`seed_qa.sql` used `gen_random_uuid()` with a bare `ON CONFLICT DO NOTHING`, which
has no arbiter and therefore never fires: **7 fresh `weight_logs` rows per run**.
Every other block in the file is idempotent. **FIXED** with a deterministic
`md5('qa-seed-weight-' || i)::uuid` and `ON CONFLICT (id)`.

### P2 — two count claims in my own prose were wrong

`git grep "\.delete()"` returns **12 lines**, not three — three are live call
sites, nine are string literals inside `test/contracts/` source-grep tests. And
the doc said "four other live documents" where the commit said "six" and seven
files changed. **FIXED**, both.

### P2 — open board entries were miscalled "historical record"

I claimed the old literals survive only in dated records. `open_issues.md` OI-116
was a **live OPEN** entry instructing the founder to create the very account this
batch abandoned, mirrored into the generated `OPEN_INDEX.md` that CLAUDE.md §7
designates the SoT for what is owed. **FIXED** — all three entries closed with
explicit supersession notes.

### P2 — `.claude/memory/feature_decisions.md` still carried the stale trial policy

Not among the dated records the doc said were deliberately left. **FIXED** with a
dated correction rather than a silent overwrite.

### P2 — the upsert path is guarded only transitively

`insertRow`/`upsertRow` take no guard; live upserts are safe today only because
`cleanup()` runs first in `setUp` and throws first. That is a property of current
file ordering, not of the write path. **ACCEPTED AS-IS, stated rather than
hidden**: the guard now also covers the one file that writes without deleting
(`ai_proxy_test`), and RLS independently bounds the blast radius (below). A future
`test/supabase/` file that upserts without a `cleanup()` in `setUp` would have no
boundary — worth knowing before writing one.

### P3 — scope: commit A bundled the free-tier doc correction

Deliberate and stated in the commit body: the drift nearly mis-planned the batch,
so it travelled with the work that surfaced it.

## The bound worth recording

Live `pg_policies` on all 12 cleanup tables: exactly one `DELETE`/`ALL` policy
each, **every one qualified by `auth.uid()`, none granted to `anon`**. So a
repointed credential can only ever delete its OWN rows — a credential change alone
cannot reach a third party's data. The worst outcome still reachable requires a
*code* change: adding a uuid to `qaUserIds`, or un-skipping
`integration_test/device/delete_account_patrol_test.dart` (currently `skip: true`,
body commented out), which hard-deletes `auth.users` and has no allow-list at all.
**The batch's thesis does not extend to that device surface** — recorded here
because it is the honest limit of what this change buys.

## Verdict

Four P1s: three fixed, one false alarm with the refutation recorded. Six P2s: five
fixed, one accepted with its residual stated. One P3 scope note, deliberate.
Nothing outstanding that would make the merge unsafe.

**verdict: accepted**
