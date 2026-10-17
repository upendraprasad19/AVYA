---
branch: oi79-paged-cron-reads
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/337bf6eb-review.md
hermes_report: not_required
---

# Plan review — oi79-paged-cron-reads (OI-79)

Commits: `cda5b62c` → `017014f1` → `337bf6eb`. Blast radius measured **platform**
(`git diff --name-only d229c012..HEAD | dart run scripts/blast_radius_from_diff.dart -`; the
trailing `-` is load-bearing — without it the script reads `git diff --cached`, which is empty
after committing, and prints nothing. That footgun cost three separate wrong readings this batch,
two mine and one the B-pass reviewer's).

Hermes is `not_required`: catastrophic-tier only, and this is platform.

## Ground truth

Every load-bearing claim was measured, not inferred.

- **The bug, live.** A bare `?select=id` on `food_database` returns **HTTP 200**, `Content-Range:
  0-999/*`, 1000 rows, `error === null`. Not a 206 — that needs `Prefer: count=exact`, which
  supabase-js does not send. OI-79's own text said 206; corrected in its closure.
- **`.range()` cannot raise the cap** (`Range: 0-1499` still yields 1000), and
  `pg_db_role_setting` has no `pgrst.db_max_rows` row, so `service_role` — what every cron uses —
  is capped like everyone else.
- **Sort keys.** Every paging key checked against live `pg_index`. `coach_memory` has **no `id`
  column** (PK is `user_id`); assuming `id` would have thrown 42703 at runtime.
- **`uq_scheduled_workouts_user_date`** UNIQUE(user_id, scheduled_date) confirmed via `pg_index`
  before a waiver was allowed to rest on the 1-row-per-user-per-day premise.
- **Nothing truncates today** — 18 users, largest per-user table 565 rows. A latent correctness
  fix landed before growth, not an outage. Stated so the closure does not overclaim.
- **End-to-end behavioral proof** against live PostgREST: bare read 1000 / `error===null` vs
  `fetchAllPages` 1431 = exact `count: exact` server count, no duplicate ids across page
  boundaries. This closed a real gap — the Deno tests run against a *fake* builder and prove the
  loop's arithmetic, never that the helper recovers rows through real supabase-js.

## Round 1 — two parallel context-blind reviewers

9 REAL findings. Every one verified against the file or live DB before acting; one reviewer claim
was over-stated and is corrected below.

Two would have hurt users, and both were mine:

1. **`new Date()` inside the per-page closure** (3 sites). The closure re-runs per page, so each
   page was offset into a *different* result set — a subscription expiring mid-scan shifts later
   rows down one and the boundary row is never returned. That drops a **paying user from a PRO
   inclusion set**: the Class-1 silently-wrong outcome this batch exists to remove, re-entered
   through the predicate instead of the sort key.
2. **The loop assumed the server cap equals my constant.** `db-max-rows` is a dashboard setting;
   at 500, page 0 returns 500, reads as end-of-data, and every converted read silently returns
   half its rows with `error === null`. Now advances by rows *received* and terminates only on an
   empty page — correct at any cap.

Three proven gate bypasses (read in the helper's 2nd argument; `//` inside `https://`; a paren
inside a string) plus the `.range()`-without-`.order()` blind spot and two doc/waiver errors.

**Corrected a reviewer claim:** only ONE of three "stale" `snapshot_contract.yaml` citations was
genuinely undetected; the other two sat inside the ±15 tolerance and passed legitimately.

## Round 2 — on the hardened diff

Ran against the round-1 *fixes*, per §4.12. **All 5 findings were defects my corrections
introduced** — the rule justifying itself:

- My string-skip fix had no **regex-literal** awareness, so `/'/g` reopened the identical
  runaway-chain bug. Third token class to defeat that scanner (comments → strings → regexes), so
  it now **fails closed** past 4000 chars instead of being patched again.
- The new `.range()` branch emitted before the shared waiver check, making the documented
  `oi79-ok` hatch inoperative for that one class.
- Stale docs from the loop rewrite, including `validate()`'s live throw text.
- The cost claim was wrong for the dominant path (per-chunk, not per-read).
- **Roster gap:** deriving from `CRON_REGISTRY.md` alone meant `weekly-recalc` was never scanned —
  and my own round-1 comment had claimed the new rule covered it. Roster is now registry ∪
  cron-shaped (importing `_shared/cron_auth.ts`).

That roster fix immediately found a **21st real bug**: `weekly-recalc:326` read `user_progress`
with no `error` destructure, so a failed read left the comparison map empty and the `GREATEST`
guard had nothing to compare — silently re-opening diagnose `3a7b9f` (every user's LIFETIME
`total_workouts_done` overwritten by a 4-week count each Sunday).

Two further defects found by my own instrumentation, not a reviewer: the waiver tally was
unauditable, so the gate now prints each waived **site** — which exposed that the roster union
de-duplicated on the raw path string while its two branches build `/` and `\` paths, scanning
files twice (55→39 files, waived 8→5, now exactly matching the 5 markers).

## B-pass

`docs/reviews/337bf6eb-review.md`. All 5 lenses clean, **zero P0/P1**, 2 P2s. It independently
re-derived 316 Deno tests, 39 files / 5 waivers, 41/41 ledger entries, and four line citations.

- **P2-1 accepted and fixed:** tier 6's status was `pending_explicit_authorization`, outside
  CLAUDE.md §6's enum. `not_applicable` would be false and `deferred` both false and a banned
  semantic, so it now states the verified delta.
- **P2-2 resolved, not a defect:** the reviewer could not re-derive the blast radius because it
  omitted the stdin form's trailing `-` — the same footgun noted above. Re-run correctly:
  `platform`.

Chasing P2-1 produced a **material deploy-scope correction**: the set is **16**, not the 15 I had
been stating — the 15 changed directories plus `proactive-coach-promotion`, which changes no file
of its own but imports the genuinely-changed `notification_prefs.ts`. `ai-proxy` is deliberately
**excluded**: its only changed dependency is `memory_retrieval.ts`, whose whole diff is three
comment lines.

## Convergence

Round 2's findings were entirely *self-inflicted-by-round-1*, not new defects in the underlying
paging work, and the B-pass found no correctness issue at all. That is convergence, not a signal
to split (§4.12): the shipped read-paging logic has been stable since `cda5b62c` — what kept
moving was the gate's precision and the prose around it.

**Verdict: converged.** 41/41 ledger entries terminal, both gates green, 316 Deno tests, live
end-to-end proof green, negative controls re-verified after every gate change.

## Not fixed here, filed instead

- **OI-80** — `check_snapshot_contract` silently skips one reader citation while counting it.
  Measured (`line: 700` passes; the same mutation one entry below correctly fails). Cause **not
  diagnosed**; my leading-comment theory was tested and refuted.
- **OI-81** — ~10 per-user reads still destructure `data` without `error` in 4 cron functions.
  Correctly bounded; the defect is error handling, and abort-vs-skip is a per-site judgement.
- **OI-82** — `promote-community-item` calls `community_votes_summary`, absent from `pg_proc` in
  every schema, so its primary vote-summary path has never executed.
