# FOB-3 — the coach's hold block, and OI-132's fileless migration · 2026-08-21

Branch `claude/oi-pending-hold-weeks-1od97o` · diagnoses `b6e1f4` (FOB-3) + `c8e5b3` (OI-132)
Closures `docs/audit/fob3-coach-hold-block.closure.yaml` (10/10 terminal) +
`docs/audit/oi132-cron-registry.closure.yaml` (9/9) · both B-passes accepted.

## How this stretch started

`main` was RED. The previous batch's merge (`1eb016c`) failed CI run #335 on the
keystone gate: the Hermes report it cited carried `verdict: pending` with
`<pending>` triage sections, and the gate refuses a record whose report does not
contain a line-anchored `verdict: accepted` — "Fabricated acceptance is not
allowed". The fix was to genuinely close the report out (a triage table mapping
all 24 findings to terminal states with shas or named blockers), not to flip the
string. Run #336 on `3e91d6e`: all 7 jobs green.

## Three things worth carrying forward

**1. The fix for a blind spot reintroduced the blind spot, ten lines below the
comment explaining why it must not.** Gate 31 enforced cron-registry parity by
SCANNING `supabase/migrations/*.sql`, so a migration applied without a file was
not merely un-gated but *unseeable* — 28 live jobs, 24 registered, and the 4
missing were exactly the fileless migration's. The re-scope added a committed
snapshot of live `cron.job` as a second, file-independent input. It placed that
read BELOW input A's `migrations dir absent -> exit(0)`, so a tree without that
directory exits green having consulted NEITHER input. Six tests written with the
re-scope could not see it: `setUp` unconditionally created the directory. Caught
by the B-pass, not by the tests. **The general shape: when you add input B to
close a hole in input A, check every early exit that now sits above B.**

**2. A test can be green because something ELSE absorbed the mutation.** New
debugging-skill entry §2.41. `'hold'` was added to `trimSnapshotToBudget`'s keep
set with a test that bloated the snapshot and asserted the block came back
whole. Dropping `'hold'` from the keep set reddened NOTHING — the trimmer shrinks
the LARGEST non-kept field each pass, so the two giant bloat fields the test used
absorbed the whole overage and the 110-char block was never reached. The test
exercised the trimmer; it never exercised the line it was written for. Fixed by
making the KEPT fields alone exceed the budget, so the loop has nothing else to
take. **Corollary: "N tests redden" is only meaningful if you RAN it.** Reasoning
about a mutation cannot tell you it was absorbed.

**3. Prose about a data key, inside a template literal, is a boot failure.** New
deploy-skill entry §6.8. The HOLD WEEKS section refers to `snapshot.hold`,
`hold.label`, `hold.is_deload` — 20 backticks, unescaped, inside
`export const CAPTAIN_MANUAL = ` + backtick. That terminates the literal at line
126 and stops the module parsing, and per §6.5 it does not fail loudly: ai-proxy
503s at boot while the old bundle keeps serving. Found by reading the file's own
existing escapes at 403-410. Verified by extracting the declaration and parsing
it with node — 19831 chars, closing backtick at line 412 — because Deno cannot be
installed here (the proxy 403s deno.land).

## Two smaller ones

**A literal `sha256:%s` passed Gate 39**, inside the very manifest note
explaining that 60 of 126 ledger hashes already match nothing and that this entry
must not become the 61st. The gate's `_requiredKeys` asserts the four keys EXIST
and never looks at a value. Filed OI-137 with a separable step 1 (`^sha256:[0-9a-f]{64}$`
or a documented sentinel) that blocks nothing.

**The seam inlined a second `'H$ordinal'`** beside `hold_week_labels.dart`,
which exists *because* inlined hold-label logic drifts — its own header records a
B-pass inverting an inlined ternary while all 16 tests stayed green. Added
`holdIdentityLabel()` and composed all NINE sites, not seven with two named for
later.

## What FOB-4 turned out to be

Its ledger `why:` says it needs "a hold branch — which means redeploys". Measured
live: schema `public` holds ZERO columns matching `%hold%`, `user_progress` has no
hold field of any spelling, and there is no `workout_schedule` table in `public`
at all — `is_hold` is written onto LOCAL rows and never crosses the wire. So
`weekly-recap-ready` and `weekly-report` cannot branch on a hold whatever is
deployed to them. FOB-4 needs a MIGRATION and its own live-apply authorization
first. Recorded on OI-60 so it is not rediscovered mid-batch.

## Honest note on review depth

Both units on this stretch (OI-132, FOB-3) got a self-driven B-pass and ZERO
independent context-blind rounds. FOB-3 qualifies for §4.12.4's `ship_dark_build`
tier, which permits 1 round — so it is one short even of the lighter tier. That
is recorded in the plan-review record's per-unit table rather than rounded up to
the branch's high-water mark. The full ×2 is required again on the flip-on
commit, which must clear all FOUR `enable_hold_weeks` ledger rows at once.
