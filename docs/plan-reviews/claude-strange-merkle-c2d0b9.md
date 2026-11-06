---
branch: claude/strange-merkle-c2d0b9
date: 2026-09-21
blast_radius: catastrophic
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/f81f7ae899e1-review.md
hermes: accepted
hermes_report: docs/audit/2026-09-21-hermes-observation-batch-and-digest-redesign.md
---

# Plan-review record — observation-batch-and-digest-redesign (catastrophic)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Catastrophic-tier because migrations 138 and 140 each define a `SECURITY DEFINER`
function (content rule in `scripts/blast_radius_content_rules_lib.dart`, forcing
the tier up from a path-glob-computed `platform`) — requiring both `bpass:
accepted` and `hermes: accepted` at this tier, not just one.

## Scope

Spec: `docs/superpowers/specs/2026-09-21-observation-batch-and-digest-redesign-design.md`.
Two parts:

- **Part A** — 8 independent founder-observation bug fixes: A1 (workout swap
  undo-snackbar dismissed by an unrelated completion event), A2a (AI coach
  chat rendering raw JSON instead of prose on a heuristic miss), A2b (9
  `geminiChat()` call sites with no retry on a transient empty candidate),
  A2c (chat history render-path channel filter), A3 (SyncCoalescer
  re-audit), A4 (AI coach chat not invalidating on background restore
  completion), A5 (Gemini exhaustion alert telemetry gap, OI-226), A7
  (support-contact-email drift).
- **Part B** — founder-digest redesign: 3 new metrics RPCs
  (`founder_metrics_for_admin_api`/`_ops`/`_engagement`), a
  privacy-respecting name lookup, MRR/cancelled/lapsed computation, migration
  138 (`subscriptions.cancelled_at` trigger) + migration 139
  (`alert_cron_failures` cron job).
- **Post-implementation hardening**: a self-triggered Hermes pass (required
  at catastrophic tier, §4.12) found 12 findings across 8 lenses in the
  Part A + Part B diff, including one (the `alert_cron_failures` unbounded
  stuck-window) already actively misfiring in production. All 12 fixed,
  including migration 140 (a new migration correcting live defects in the
  immutable 138/139). A B-pass (this record's own gate requirement) then ran
  in two rounds against the accumulated diff — see below.

## Review rounds

**Round 1 — spec pre-implementation, round 1 (both reviewers, independent,
context-blind).** Did not converge: Part A had blocking findings on 6 of 8
items (A1, A2a, A2c, A4, A5, the new mechanical gate); Part B had blocking
findings on 3 of 4 items (B2, B3, B4). All addressed in the hardened spec.

**Round 2 — spec pre-implementation, round 2 (both reviewers, independent,
context-blind, reviewing the round-1-hardened plan per §4.12 point 1).**
Part A converged after two narrow corrections (a gate site-count fix; A4's
prescribed mixin-adoption fix corrected to avoid a documented architectural
exclusion). Part B converged on 3 of 4 sub-items; B3 required a real
re-derivation (the round-1 fix, `pro_expired`, was found to be a
point-in-time cumulative total masquerading as a "yesterday" figure — worse
than the original bug). Per §4.12 point 1's own guidance and the round-2
reviewer's explicit recommendation, B3's replacement query was corrected
directly (verified live) rather than triggering a third full-batch round.
Full spec (Parts A + B) implementation-ready after this round. Full detail:
the spec's own "Review history and final convergence status" section.

**Round 3 — self-triggered Hermes pass (required at catastrophic tier),
post-implementation, over the full Part A + Part B diff.** 8 lenses, 8
agents, 12 findings (2 P0, 3 P1, 6 P2, 1 false_alarm) — including a P0
already live in production (the stuck-cron-alert false-positive misfire).
All 12 reached a terminal state: fixed in-batch (migration 140 + 3 more
diagnose-docs' worth of fixes across `founder_digest_content.ts`,
`gemini.ts`, `tool-loop.ts`, `rolling-context/index.ts`), 2 genuinely
pre-existing out-of-scope gaps filed as OI-238/OI-239 rather than
absorbed into scope. Full detail: `docs/audit/2026-09-21-hermes-observation-batch-and-digest-redesign.md`,
`verdict: accepted`.

**Round 4 — B-pass, two sub-rounds, over the accumulated diff (this
record's own gate requirement, self-triggered before the `--no-ff` merge
per §4.3 — not waited for).**

- *Round 4a* — 2 fresh context-blind reviewers, lenses split 1-5/6-8, over
  the diff as it stood immediately after Round 3's fixes. 3 findings (1 P0,
  2 P1), 0 false_alarm, all fixed in-batch:
  - P0 (guard_without_its_mirror): the new chat-history render-path channel
    filter reused a narrower sibling reader's allowlist verbatim, silently
    dropping 3 real, live proactive-message channels. Fixed via a denylist
    redesign (not the suggested allowlist widening, which a follow-up grep
    showed would likely have missed an 8th channel it also found).
  - P1 (guard_without_its_mirror): the new mechanical gate
    (`check_gemini_retry_and_telemetry_coverage.dart`) shipped to prevent
    regressions had the same defeatable-by-comment shape this repo already
    distrusts in hand-written guards. Fixed with comment-stripping + a
    "comment-out rather than delete" mutation test.
  - P1 (blast_radius_mismatch): `alert_cron_failures`'s 24h-lookback vs
    1h-dedup ratio was an alert-storm risk. Hand-tracing the suggested "pick
    better numbers" fix found it would trade the bug for a worse one (a
    permanently-invisible stuck job); fixed structurally with two
    independently-bounded branches instead.
  - Review: `docs/reviews/f81f7ae899e1-review.md` (renamed twice more after
    this sub-round for unrelated staging-hash reasons — see the file's own
    header for the full chain).
