---
reviewed_at: 2026-09-11T17:27:06+05:30
staged_against: 3cd1891ee7eb  # RENAMED FOUR TIMES: 12408db06b47 (original dispatch) -> 1486254681fb (after the 4 findings were fixed) -> 016af81ca391 (after the Hermes-pass remediation) -> 42ed72d24303 (after every prose citation TO this file was made hash-independent, because each citation fix moved the hash it cited) -> 3cd1891ee7eb (the pre-commit hook regenerates OPEN_INDEX.md from the board, so a direct gate run against a stale index reports a hash the hook then moves — compute the hash AFTER the hook, not before; see the code-review SKILL.md 2026-09-11 second entry). The plan-review record lands in a separate follow-on commit for the same reason.
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
# ^ all 4 findings triaged accepted and fixed in this same batch — see per-finding status + "Post-dispatch remediation" below. Kept on its own line: check_plan_review_record_exists.dart's anti-fabrication check matches `^verdict:\s*accepted\s*$` LINE-ANCHORED, so a trailing comment on the verdict line itself would fail the merge-to-main gate in CI.
---

# Code Review — 12408db06b47 (OI-162 slice 4, diagnose f2c8d5)

## Note — repo state changed concurrently with this review

Partway through this pass, `backups/applied_migrations.json` (staged, not
part of the original 18-file diff this review was dispatched against) began
recording migration 130 as **applied to prod at 2026-09-11T17:32:05+05:30**,
applier `founder-via-management-api`, with a note stating the agent's own
raw-curl DDL attempt was correctly classifier-blocked and the founder then
ran the reviewed SQL directly. The diagnose-doc (`docs/diagnoses/2026-09-11-
windowed-rate-limits-inert-and-quota-acl-gap-f2c8d5.md`) was, at that same
moment, updated in every place that mattered — tiers 3/4/5 of
`touched_layers_checked` and the "What is NOT proven" section (which now
reads `~~Migration 130 has not been applied.~~ **RESOLVED
2026-09-11T17:32:05+05:30.**`) — and I re-read it fresh rather than trusting
my earlier cached read once I noticed the ledger change. I checked every
place both documents make this claim; as of this review's final version
they are mutually consistent and I found no residual stale copy. Noted here
because it is exactly the shape of thing this skill's own history flags as
high-value (a document's claim contradicted by sibling repo state) — this
instance resolved itself before I finalized rather than needing a finding.
**I have not independently re-verified the post-apply live ACL myself** —
my own Supabase MCP access was unauthorized throughout this review (see
below) — so that specific claim rests on the ledger/diagnose-doc's own
self-report, at the same epistemic status as every other live-state claim
in this review I could not query directly. Findings 3 and 4 below, about
migration 130's rollback wording and forward-looking signature-change risk,
are unaffected by apply status either way — they are about the migration's
design, not its deployment state.

Dispatched as a fresh context-blind reviewer per `.claude/skills/code-review/SKILL.md`.
Verification performed: full read of both Edge Function diffs and their post-diff
full files; read of migrations 128/129/130 in full; full read of the two new
contract tests plus an independent live run of both (13/13 green); one
independent mutation not in the diagnose-doc's own mutation table
(`RATE_LIMIT_MAX` 5→6 in `delete-account/index.ts`), executed, confirmed it
reddens exactly 1/6 assertions, then restored and re-verified clean via
`git status --porcelain` + a second green test run; grep of the full staged
diff for secrets and `unawaited(`; grep of the whole `lib/` tree for every
client-side write to `ai_coach_interactions` and for any client read of
`Retry-After`/`retry_after_seconds`; read of `docs/blast_radius.yaml` and
`scripts/check_plan_review_record_exists.dart` in full to verify the
catastrophic-tier requirement precisely; directory listing of
`docs/plan-reviews/` (153 files, none matching this branch). Live Supabase
MCP access was attempted (to independently re-verify `pg_proc.proacl`,
`pg_policies` on `usage_counters`, and `pg_roles.rolbypassrls`) but the token
had expired (`MCP server "claude.ai Supabase" requires re-authorization`), so
those specific live-state claims are verified only by re-deriving them from
migrations 128/129's own text and from the actual client/EF code that would
be affected by them — noted per-claim below, not silently upgraded to
"confirmed live."

## Finding 1 — P1 — blast_radius_mismatch
- **file:line:** (missing artifact) `docs/plan-reviews/oi162-slice4-windowed-counters.md`
- **claim:** This branch is declared `blast_radius: catastrophic` — correctly:
  `docs/blast_radius.yaml:42-43` independently pins BOTH
  `supabase/functions/verify-payment/**` and `supabase/functions/delete-account/**`
  to `catastrophic`. The keystone merge gate
  `scripts/check_plan_review_record_exists.dart:836-837` requires, at that
  tier, `field('hermes') != 'accepted'` to FAIL the build — i.e. a converged
  `docs/plan-reviews/<branch>.md` record with `hermes: accepted`, on top of
  `review_rounds >= 2`, `ground_truth_verified: true`, `verdict: converged`
  and `bpass: accepted` (required from `platform` up, `:832-835`). The same
  gate additionally anti-fabrication-checks (`:840-844`) that an
  `hermes: accepted` claim names a real `hermes_report:` file under
  `docs/audit/` that itself carries `verdict: accepted`.
  **None of this exists.** `docs/plan-reviews/` has 153 files; none is named
  `oi162-slice4-windowed-counters.md` (`recordSlug()` on this branch name is
  the identity map — no `/`, no `origin/` prefix — so there is no naming
  ambiguity to explain the absence). The staged diff (`git diff --cached
  --name-only`) adds no file under `docs/plan-reviews/` at all. The batch DID
  do real review work — `docs/audit/oi162-slice4-plan.md` documents round 1
  (8 findings, scope-changed to add Unit C) and
  `docs/audit/oi162-slice4-review-continuity.md` documents round 2's
  decision not to split — but neither file opens with a `---` YAML
  frontmatter block (both start with a bare `# ` Markdown H1), so neither
  would satisfy the gate's `_frontmatter()` parser even if moved to the
  right directory. I found zero evidence anywhere in the diff, in
  `docs/audit/`, or in `docs/reviews/` of a Hermes pass (`/hermes-pass`)
  having been run against this branch at all.
  **Consequence:** a `--no-ff` merge of this branch to `main` will fail CI's
  keystone gate. Per CLAUDE.md §4.3 this review is meant to run BEFORE that
  merge — this is the moment to catch it, not after.
- **verification:** `ls docs/plan-reviews/ | grep -i "slice4\|windowed"` →
  empty. `git diff --cached --name-only | grep plan-review` → empty.
  `sed -n '1p' docs/audit/oi162-slice4-plan.md` → `# OI-162 slice 4 — …`
  (not `---`). `grep -rn hermes docs/reviews/ docs/audit/ | grep -i
  "slice4\|f2c8d5\|windowed"` → empty.
- **suggested-fix:** Before merging: (1) write
  `docs/plan-reviews/oi162-slice4-windowed-counters.md` with the required
  frontmatter (`review_rounds: 2`, `ground_truth_verified: true`,
  `verdict: converged`, `bpass: accepted` — this review, once triaged, can
  serve as that — and `hermes: accepted` backed by an actual
  `hermes_report:` file under `docs/audit/` with `verdict: accepted`); (2)
  actually run `/hermes-pass` against this branch if it has not been run,
  since nothing else in the repo currently attests that it has.
- **status:** accepted. `/hermes-pass` and the plan-review record are the
  NEXT steps after this review lands (not yet done as of this edit) — see
  "Post-dispatch remediation" below for exactly what state this leaves.

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** `supabase/migrations/129_cap_triggers_use_usage_counters.sql:142-168`
  (`enforce_vision_analysis_daily_limit`, unchanged by this diff); discovered
  in `docs/audit/oi162-slice4-channel-enumeration.md:66-73` ("Defect found
  during the enumeration")
- **claim:** The two chat/food-text triggers guard their early-return with
  `IS DISTINCT FROM` (NULL-safe: a NULL `channel` correctly takes the
  early-return path). `enforce_vision_analysis_daily_limit` instead guards
  with `IF NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN RETURN NEW;`
  — and `NULL NOT IN (...)` evaluates to NULL, not TRUE, in Postgres, so a
  NULL-channel insert does **not** take the early return and falls through
  to `consume_quota('vision_analysis', ...)`, which could raise
  `vision_analysis_daily_limit_reached` for a row that was never a vision
  request. This batch's own channel-enumeration artifact found this,
  correctly labelled it "Class: guard_without_its_mirror", and correctly
  assessed it as dormant (the column is nullable but nothing today writes
  NULL) and out of this batch's scope. What it did NOT do is give it an OI
  number — contrast with the sibling out-of-scope discovery from the same
  review round (the payment-grace-window mismatch), which WAS filed as
  **OI-182** with full `Status`/`Blocked on`/`Verified`/`Related` fields in
  `docs/audit/open_issues.md`. The vision-analysis NULL gap has no such
  entry anywhere I could find, so it is invisible to `OPEN_INDEX.md` — the
  file every session is told to read first — and is at risk of being lost
  exactly the way the board itself once was ("70 days unread because nothing
  referenced it").
- **verification:** `grep -n "vision_analysis\|NULL" docs/audit/open_issues.md`
  → no matching OI entry (only OI-182, about the grace window, was added by
  this diff). `grep -c "OI-" docs/audit/oi162-slice4-channel-enumeration.md`
  → 4 hits, none minting a new number for this specific defect.
- **suggested-fix:** File it as its own OI (same shape as OI-182: `Status:
  OPEN`, `Blocked on: none — one-line NULL-safe rewrite`, `Verified: 2026-09-11`,
  `Related: OI-162`), in the same commit, for the same reason OI-182 was —
  a dormant defect discovered during this batch's own investigation and
  explicitly deferred should not depend on someone re-reading this prose
  audit file to be rediscovered.
- **status:** accepted — fixed. Filed as OI-183 in `docs/audit/open_issues.md`
  with the same Status/Blocked-on/Verified/Related shape as OI-182, and
  `OPEN_INDEX.md` regenerated (99 open issues). Verified the underlying claim
  independently before filing: read the live trigger body directly (confirmed
  the exact `NOT IN` vs `IS DISTINCT FROM` asymmetry against the other two
  triggers), and queried live state (`channel` is nullable,
  `is_nullable='YES'`; 0 rows currently hold NULL) — dormant, not active.

## Finding 3 — P3 — asserted_fixture_value (documentation precision)
- **file:line:** `supabase/migrations/130_consume_quota_revoke_public_execute.sql:46-49`
- **claim:** The commented-out rollback block says: *"Re-granting EXECUTE to
  PUBLIC restores the pre-migration ACL exactly (nothing else in this
  migration is destructive or has a side effect to unwind)."* The migration's
  OWN header (lines 27-29) documents the live pre-migration ACL as FIVE
  distinct entries: `=X/postgres` (PUBLIC), `postgres=X`, `anon=X`,
  `authenticated=X`, `service_role=X` — i.e. `anon` and `authenticated` each
  hold their own **direct, named** grant, separate from the PUBLIC one.
  Running only `GRANT EXECUTE ... TO PUBLIC;` as the rollback restores the
  bare PUBLIC entry, but does NOT restore the separate `anon=X` /
  `authenticated=X` entries — the ACL after rollback would be `postgres=X,
  service_role=X, =X(PUBLIC)`, not the original five-entry set. This is
  functionally equivalent for every consumer that checks
  `has_function_privilege()` (PUBLIC-inherited access reads identically to a
  direct grant), so the rollback is SAFE — but "restores the ACL exactly" is
  a stronger, and not quite accurate, claim than "restores the same
  effective privilege."
- **verification:** Compare the migration's own header ACL dump (5 entries,
  including 2 named non-PUBLIC grantees for anon/authenticated) against what
  `REVOKE ... FROM PUBLIC, anon, authenticated; GRANT ... TO service_role;`
  followed by `GRANT ... TO PUBLIC;` actually produces (3 entries: postgres,
  service_role, PUBLIC) — the entry count and grantee identities differ even
  though the resulting *privilege* set does not.
- **suggested-fix:** Reword to "restores the pre-migration EFFECTIVE
  privilege (anon/authenticated regain EXECUTE via PUBLIC-inheritance,
  though not as separately-named grants)" — or, if literal restoration ever
  matters, have the rollback re-run the two explicit GRANTs too. Low
  priority: this is a comment on a rollback path that is not being executed
  in this batch.
- **status:** accepted — fixed, but NOT by editing migration 130. Between
  this review's dispatch and triage, migration 130 was founder-approved and
  applied to prod (2026-09-11T17:32:05+05:30, `backups/applied_migrations.json`).
  `supabase/migrations/CLAUDE.md`'s own immutability rule (an applied
  migration's file — including comments — must never be edited, because the
  ledger's hash is pinned to the file as-applied) makes the suggested reword
  unsafe now. Corrected instead in the diagnose-doc under "Known
  documentation imprecision", per that same CLAUDE.md section's own guidance
  for exactly this case ("where a correction goes instead: the diagnose-doc").

## Finding 4 — P3 — missing_input (forward-looking robustness gap)
- **file:line:** `supabase/migrations/130_consume_quota_revoke_public_execute.sql`
  (whole file); `supabase/migrations/128_usage_counters.sql:69-73`
  (`consume_quota` signature)
- **claim:** `CREATE OR REPLACE FUNCTION` preserves an existing function's
  ACL (grants/revokes survive a body-only replace), so migration 130's
  REVOKE is durable against any future migration that only edits
  `consume_quota`'s BODY. It is NOT durable against a future migration that
  changes its SIGNATURE (adds/removes/retypes a parameter) — Postgres
  requires `DROP FUNCTION` + `CREATE FUNCTION` for that, and a freshly
  created function gets the schema's default-privilege grants again
  (per migration 128's own comment, that default already includes
  anon/authenticated), silently re-opening exactly the gap this migration
  closes. Nothing in the migration, in `supabase/migrations/CLAUDE.md`, or
  in any gate checks for this — `supabase/migrations/CLAUDE.md` already
  carries one closely-related pitfall ("`public` SECURITY DEFINER function
  is anon-executable despite `REVOKE ALL FROM PUBLIC`" / "RECURRED
  2026-08-26") but that entry is about the grant never having been removed
  in the first place, not about a later signature change silently
  re-introducing a grant that WAS correctly removed.
- **verification:** No live check performed (this is a claim about future
  migrations, not the current one); reasoning follows directly from
  Postgres's documented `CREATE OR REPLACE FUNCTION` semantics (ACL
  preserved) versus `DROP`+`CREATE` (ACL reset to schema defaults) and from
  migration 128's own text describing those schema defaults as including
  anon/authenticated.
- **suggested-fix:** Add a short pitfall row to `supabase/migrations/CLAUDE.md`
  (alongside the existing REVOKE-FROM-PUBLIC-not-role entry) noting that a
  future signature change to a function whose ACL was deliberately narrowed
  needs its narrowing re-applied in the same migration, and that the
  live-ACL check (`has_function_privilege`) is the only thing that would
  catch a silent regression. Not a blocker for this batch — no migration
  here changes `consume_quota`'s signature.
- **status:** accepted — fixed. Added as a new pitfall-table row in
  `supabase/migrations/CLAUDE.md`, alongside the existing
  REVOKE-from-PUBLIC-not-role sibling entry, citing this review by path.

## Addendum — a gate self-reference this dispatch triggered (not a batch defect)

Per §5.1, adding this review file requires a same-dated entry in
`.claude/skills/code-review/SKILL.md`'s Tuning history in the SAME commit —
done (see that file). Staging it is necessary but has a side effect worth
flagging explicitly rather than leaving for someone to discover at commit
time: `scripts/check_code_review_pass_exists.dart` computes its
catastrophic-tier hash from `git diff --cached` over EVERYTHING except
`docs/reviews/` — it does **not** exclude `.claude/skills/code-review/
SKILL.md`. So staging the required tuning entry moves the hash. Confirmed by
actually running the gate against the current staged state (18 batch files +
this review + the SKILL.md tuning entry):
`[Gate] FAIL: blast-radius=catastrophic requires a STAGED review file at
docs/reviews/0c077bc09fa2-review.md` (exit 1) — NOT `12408db06b47`, the hash
this review was dispatched against and is deliberately still named after per
the dispatch instruction not to recompute it.
**This has no clean iterative fix**: renaming this file to
`0c077bc09fa2-review.md` and fixing the one filename reference inside the
SKILL.md entry to match would itself change SKILL.md's bytes again, moving
the hash to a fourth value, and so on indefinitely — `check_skill_tuning_
history.dart`'s own check is satisfied by mere string-containment of
whatever the review is ACTUALLY named (verified: it does not recompute any
hash), but `check_code_review_pass_exists.dart`'s IS a strict recomputed
match, so the two gates cannot both be satisfied by iterating rename→edit
cycles. The durable fix is structural: exclude `.claude/skills/code-review/
SKILL.md` from `check_code_review_pass_exists.dart`'s hashed pathspec the
same way `docs/reviews/` already is, for the identical self-reference
reason. That is a change to shared gate tooling, out of scope for me to make
unilaterally inside a code-review dispatch — flagging it here (and to the
dispatcher) rather than silently leaving whoever runs the real commit to
discover a `[Gate] FAIL` with no explanation of why the printed hash doesn't
match this file's name. Whoever lands this commit will need to either widen
that gate's exclusion first, or do the rename by hand at the single moment
all content is truly final and accept that as the last edit (no further
SKILL.md changes after it).

## Post-dispatch remediation (all done AFTER this review was dispatched)

The dispatcher (not this reviewer) triaged and fixed all 4 findings, then
renamed this file from its dispatch-time name (`12408db06b47-review.md`) to
match the hash the batch's growth produced:

1. **The Addendum's own recommendation was taken.** `stagedDiffHash()` in
   `scripts/check_code_review_pass_exists.dart` now excludes
   `.claude/skills/code-review/SKILL.md` from its hash the same way it
   already excluded `docs/reviews/`, closing the exact infinite-rename loop
   this Addendum describes. A new test
   (`test/contracts/review_gate_staged_content_not_working_tree_test.dart`,
   "staging the §5.1-required SKILL.md tuning entry alongside the review
   does not move the demanded hash") proves it — mutation-run: reverting the
   exclusion reddens exactly that one test, nothing else, confirmed by
   restoring and re-running clean (6/6).
2. **Finding 1's real ask (this review's own P1) is now done.** `/hermes-pass`
   was dispatched (9 lenses: L1, L2, L14, L21, L22, L23, L29, L35, L40) and
   its consolidated report landed at
   `docs/audit/2026-09-11-hermes-oi162-slice4-windowed-counters.md`;
   `docs/plan-reviews/oi162-slice4-windowed-counters.md` was written and
   records both plan-review rounds, this B-pass, and the Hermes pass.
3. **Finding 2** → filed as OI-183 (see that finding's updated status).
4. **Finding 3** → NOT fixed in the migration file (it is now immutable,
   applied to prod); corrected in the diagnose-doc instead.
5. **Finding 4** → added as a new pitfall-table row in
   `supabase/migrations/CLAUDE.md`.

This section is written by the dispatcher, not the original context-blind
reviewer — flagged as such rather than blended into the reviewer's own
voice, so a future reader can tell which claims were independently verified
by a fresh reader and which are the dispatcher's own account of its fixes.

## Second post-dispatch remediation round (after the Hermes pass, same dispatcher)

The Hermes pass (9 lenses) found 16 further items across the batch as it
stood after the first remediation round above. All 16 reached a terminal
state in this same batch — none deferred. Full per-finding detail lives in
`docs/audit/2026-09-11-hermes-oi162-slice4-windowed-counters.md`; the
highlights, because they are what moved this file's hash a second time:

- Both new rate-limit contract tests were hardened from membership to
  ASSOCIATION on `p_window_start`/`p_user_id` (this B-pass's own
  `asserted_fixture_value` check above ran the tests and mutated
  `RATE_LIMIT_MAX`, but never mutated `p_window_start`/`p_user_id`
  themselves — the exact gap the Hermes pass's L1 lens then found and this
  round closed, mutation-proven on all 4 legs).
- `usage_counters_rls_denies_client_test.dart` — a live-prod CI test
  independent of this diff — had a discriminator that degenerated to a
  tautology once migration 130 shipped (found independently by two lenses,
  L22 and L35); rewritten and live-verified via two read-only
  `BEGIN…ROLLBACK` probes rather than assumed.
- One systemic, pre-existing, out-of-scope finding (4 tables relying on
  RLS-zero-policy default-deny with their raw grants never narrowed) was
  filed as **OI-184** rather than fixed here, sized as its own unit per the
  OI-153 precedent.
- A client-side 429 handler gap, a verify-payment defense-in-depth
  hardening, an observability gap, and several documentation-precision
  fixes rounded out the remaining 12 — see the Hermes report for the full
  list and disposition of each.

## Lens coverage — clean / not-applicable, with what was checked

- **writer_reader_drift** — Extensively checked, clean. Traced the writer
  (`consume_quota()` RPC call, both EFs) to its only readers (the same
  handler's own `usedCount`/`rateErr` branches — no separate advisory read
  exists for either new concept, matching `docs/sot_registry.yaml`'s new
  `delete_account_rate_limit` / `verify_payment_rate_limit` entries exactly).
  Independently re-derived migration 130's central safety claim — that
  revoking `anon`/`authenticated` EXECUTE cannot break the three live cap
  triggers — by reading migration 129's trigger bodies (all three are
  `SECURITY INVOKER`, safe only because every gated-channel writer is a
  service-role Edge Function) AND by grepping the **entire** `lib/` tree for
  every client-side write to `ai_coach_interactions`
  (`grep -rn "ai_coach_interactions" lib/`): exactly two call sites write
  directly (`sync_coach.dart:149` → `channel: 'in_app_orphan'`,
  `app_events_service.dart:60-63` → `channel: 'app_event'`), and both values
  are excluded by all three triggers' early-return guards (confirmed by
  reading the guards directly) — so no client path reaches `consume_quota`
  under a role migration 130 revokes. This matches the migration's and the
  diagnose-doc's own claim, independently reproduced rather than trusted.
- **function_exception_swallow** — N/A / clean. This diff touches no
  `.functions.invoke(` client call site. Independently verified the
  diagnose-doc's own claim that no client reads the changed `Retry-After` /
  `retry_after_seconds` values: `grep -rn "retry_after_seconds|Retry-After|
  retryAfter" lib/ --include="*.dart"` → zero hits.
- **secrets_in_tree** — Clean. `git diff --cached | grep -iE "sk-[a-z0-9]|
  rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN"` → zero hits across the full staged
  diff (18 files).
- **unawaited_no_error_sink** — N/A. `git diff --cached | grep "unawaited("`
  → zero hits; this diff adds no `unawaited(` calls anywhere.
- **guard_without_its_mirror** — See Finding 2 for the one real (pre-existing,
  dormant, unfiled) gap. Otherwise clean: independently confirmed the
  delete-account-fails-OPEN / verify-payment-fails-CLOSED asymmetry the task
  asked me to check is exactly what both files' code does (traced the
  `if (rateErr) {...} else if (usedCount === -1) {...}` control flow in both
  files line-by-line; delete-account's error branch only `console.warn`s and
  falls through, verify-payment's error branch returns 429 immediately) —
  and ran the actual contract tests that pin this, which passed (see below).
- **missing_input** — Clean. `usage_counters.quota_key` is unconstrained
  `text` (migration 128 — no CHECK/enum/trigger on it), so the two new quota
  keys need no schema change. The live-SQL test's hardcoded user UUID
  (`d7a67a37-0b05-4f0a-b13c-388bff3cb59b`) is not a fabricated placeholder —
  `grep -rn` across the repo shows it is the long-established founder/QA
  test account reused in ~15 other live-verification docs/tests going back
  to 2026-05-02, satisfying `usage_counters.user_id`'s `ON DELETE CASCADE`
  FK requirement of a real `users.id`.
- **asserted_fixture_value** — Clean, and executed rather than only read.
  Ran both new contract test files: `flutter test
  test/contracts/delete_account_rate_limit_writer_to_reader_test.dart
  test/contracts/verify_payment_rate_limit_writer_to_reader_test.dart` →
  **13/13 passed**. Independently spot-checked 4 of the diagnose-doc's own
  6 mutation-table line citations against the real files byte-for-byte
  (`delete-account/index.ts:78,80,159-160,181`,
  `verify-payment/index.ts:242`) — all exact. Then ran my OWN mutation, not
  in their table: changed `RATE_LIMIT_MAX` 5→6 in `delete-account/index.ts`
  and re-ran the test — reddened **exactly 1 of 6** assertions ("the
  5-attempt cap must be unchanged"), confirming the test discriminates
  correctly rather than being coincidentally green. Restored the file from
  a backup, confirmed `git status --porcelain` shows no residual diff, and
  re-ran the test to confirm 6/6 green again. Also manually traced the live
  SQL file's self-checking `CASE` expression
  (`test/sql/oi162_slice4_quota_boundary_and_acl_live_verify.sql`) against
  `consume_quota`'s actual return semantics (increment-then-return-count on
  success, `-1` sentinel on refusal) and found it algebraically correct for
  all four branches (at-limit, must-refuse, next-bucket, sequential calls).
- **blast_radius_mismatch** — The TIER itself is correct (see Finding 1) —
  `docs/blast_radius.yaml:42-43` independently confirms catastrophic for
  both touched Edge Functions. The gap is the tier's REQUIRED ARTIFACT, not
  the classification — filed as Finding 1.

## Live-DB verification attempted but blocked

`mcp__claude_ai_Supabase__execute_sql` returned `MCP server "claude.ai
Supabase" requires re-authorization (token expired)` on every attempt (ACL
dump for `consume_quota`, `has_function_privilege` for the four roles, RLS
policy count on `usage_counters`, `pg_roles.rolbypassrls`). Per the task's
own fallback instruction, these specific claims (the live pre-migration ACL
shape, RLS-zero-policy on `usage_counters`, `service_role.rolbypassrls`) are
therefore verified only by re-deriving them from migrations 128/129's own
text and cross-checking internal consistency (e.g. 130's ACL dump — 5
entries including separate `anon=X`/`authenticated=X` — is consistent with
128's comment about the schema-wide default-privilege regime), not by an
independent live query. Flagging this explicitly rather than silently
presenting static-analysis confidence as live-verified confidence.
