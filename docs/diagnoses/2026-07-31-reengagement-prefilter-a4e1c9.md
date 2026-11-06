---
bug_id: a4e1c9
date: 2026-07-31
batch: re-engagement-prefilter
status: fixed
blast_radius: catastrophic
symptom: >
  OI-48 (audit finding, corrected twice — 2026-07-27 re-scope, 2026-07-29
  board correction — down to a single real remaining instance): the
  `re-engagement` cron-dispatched Edge Function's Path B silent-user
  fallback fetched EVERY non-deleted user (`.from("users")`, O(all users))
  then, per user not already covered by Path A, issued up to 3 sequential
  per-table point queries (workout_logs, nutrition_logs, weight_logs) to
  verify absence of recent activity. At 12 Path-B-eligible silent users this
  is 1 + 12*3 = 37 Postgres round-trips per cron tick (noon IST, daily);
  unbounded growth with user count, since the outer scan has no pre-filter
  at all (not even last_active_at, which was only checked in-process after
  the fetch, not as a query predicate). While investigating the reference
  RPC pattern to mirror (find_orphan_chat_media, migration 071 — the
  board's own text already named this as the better structural fit for an
  absence/anti-join check, vs. protein-gap-alert's batched positive-filter
  precedent), live has_function_privilege queries against dedsavbjuwgarrhphgnl
  found that RPC has been anon- AND authenticated-executable since its
  creation (migration 071 GRANTed to service_role but never revoked the
  PUBLIC-default grant anon/authenticated inherit via pg_default_acl) — the
  same gap class migrations 090/091 fixed for 9 SECURITY DEFINER functions
  on 2026-06-11, but find_orphan_chat_media was never covered by that
  audit — B-pass caught an initial draft here claiming a timing reason
  ("created a week after") that had the dates backwards: find_orphan_chat_
  media's creating migration (071) is dated 2026-05-17, ~25 days BEFORE
  090/091, not after. The real reason is SCOPE, not timing: 090/091's
  REVOKE pass specifically targeted SECURITY DEFINER functions (live-
  verified: all 9 are prosecdef=true), and find_orphan_chat_media is plain
  SQL/STABLE — categorically outside that audit's scope regardless of
  when either migration landed.
concept: reengagement_silent_candidate_detection
sot_registry_entry: >
  Not added as a docs/sot_registry.yaml top-level concept — this is a
  read-only candidate-selection RPC with no Hive side and no cloud row it
  owns/writes (mirrors how find_orphan_chat_media itself has no SoT registry
  entry). Documented instead in supabase/migrations/CLAUDE.md's existing
  table→concept mapping is not applicable either (no table gains/loses a
  column); the RPC is documented in this diagnose-doc and in migration
  117's own header, matching find_orphan_chat_media's own precedent level
  of documentation.
writers: >
  supabase/migrations/117_reengagement_silent_candidates_rpc.sql —
  find_reengagement_silent_candidates(date, timestamptz, uuid[]) (new,
  read-only SQL/STABLE function, no table writes); REVOKE/GRANT statements
  on find_reengagement_silent_candidates AND (Part 2, the sibling fix)
  find_orphan_chat_media(timestamptz) — narrows both to service_role-only.
  supabase/functions/re-engagement/index.ts — Path B rewritten to call
  `.rpc('find_reengagement_silent_candidates', ...)` once instead of the
  old .from("users") fetch + per-user 3-table loop (removed lines
  previously ~131-189); new exported pure function `mapFallbackCandidates`
  (line ~80) projects the RPC's rows into the same {candidates, names}
  shape the loop used to build inline.
readers: >
  The re-engagement cron's own notification-send loop (unchanged —
  `allCandidates`/`fallbackNames` are consumed identically to before, only
  their construction changed). clean-orphan-media/index.ts remains
  find_orphan_chat_media's only caller (confirmed by repo-wide grep before
  narrowing its grant), unaffected by the Part-2 privilege fix since it has
  always called as service_role.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: users, workout_logs, nutrition_logs, weight_logs, storage.objects, subscriptions