- *Round 4b* — 2 fresh context-blind reviewers, same split, explicitly
  targeted at the code Round 3 (the Hermes pass) had just added — none of
  which had had an independent pass yet, only the author's own
  mutation-proofs. 6 findings (1 P1, 2 P2, 3 P3), 0 false_alarm, 5 fixed
  in-batch, 1 accepted with no code fix:
  - P1 (guard_without_its_mirror): `geminiChatWithTools`'s per-attempt
    `console.warn` had no redaction of its own — only the inner
    `_callOnceWithTools` call's, one hop away. Mutation-proven: reverting
    the inner call left the raw key leaking into this log line while ALL 22
    pre-existing tests (including two written specifically to prove no
    leak) stayed green, because they all inspect only the final exhaustion
    message, which is redacted independently. Fixed with defense-in-depth
    redaction at the log site itself; a new test's 3-way mutation exactly
    reproduces the finding.
  - P2 (secrets_in_tree): two HTTP-error-body branches sliced to 200 chars
    BEFORE redacting, backwards from the file's other two branches — a key
    straddling the cut would leak a fragment. Fixed with 2 new
    boundary-straddling tests, mutation-proven (reverting reddens exactly
    those 2, with the actual leaked fragment visible in the failure
    output).
  - P3 (asserted_fixture_value): this same review file's own Round-1
    "lenses checked with no findings" section had verified a pre-Hermes-fix
    MRR value (₹3697) as "correct" — stale the moment the Hermes pass's
    ÷12-for-yearly-plans fix landed. Corrected in place with an explanatory
    note rather than silently rewritten.
  - P3 (blast_radius_mismatch): `alerts/_thresholds.yaml`'s `cron_failures`
    entry still said "no upper bound" after migration 140 added a 6-hour
    one. Fixed.
  - P3 (missing_input / test-coverage gap): migration 140 fixes two
    defects (a reactivation-clear and an INSERT-path stamp); the live-verify
    SQL only exercised the first. Fixed: added the missing case, re-ran all
    4 live against `dedsavbjuwgarrhphgnl` inside the same rolled-back
    transaction — all 4 `status='ok'`, zero residual rows.
  - P3 (blast_radius_mismatch, audit-trail): `applied_migrations.json`
    cites a review filename that no longer exists (renamed since).
    Accepted with no fix — the rename chain is fully documented in the
    review file's own header, and editing an "immutable" applied-migration
    ledger's prose for a citation-only issue was judged not worth the
    precedent.
  - Same review file, "Round 2" section (the file predates this record's
    own numbering — see the file itself for its internal round labels,
    which are offset by one from this record's Round 4a/4b split).

## Convergence

Four rounds, with material findings present through Round 4b but
progressively narrower in scope: Round 1 found architecture-level design
gaps; Round 2 found implementation-detail gaps in the hardened design;
Round 3 (Hermes) found cross-cutting defects across the shipped
implementation, including one live production issue; Round 4 (B-pass) found
completeness gaps specifically in the code Round 3 itself had just added —
each round's findings a strict subset in kind of what the previous round
could have found, converging on "the fix for round N's findings has its own
gaps" rather than surfacing new architectural problems. This is the
§4.12.1 convergence signal (findings narrowing in kind, not growing) rather
than the split signal (successive rounds surfacing new MATERIAL issues).

## Ground truth verified

Every finding across all four rounds was independently re-checked against
the actual repository or live-database state before being accepted or
fixed, never taken on a subagent's prose alone:

- Every B-pass finding's `verification:` command was re-run by the
  implementing session, not just read (grep counts, `sed` line ranges, live
  schema/function-definition checks via `backups/live_schema_columns.json`
  and direct `pg_get_functiondef`-style reads).
- The Hermes pass's stuck-cron-alert P0 was confirmed against real,
  pre-existing `cron_call_log` rows (two rows from a 2026-09-19 crash,
  still `'started'` 2.5 days later) and a real, already-fired
  `public.alerts` row — not a hypothetical.
- Migration 140's fix was verified live, twice: once for its original 3
  cases (all `status='ok'`), and again after Round 4b's Finding 6 added a
  4th case for the previously-untested INSERT path — all 4 `status='ok'`,
  with a separate post-run query confirming zero residual synthetic rows
  both times.
- Every mutation-proof cited in this record was actually executed by the
  implementing session (not merely described): the redact-before-slice
  fix, the console.warn defense-in-depth fix, and the channel-filter
  denylist fix were each reverted, observed RED with the actual failure
  output inspected (not just the pass/fail count), then restored and
  re-observed GREEN.
- `deno check --node-modules-dir=none` run clean on every touched Edge
  Function after every round; `flutter analyze` clean on every touched
  Dart file; the documented `node_modules/pg` auto-mode corruption was hit
  and recovered per the established procedure, confirmed via
  `git status --porcelain node_modules/` each time.

## Verification

- 12 Hermes-pass findings + 9 B-pass findings (3 Round 4a + 6 Round 4b) all
  reached a terminal state: fixed-in-batch (19), accepted-no-fix-needed
  with recorded reasoning (1), or filed as tracked OIs for genuinely
  pre-existing out-of-scope gaps (2 — OI-238, OI-239).
- `docs/audit/2026-09-21-hermes-observation-batch-and-digest-redesign.md` —
  `verdict: accepted`.
- `docs/reviews/f81f7ae899e1-review.md` — `verdict: accepted`, both
  sub-rounds, all 9 findings terminal.
- 10 new/amended diagnose-docs, all passing
  `dart run scripts/validate_diagnose_doc.dart`.
- Migration 140 applied live to `dedsavbjuwgarrhphgnl` with explicit
  founder authorization (separate from the broader batch-level "commit push
  merge" instruction, per §4.3's live-apply rule), recorded in
  `backups/applied_migrations.json`.
- `check_code_review_pass_exists.dart` and `check_skill_tuning_history.dart`
  both PASS against the final staged tree.

## Residual, stated rather than hidden

- **OI-238** (5 Gemini-calling Edge Functions with no server-side
  `reportGeminiExhaustion` telemetry) — filed, tracked, genuinely
  pre-existing and out of this batch's scope.
- **OI-239** (acknowledging an alert re-arms its dedup window instead of
  waiting out the original interval — a systemic property of all 6
  `alert_*` cron jobs) — filed, tracked, pre-existing.
- **`applied_migrations.json`'s stale review-filename citation** (Round 4b
  Finding 4) — accepted as a permanent, harmless artifact of the
  hash-fixed-point renaming this file's own history documents; not worth
  editing an immutable ledger's prose for.