cloud_columns: >
  users.id, users.full_name, users.last_active_at, users.is_deleted
  (find_reengagement_silent_candidates read columns); workout_logs.user_id,
  workout_logs.date; nutrition_logs.user_id, nutrition_logs.date;
  weight_logs.user_id, weight_logs.date (anti-join predicate columns, no
  schema change to any of these — read-only). find_orphan_chat_media's own
  read columns (storage.objects, public.users, public.subscriptions)
  unchanged by the Part-2 privilege fix — only its EXECUTE grant changed,
  not its body or the columns it reads.
contract_test_path: supabase/functions/re-engagement/index_test.ts
ist_handling: >
  Unchanged from pre-fix — cutoffIso/cutoffDate are computed the same way
  in TypeScript (Date.now() - 3 days, sliced to YYYY-MM-DD) as before; the
  RPC receives these as parameters rather than the client filtering
  in-process, so no IST semantics changed, only where the filtering
  executes. Not a date-key-reset concept (this is a rolling 3-day lookback,
  not a daily-boundary cap), so the IST-midnight-boundary bug class
  (migration 026/113's own history) does not apply here.
provider_invalidations: not_applicable
telemetry_op_types: >
  Not a client ErrorTelemetry concept (no lib/ code in this batch), but the
  SERVER-side cron telemetry did change, and had to — Hermes lens L34 found
  the accepted Path-B tradeoff (per-user skip-and-continue -> one
  whole-invocation throw) had never been assessed for observability by the
  x2 rounds OR the B-pass. cron_call_log.error_summary is now the ONLY
  durable record of a Path B failure, and it was blind twice over:
  (F1) `errorSummary: String(err)` serializes a supabase-js PostgrestError
  -- a plain {message,details,hint,code} object, NOT an Error subclass --
  to the literal string "[object Object]"; this is a catalogued repo
  bug-class (Hermes 2026-07-26 F3) whose shipped fix survives at
  compute-coach-signals/index.ts:92-98, the ONLY function repo-wide
  carrying the guard (grep-verified across all 25 errorSummary callsites).
  (F2) Path A's `throw memError` and Path B's `throw fallbackErr` landed in
  one catch with an untagged summary, so the two were byte-identical rows.
  Both fixed: errorSummary now unwraps .message, and both throw sites carry
  a `path_a ...` / `path_b ...` tag (convention mirrored from
  morning-alert:809 / rolling-context:161).
cross_account_guard: >
  find_reengagement_silent_candidates and find_orphan_chat_media (Part 2)
  are both now service_role-only (anon + authenticated EXECUTE revoked) —
  live-verified via has_function_privilege before AND after applying the
  fix within a rolled-back transaction (test/sql/reengagement_silent_
  candidates_verify.sql cases 4-9). Neither function is SECURITY DEFINER
  (both run with the CALLER's privileges as plain SQL/STABLE functions), so
  even pre-fix the over-broad grant was not a live data leak. RLS is
  enabled on all 3 tables find_orphan_chat_media reads (storage.objects,
  public.users, public.subscriptions), and round-1 review caught an
  imprecise first draft of this claim here ("zero anon-granted policies") —
  live pg_policies actually shows 4 SELECT-command policies scoped
  `roles={public}` on these 3 tables (the only command find_orphan_chat_media
  ever issues; there are 7 `roles={public}` policies total across all
  commands, but the other 3 are INSERT/UPDATE/DELETE, irrelevant to a
  read-only function), which DOES include anon. The zero-rows conclusion
  still holds, for the real
  reason: `users_select_own`/`subscriptions_select_own` both qualify on
  `auth.uid() = id|user_id`, NULL for an anon caller (no session) so no row
  matches; storage.objects' two `{public}` policies ("Allow public read
  avatars"/"Allow public read banners") filter `bucket_id IN ('avatars',
  'banners')`, disjoint from the `chat-media` bucket this function actually
  queries. The fix closes unwanted
  attack surface inconsistent with both functions' always-documented
  service-role-only intent, not an active leak.
forbidden_patterns_checked: >
  date vs timestamptz parameter-type mismatch on a new RPC parameter
  compared against a `date`-typed column (the exact bug class Unit 3b's
  own live-verify test caught in a sibling RPC on 2026-07-30 — this
  batch's first live-transaction draft used `p_cutoff_date timestamptz`
  before live schema inspection via information_schema.columns confirmed
  workout_logs/nutrition_logs/weight_logs.date are genuinely `date`, not
  timestamptz — corrected before the migration file was even run once);
  PUBLIC-only REVOKE without explicit anon/authenticated (the
  feedback_revoke_from_public_not_role.md class — both this migration's
  functions use the full `FROM PUBLIC, anon, authenticated` form); an empty
  exclude-array edge case that could silently exclude every candidate via
  a malformed `= ANY()` negation (tested directly, case 2); a NULL (not
  merely empty) exclude-array producing the same silent-empty failure mode
  via `NOT (id = ANY(NULL::uuid[])) IS NULL` rather than false — caught by
  round-1 review, fixed with `COALESCE(p_exclude_user_ids,
  ARRAY[]::uuid[])`, tested directly (case 3b); mutable search_path on a
  new directly-callable public RPC (round-1 review N2 — every other
  directly-callable public RPC in this project sets `search_path`,
  including the sibling this migration mirrors; omitting it would have
  regressed the function_search_path_mutable lint category the 2026-06-11
  audit closed 9/9) — fixed with `SET search_path = public`.
proposed_fix: >
  One new Postgres RPC (migration 117 Part 1), find_reengagement_silent_
  candidates(p_cutoff_date date, p_cutoff_ts timestamptz, p_exclude_user_ids
  uuid[]), expressing the absence-of-recent-activity check as three NOT
  EXISTS anti-joins plus the last_active_at fast-path and is_deleted/
  exclude-array filters — all in one SQL statement, mirroring find_orphan_
  chat_media's shape. re-engagement/index.ts's Path B now calls this RPC
  once instead of fetching all users and looping. Migration 117 Part 2
  closes the live over-broad EXECUTE grant found on find_orphan_chat_media
  while designing Part 1 against it as the reference pattern — REVOKE FROM
  PUBLIC, anon, authenticated + GRANT TO service_role on both functions,
  the actually-effective pattern per migrations 090/091's prior finding
  (a PUBLIC-only revoke is a no-op against Supabase's per-role default ACL).
regression_test_planned: >
  supabase/functions/re-engagement/index_test.ts (5 Deno tests, pure-function
  + source-shape, following compute-admin-metrics-daily/index_test.ts's
  convention — the serve handler needs live env so is not exercised here):
  mapFallbackCandidates projects rows correctly; null full_name preserved
  as null (not undefined, so Map.has distinguishes "present but null" from
  "absent"); empty RPC result produces an empty candidate set; row order is
  preserved; source-grep confirms the 3 old per-table `.from(...)` calls
  are GONE (not merely supplemented) and the new `.rpc(` call is present.
  Behavioral proof of the RPC's own anti-join correctness + privilege grants
  lives in test/sql/reengagement_silent_candidates_verify.sql (10 cases), run
  via the existing generic `scripts/check_onconflict_live_arbiter.dart --sql
  test/sql/reengagement_silent_candidates_verify.sql` harness. **RUN LIVE
  2026-07-31 (pre-apply, via direct execute_sql in a rolled-back
  transaction): all 10 cases returned status='ok'** — candidate-set
  correctness (the genuinely-silent seeded user AND a seeded user with
  last_active_at IS NULL and zero activity rows — the single most
  drift-prone clause, added by round-1 review N7/F7 — against 5 other
  seeded users each excluded for a different reason: recent activity in
  each of the 3 tables, fresh last_active_at, is_deleted, and the exclude
  array), the empty-exclude-array edge case, the NULL-exclude-array edge
  case (case 3b, proving the COALESCE guard above), the exclude-empties-
  the-set case, and both functions' before/after privilege grants. The
  empty-exclude-array case's first draft asserted the wrong expected value
  (only the silent user, when the correctly-also-silent "Excluded User"
  fixture legitimately belongs in that unfiltered result too) — a bug in
  the TEST's assertion, caught by the live run itself and corrected before
  being treated as passing; not an RPC bug. Also appended 7 rows to the
  existing test/sql/security_definer_anon_revoke.sql (a MANUAL post-deploy
  privilege-sanity file -- confirmed by grep that no script/CI workflow
  runs anything under test/sql/*.sql automatically; it is run by hand
  against live Postgres after a deploy, same pre-existing convention Unit
  3b already extended past its originating migration) covering both
  functions' anon/authenticated/service_role grants.
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "supabase/functions/re-engagement/index.ts — a Deno Edge Function, not covered by flutter analyze. Deno type-check + the 5 new index_test.ts tests pass locally (deno test --allow-env). Source-grep test confirms the 3 old per-table .from() calls inside the removed loop are gone, not merely supplemented." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive read/write anywhere in this batch" }
  - { tier: 3_postgres_schema, status: fixed_in_this_batch, evidence: "migration 117 adds one new function (find_reengagement_silent_candidates) and CREATE-OR-REPLACE-then-REVOKE/GRANTs the pre-existing find_orphan_chat_media's privileges (its body is untouched, only its EXECUTE grant narrows). No table/column DDL." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no existing row data touched — both parts of migration 117 are function DDL + privilege grants only" }
  - { tier: 5_migrations_applied, status: pending_explicit_authorization, evidence: "Migration 117 written and live-verified (test/sql/reengagement_silent_candidates_verify.sql, 10/10 ok, run pre-apply in a rolled-back transaction) but NOT YET applied to dedsavbjuwgarrhphgnl — per CLAUDE.md Sec4.3, live apply requires its own explicit founder authorization, requested separately after this diagnose-doc and the review round(s) converge, not assumed from batch/plan approval." }
  - { tier: 6_edge_function_code_vs_deploy, status: pending_explicit_authorization, evidence: "re-engagement/index.ts source rewritten locally; NOT yet deployed to dedsavbjuwgarrhphgnl. Deploying before migration 117 is live would 500 every Path-B-eligible cron tick (the RPC would not exist yet) — deploy must happen AFTER, not before or simultaneously with, the migration apply, both under their own explicit authorization." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "re-engagement's own cron schedule (30 06 * * * UTC) is unchanged by this batch — only its Path B implementation changed, not its trigger or auth gate" }
  - { tier: 8_rls_policies, status: verified, evidence: "no RLS policy change. Confirmed live (pg_policies) that storage.objects/public.users/public.subscriptions have RLS enabled. 4 SELECT-command policies (the only command this read-only function issues) are roles={public} (includes anon; 7 roles={public} policies exist across all commands, the other 3 are INSERT/UPDATE/DELETE and irrelevant here) but none expose rows to an anon caller through this function: users_select_own/subscriptions_select_own qualify on auth.uid()=id|user_id (NULL for anon), and storage.objects' 2 public SELECT policies are bucket-scoped to avatars/banners, disjoint from chat-media — the basis for this diagnose-doc's cross_account_guard field's not-a-live-leak conclusion for the pre-fix find_orphan_chat_media grant gap. Round-1 and round-2 review each caught an imprecise draft of this evidence string in turn (first 'zero', then an unqualified '4')." }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage bucket or object touched — find_orphan_chat_media reads storage.objects metadata via SQL, unchanged by the Part-2 privilege fix" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no Razorpay/OneSignal/Firebase touched" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "test/sql/reengagement_silent_candidates_verify.sql traces the RPC's full candidate-selection contract end-to-end via live-Postgres calls in a rollback transaction — 10/10 cases passing, including both functions' privilege grants before/after. Live index.ts <-> RPC parameter-shape match (p_cutoff_date/p_cutoff_ts/p_exclude_user_ids) verified by running the exact same DDL the migration file contains." }
impact_analysis: >
  Positive: closes OI-48 in full, per the board's own twice-corrected
  2026-07-29 text (open_issues.md:449-489), not a bare "already fixed"
  claim -- evaluate-rank-promotions is reclassified there as "NO LONGER
  MATCHES THE FINDING... now the in-repo EXAMPLE of the fix" (its
  N-per-user reads are batched via chunked `.in()`, even though an outer
  `.from("users")` scan survives), and i-see-you-callout is moved to
  "already efficient" for its F45 active-user pre-filter + pagination
  (even though bounded per-active-user queries remain). Neither is
  "zero remaining queries" -- the board's own bar for closing this finding
  is "no longer the unbounded recompute-everything shape", which
  round-1 review confirmed both satisfy; re-engagement was the one
  function that still failed even that bar before this fix. Reduces
  re-engagement's Path B cost
  from 1 + 3N Postgres round-trips (N = Path-B-eligible users after Path A)
  to exactly 1, removing the unbounded-with-user-count growth entirely.
  Additionally closes a live privilege-hygiene gap on find_orphan_chat_media
  that predates this batch and was not part of OI-48's own scope — found
  only because this batch's own design process used that function as its
  reference pattern and checked its live grants before copying its shape.
  Confirmed NOT a live data leak (RLS backstop verified: the `{public}`-role
  policies on the 3 tables it reads are either auth.uid()-scoped, NULL for
  anon, or bucket-disjoint from what the function queries), so this is a
  hardening fix, not an incident response.

  Residual, stated rather than silently dropped: this migration and the
  Edge Function rewrite are NOT yet live — both require their own explicit
  founder authorization per CLAUDE.md Sec4.3 (plan approval is not deploy
  approval), requested after the review round(s) below converge. Until
  both land, re-engagement continues running its OLD Path B code against
  the OLD (over-broad-grant) find_orphan_chat_media — this diagnose-doc
  describes what WILL be true post-deploy, and tier 5/6 above are marked
  pending_explicit_authorization rather than fixed_in_this_batch to keep
  that distinction visible rather than overclaiming completion.

  Second residual, also stated rather than silently dropped: round-1 review
  independently re-ran the has_function_privilege query this migration's
  own design process used against find_orphan_chat_media, applied
  repo-wide, and found 3 MORE public-schema functions with the identical
  unrevoked-PUBLIC-grant gap (get_users_with_message_count,
  match_memories, morning_alert_pick_quarter — none SECURITY DEFINER, same
  class of unwanted-but-not-confirmed-exploitable attack surface). These
  are NOT fixed by migration 117 and NOT folded into this unit's scope —
  they were not the reference pattern this migration was designed against,
  each needs its own per-function caller/RLS verification at the same
  rigor this diagnose-doc gives find_orphan_chat_media, and bundling 3
  more into an already-catastrophic-tier migration would dilute that
  rigor rather than preserve it. Filed as docs/audit/open_issues.md OI-78
  (P3, blast radius estimate platform) instead, with a recommendation to
  build a structural allowlist gate rather than keep fixing this class one
  reference-pattern-discovery at a time.
---

# `re-engagement`'s Path B silent-user scan was O(all users) with a per-user 3-table query loop; fixing it surfaced a live, pre-existing privilege gap on the sibling RPC it was designed to mirror

## Summary

OI-48's last remaining real instance (after two prior board corrections
confirmed the other two named functions no longer match the unbounded
recompute-everything shape the finding describes, per their own now-batched
or now-pre-filtered-and-paginated reads):
`re-engagement`'s Path B fallback for silent-user detection fetched every
non-deleted user, then ran up to 3 sequential per-table absence checks per
candidate. Replaced with one Postgres RPC expressing the same check as
`NOT EXISTS` anti-joins, mirroring `clean-orphan-media`'s existing
`find_orphan_chat_media` RPC — which the investigation into that exact
pattern revealed has been anon/authenticated-executable live since its
creation (migration 071 never revoked the PUBLIC-default grant). Both gaps
close in the same migration (117): the new RPC ships privilege-hardened
from the start, and the reference RPC gets the same hardening retroactively.
Not a live data leak (RLS backstop confirmed) — a hardening fix, closing
unwanted attack surface consistent with both functions' always-documented
service-role-only intent.

## Root cause

**Writer (Path B fetch):** `supabase/functions/re-engagement/index.ts`,
pre-fix lines ~131-135 — `.from("users").select("id, last_active_at,
full_name, is_deleted").or("is_deleted.is.null,is_deleted.eq.false")`, no
`last_active_at` predicate (the freshness check happened in-process, after
the fetch, not as a query filter).

**Reader/verifier (the per-user loop):** same file, pre-fix lines ~140-189
— for each of the (potentially thousands of) fetched users not already in
Path A's candidate set, up to 3 sequential `.from("workout_logs")` /
`.from("nutrition_logs")` / `.from("weight_logs")` point queries, each
`.eq("user_id", userId).gte("date", cutoffDate).limit(1)`.

**The reference pattern's own gap (found via investigation, not the
original finding):** `supabase/migrations/071_rename_orphan_media_rpc.sql`
line 41 — `GRANT EXECUTE ON FUNCTION public.find_orphan_chat_media TO
service_role;` with no accompanying `REVOKE ... FROM PUBLIC, anon,
authenticated`. Supabase's platform grants EXECUTE on every new
public-schema function DIRECTLY to `anon`/`authenticated` via
`pg_default_acl`, bypassing `PUBLIC` entirely (the same mechanism
migrations 090/091 document fixing for 9 SECURITY DEFINER functions on
2026-06-11) — migration 071 (2026-05-17) predates that audit by ~25 days
and was never covered by it, because 090/091's REVOKE pass was scoped to
SECURITY DEFINER functions specifically, not because of timing (an
earlier draft of this doc had the dates backwards — caught by B-pass).
find_orphan_chat_media is plain SQL/STABLE, outside that scope regardless
of creation order. Live
`has_function_privilege` queries against `dedsavbjuwgarrhphgnl` confirmed
`anon`=true, `authenticated`=true, `service_role`=true before this batch's
fix.

## Fix

Migration 117, two parts:

1. New RPC `find_reengagement_silent_candidates(p_cutoff_date date,
   p_cutoff_ts timestamptz, p_exclude_user_ids uuid[])` — one `SELECT`
   against `public.users` with three `NOT EXISTS` anti-joins (workout_logs,
   nutrition_logs, weight_logs) plus the `last_active_at`/`is_deleted`/
   exclude-array filters, all evaluated by Postgres in one round-trip.
   Explicit `REVOKE ... FROM PUBLIC, anon, authenticated` + narrow
   `GRANT ... TO service_role` from the start.
2. The same `REVOKE`/`GRANT` pair applied to the pre-existing
   `find_orphan_chat_media`, closing the gap found in step 1's own design
   investigation. Its function body and its one real caller
   (`clean-orphan-media/index.ts`, always `service_role`) are unaffected.

`re-engagement/index.ts`'s Path B now calls the new RPC once; a new
exported pure function `mapFallbackCandidates` projects the RPC's rows into
the same `{candidates, names}` shape the old loop built inline, kept
separately testable per this repo's established
`buildSnapshotRow`/`index_test.ts` convention.

## Blast-radius confirmation

`scripts/blast_radius_from_diff.dart` against the staged diff returned
`catastrophic`, not the plan's pre-diff `account` estimate — the path-glob
tier for `supabase/migrations/**` (`platform`) was escalated by the
content-rule in `blast_radius_content_rules_lib.dart`, which regex-matches
`security\s+definer` (case-insensitive) anywhere in a staged migration
file's content, no negation-awareness. The match is on prose in this
migration's own comments (referencing migrations 090/091's *SECURITY
DEFINER* fixes, and stating find_orphan_chat_media is *not* SECURITY
DEFINER) — neither new function in this migration declares a `SECURITY
DEFINER` clause. Per the rule's own header comment, this is by design
("a content check can only ESCALATE... erring toward 'no escalation' is
the safe direction") — accepted as-is rather than reworded around, since
the migration substantively does change EXECUTE privilege grants on two
functions (closing a live over-broad grant on one), the exact bug class
(migrations 090/091) this rule exists to catch conservatively. Proceeding
with the full catastrophic-tier process: x2 independent review + B-pass +
Hermes-pass + plan-review record with `hermes: accepted`.

## Verification

- `test/sql/reengagement_silent_candidates_verify.sql` — 10/10 cases `ok`,
  run live pre-apply in a rolled-back transaction (candidate-set
  correctness, empty-exclude-array edge case, exclude-empties-the-set case,
  both functions' anon/authenticated/service_role grants before and after).
- `supabase/functions/re-engagement/index_test.ts` — 5/5 Deno tests
  (pure-function + source-shape).
- `test/sql/security_definer_anon_revoke.sql` — extended with 6 new rows
  (both functions' 3-role grant shape) as a standing post-deploy sanity
  check, mirroring how Unit 3b already extended this file past its
  originating migration.

## Observability of the accepted tradeoff (Hermes L34)

The RPC rewrite deliberately drops Path B's old per-user "skip this user on
read error" handling — one SQL statement cannot partially fail per-row, so
an RPC error now fails the whole Path B fallback. The ×2 rounds and the
B-pass all assessed that tradeoff on **correctness** grounds and cleared
it; none assessed its **observability**, and Hermes lens L34 found the one
durable record of that now-fatal leg was blind two ways:

1. `errorSummary: String(err)` → `"[object Object]"` for a supabase-js
   `PostgrestError` (a plain object, not an `Error`). Catalogued bug-class;
   the shipped fix lived only in `compute-coach-signals/index.ts:92-98`.
2. Path A and Path B failures were indistinguishable — both bare throws
   into one catch, untagged.

Both fixed here. Two further L34 findings in the same send loop:

3. **REFUTED — the finding was wrong, and the fix built on it was reverted.**
   L34 reported that a `markProactiveSent` throw incremented `errors` for a
   push that had already delivered (`sent++` ran first), double-counting one
   user into both tallies. A wrapper + a `markFailures` counter were written
   against that claim. A later lens (L21) challenged the premise, and
   reading the helper settled it: `_shared/proactive_dedup.ts:87-95` wraps
   its entire body in try/catch and only `console.warn`s — its own doc
   comment reads *"Non-fatal on failure (the push already went out)"*. It
   **cannot throw**, so the double-count was unreachable and the identity
   `sent + dedup_skipped + prefs_off + errors == candidate count` already
   held. Worse, the "fix" was actively harmful: `mark_failures` could only
   ever be `0`, and emitting it in the log line and both response shapes
   would have affirmatively asserted "dedup bookkeeping never failed" while
   real failures are silently swallowed inside the helper. Fully reverted;
   all 9 sibling cron functions call the helper bare after `sent++` for the
   same reason, and re-engagement now matches them again. The regression
   test was rewritten to pin the **premise** rather than the shape — it
   re-reads `proactive_dedup.ts` and fails if `markProactiveSent` ever
   grows a throwing path, and separately fails if a `markFailures` counter
   reappears. This is the `feedback_audit_verifier_cannot_trust_own_subagent`
   class: the finding quoted the call site accurately but reasoned wrongly
   about the callee, and the fix shipped before the callee was read.
4. The zero-candidate early return omitted `prefs_off`, so a consumer
   parsing both success shapes saw an inconsistent contract. REAL and
   fixed — both shapes now carry the same key set.

The genuine observability gap L34 was circling — `markProactiveSent`
swallowing its own failures with only a `console.warn` — is real but lives
in a shared helper's deliberate, documented contract across 9 callers.
Changing it is a cross-function contract change, not a re-engagement fix,
and it is NOT what L34's finding described. Recorded here as verified
rather than silently dropped.

## Silent truncation at PostgREST's row cap (Hermes L31 → OI-79)

L31 confirmed empirically (a live un-ranged REST read returns HTTP 206 +
`Content-Range: 0-999/1431`) that PostgREST caps un-ranged responses at
`db-max-rows` = 1000, and that **supabase-js does not surface a 206 as an
error** — `error` is null and `data` is simply short. Neither Path A nor
Path B paginates, so above 1000 candidates each silently processes a
truncated set.

This is NOT introduced by this batch, and this batch strictly improves it:
the old Path B truncated an *unordered, unfiltered* all-users fetch at 1000
*before* any activity filtering (so it could surface ~0 genuinely-silent
users), whereas the RPC returns up to 1000 *already-filtered* ones. The
real fix is a `.range()` pagination loop over both paths — a distinct
concern from OI-48's per-user-query-loop finding, affecting cron functions
this batch does not otherwise touch, and filed as **OI-79** (P1) with the
`morning-alert:583-594` precedent and a note to re-run the lens across all
cron candidate scans rather than just the two named.

What IS in scope and shipped here: **saturation detection**. Both paths now
emit a loud `console.warn` naming OI-79 when a read returns >= 1000 rows
(`re-engagement/index.ts:154` Path A, `:240` Path B), converting a silent
short read into an explicit one. Detection is not a fix, and the doc says
so — but it removes the "indistinguishable from a small result set"
property that makes this class dangerous.

## Residual

Migration 117 and the Edge Function rewrite are not yet live — pending
explicit founder authorization per CLAUDE.md §4.3, requested after review
converges. See `touched_layers_checked` tiers 5/6 above.

closes-diagnose: a4e1c9
