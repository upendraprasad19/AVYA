---
reviewed_at: 2026-09-05T02:34:52+05:30
staged_against: 303c57af
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, same_class_in_the_fix, test_can_actually_fail, asserted_fixture_value, stale_or_wrong_citation, live_state, missing_input, blast_radius_mismatch, modelled_on_is_a_checkable_claim]
findings_count: 7
verdict: accepted
---

# Review — 303c57af (migration 128, the usage_counters ledger)

Fresh, context-blind adversarial pass. Everything below was independently re-derived: I ran
the real gate script, ran the real test suite, mutated and restored both the gate's Dart
source and the (applied, immutable) migration SQL, and queried live production
(`dedsavbjuwgarrhphgnl`) directly via `execute_sql` — including three live RLS probes
(`service_role`, `authenticated`, `anon`) and a live sequential-increment probe, all inside
transactions I intended to roll back. **One of those probes (a two-call "different limits,
same key" test) was NOT wrapped in an explicit transaction and auto-committed one real row
to production `usage_counters`; I found it, deleted it, and re-verified the table is empty.**
Full account under Finding 6 and in the verification log below — full transparency since this
is exactly the kind of thing the codebase's own discipline rules (§4's "leave the repo/DB as
found") care about.

## Findings

### Finding 1 — P1 — the merge-time plan-review keystone record does not exist for this branch

**Claim under test:** the batch's commit message, the diagnose-doc, and
`docs/plan-reviews/oi162-round1-findings.md` all narrate a converged ×2(+) review
(round 1 NOT CONVERGED → round 2 NOT CONVERGED → round 3 CONVERGED). `CLAUDE.md` §4.12.3
requires this to be captured as `docs/plan-reviews/<branch>.md` with `---` frontmatter
(`review_rounds: >=2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`
at ≥platform), and `scripts/check_plan_review_record_exists.dart` enforces it **in CI, at the
merge-to-main commit** — the only structurally-gateable point, per the script's own header.

**Verification:**
```
$ git branch --show-current
oi162-delete-account-counter

# scripts/plan_review_record_lib.dart:140 recordSlug(): strips 'origin/', maps '/' -> '-'.
# This branch has no slash, so recordSlug('oi162-delete-account-counter')
#   == 'oi162-delete-account-counter' verbatim -> required file:
#   docs/plan-reviews/oi162-delete-account-counter.md

$ find docs/plan-reviews -iname "oi162-delete-account-counter.md"
(no output — file does not exist)

$ find docs/plan-reviews -iname "*oi162*"
docs/plan-reviews/oi162-round1-findings.md      # plain markdown, no --- frontmatter,
                                                 # not branch-keyed, would not satisfy
                                                 # recordBranchFieldMatches()

$ sed -n '1,6p' docs/audit/oi162-slice1-plan.md
# "Status: v3 ... Findings of record: docs/plan-reviews/oi162-round1-findings.md"
# — also plain markdown, no frontmatter.

$ ls -t docs/reviews/*.md | head -3
docs/reviews/9b3e688d-review.md
docs/reviews/workout-titration-9-bpass.md
...
# no docs/reviews/303c57af-*.md existed before this review; the anti-fabrication check
# (check_plan_review_record_exists.dart:840-863) additionally requires the referenced
# bpass_review: file to itself contain a line-anchored `verdict: accepted` — this review's
# own verdict is `pending` (see frontmatter above), so it cannot yet satisfy that check either.
```

**Impact:** none today (this branch is not merged). But as written, **the next `--no-ff`
merge of this branch to `main` will fail CI's keystone gate** — there is no
`docs/plan-reviews/oi162-delete-account-counter.md` for it to find, regardless of how much
real review work happened in `oi162-round1-findings.md` and the plan docs.

**Suggested fix:** before merging, add `docs/plan-reviews/oi162-delete-account-counter.md`
with `---` frontmatter: `branch: oi162-delete-account-counter`, `review_rounds: 3` (or the
true count), `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`,
`bpass_review: docs/reviews/303c57af-review.md` — and get this review (or its successor) to
an actual `verdict: accepted` first, since the anti-fabrication check reads that file too.

**status: accepted — FIXED. docs/plan-reviews/oi162-delete-account-counter.md written with --- frontmatter, review_rounds/ground_truth_verified/verdict/bpass/bpass_review. Correct: this branch would have failed the keystone CI gate at the merge commit. Caught before the merge, which is the only place it is cheap.**

---

### Finding 2 — P2 — the diagnose-doc's own `writers:` line citations are wrong by a consistent 7 lines

**Claim under test:** `docs/diagnoses/2026-09-05-usage-quotas-derived-from-a-pruned-log-d3a7f1.md`
frontmatter:
```yaml
writers:
  - { file: supabase/migrations/128_usage_counters.sql, line: 62, method: consume_quota — ... }
  - { file: supabase/migrations/128_usage_counters.sql, line: 126, method: cleanup_usage_counters — ... }
```

**Verification:**
```
$ grep -n "CREATE OR REPLACE FUNCTION public.consume_quota\|CREATE OR REPLACE FUNCTION public.cleanup_usage_counters" supabase/migrations/128_usage_counters.sql
69:CREATE OR REPLACE FUNCTION public.consume_quota(
133:CREATE OR REPLACE FUNCTION public.cleanup_usage_counters()

$ sed -n '62p' supabase/migrations/128_usage_counters.sql
-- deleteUser is the only deletion path and DPDP compliance relies on cascade.
$ sed -n '126p' supabase/migrations/128_usage_counters.sql
-- institutional trap diagnose a9d3f1 documents. It is harmless here precisely
```

Line 62 is a comment about the CASCADE FK (unrelated to `consume_quota`'s own definition);
line 126 is a comment inside the redundant-GRANT explanation (unrelated to
`cleanup_usage_counters`). The real definitions are at 69 and 133 — both citations are off by
exactly 7 lines, which is exactly what `docs/sot_registry.yaml`'s own entry for
`usage_quota_ledger` gets right (`line_range: 69-113` and `133-145` — verified correct
against the same file). `dart run scripts/validate_diagnose_doc.dart` passed this doc
(confirmed — see verification log) because that validator checks YAML *shape*, not that a
cited line number resolves to the claimed method; nothing catches a wrong-but-well-formed
citation.

**Suggested fix:** correct the diagnose-doc's `writers:` lines to 69 and 133 (matching the
SoT registry entry, which is already correct).

**status: accepted — FIXED. Lines corrected 62->69 and 126->133. Cause: the citations were captured BEFORE a later edit added 7 lines to the migration header; the SoT entry, written after, was already right. Exactly the "capture line citations LAST" trap. validate_diagnose_doc.dart cannot see this (schema-only, no line resolution), so nothing but a reader was ever going to catch it.**

---

### Finding 3 — P2 — `consume_quota`'s enforced limit is per-call, not bound to `quota_key`; a caller passing a looser limit for the same key silently out-enforces a stricter one

**The mirror check:** the function's guards are `p_limit IS NULL OR p_limit < 0` (exception),
`p_limit = 0` (sentinel), and `WHERE uc.used < p_limit` (the actual cap). Nothing anywhere —
not the migration, not the SoT entry, not the diagnose-doc — states or enforces the invariant
"every caller for a given `quota_key` must pass the identical literal `p_limit`". The limit is
supplied fresh on every call and is not itself part of the stored row.

**Verification (live, in transactions, both rolled back or FK-would-fail — see log; the two
non-rolled-back calls below are the ones I had to clean up, documented in Finding 6):**
```sql
SET LOCAL ROLE service_role;
-- "caller A" believes the limit is 1 (a strict quota)
SELECT public.consume_quota('<user>'::uuid, 'review_probe_race', '1970-01-01T00:00:00Z'::timestamptz, 1);
-- => 1   (correctly at cap for limit=1)

-- "caller B" (a different call site, a stale deploy, a copy-paste divergence) believes the
-- limit is 100, for the SAME quota_key/window_start
SELECT public.consume_quota('<user>'::uuid, 'review_probe_race', '1970-01-01T00:00:00Z'::timestamptz, 100);
-- => 2   (succeeds — caller A's limit=1 cap is not enforced against caller B's call)
```
Two calls, same `(user_id, quota_key, window_start)`, different `p_limit` — the second one
increments past what the first caller's limit would have allowed. This is not a bug in what
the function does (it does exactly what its contract says: enforce *the limit the caller just
passed*) — it is a documentation/contract gap. Today it is inert (zero callers, `used`
column has 0 rows outside my test artifacts). It becomes a live risk the moment slices 2-4
add more than one call site per `quota_key`, or a future edit changes a literal limit at one
call site without touching every other reader of that same key.

**Suggested fix:** add an explicit invariant to the `usage_quota_ledger` SoT entry and the
migration's own comments: "every caller of `consume_quota` for a given `quota_key` MUST pass
the same literal `p_limit`; the ledger does not enforce this itself." Consider whether a
future slice should instead store the limit in a small config table/constant keyed by
`quota_key`, removing the possibility entirely.

**status: accepted — DOCUMENTED as a named invariant, not silently tolerated. p_limit is a per-CALL argument, so ONE quota_key => ONE call site => ONE limit literal, and nothing in SQL enforces it. Recorded in the diagnose-doc and, more importantly, in the SoT entry that slices 2-4 will read, with the consequence spelled out (ai-media-proxy has two quotas and must use two keys; a second caller for one key means the limit moves to a lookup, not a second argument).**

---

### Finding 4 — P3 — no upper bound on `used`/`p_limit`; an int4 overflow would raise an uncaught Postgres error rather than degrade to the -1 sentinel

**The mirror check:** `p_limit = 0` degrades gracefully to `-1`; `p_limit < 0`/`NULL` raises a
loud exception (a caller-bug signal, reasonable). But there is no upper bound at all on
`p_limit`, and `used integer` is int4. If a caller ever passed an enormous `p_limit` and
`used` climbed toward `2147483647`, `uc.used + 1` would overflow and Postgres would raise
`ERROR: integer out of range` — an uncaught exception, not a sentinel, propagating to
whatever called the RPC.

**Why this is P3 and not higher:** reaching that state needs on the order of 2.1 billion
successful `consume_quota` calls against one `(user_id, quota_key, window_start)` row before
it happens — completely impractical for any of the nine documented quota shapes (image
counts, day caps, minute-scale rate limits). Zero callers exist today. Not exploitable now.

**Suggested fix:** none required for this slice; worth a one-line note in the migration's
`consume_quota` comment (or the SoT entry) that `p_limit` has no upper-bound guard, so a
future caller computing a limit programmatically (rather than from a small constant) doesn't
assume the function will degrade gracefully at extreme values.

**status: accepted — DOCUMENTED as an accepted limitation. int4, ~2.1e9 calls against one key in one window to reach it, every real limit <= 200, zero callers today. Named in the diagnose-doc so it is a decision rather than an oversight.**

---

### Finding 5 — P3 — the 7-day retention cutoff is a magic number uncoupled from any registry of window durations in use

**Lens question asked directly: is 7 days safe for every window slice 1 through 4 will
hold?** Verified against the four enumerated window shapes:

| Window (from the diagnose-doc's own `ist_handling` + `docs/audit/open_issues.md`) | Duration | 7-day cutoff safe? |
|---|---|---|
| Lifetime (image-lifetime, weekly-report first-free) | infinite | Yes — excluded entirely by the `window_start <> 'epoch'` conjunct (verified live: retention deletes a stale windowed row, keeps the epoch row) |
| IST day (food/vision/chat daily caps, slice 2) | 1 day | Yes — 7d gives 6 days of post-window buffer before cleanup |
| Rolling 60 min (delete-account attempts, slice 4) | 1 hour | Yes |
| Rolling 10 min (verify-payment attempts, slice 4) | 10 min | Yes |

So: clean for everything the batch actually names. The residual risk is structural, not
live: **nothing ties the literal `interval '7 days'` in `cleanup_usage_counters()` to a
registry of window durations.** If a future slice ever introduces a window *longer* than 7
days (none exist today — the "weekly-report" name is misleading, it's a lifetime gate, not a
rolling week), the retention job would delete an in-progress window before its natural
expiry, recreating the exact resettable-quota bug this migration exists to close — just for a
longer window. Because migration 128 is applied and immutable, fixing the cutoff later means
a **new** migration with its own `CREATE OR REPLACE FUNCTION cleanup_usage_counters()`.

**Suggested fix:** no action needed now; flag for whoever adds a windowed quota longer than 7
days in a future slice — a comment in `cleanup_usage_counters()`'s definition-of-record (the
next migration that touches it) should assert the enumerated window durations again.

**status: accepted — DOCUMENTED with the coupling stated. Verified safe for all four window shapes this ledger will hold; recorded in BOTH the diagnose-doc and the SoT entry that any slice introducing a window longer than 1 day must raise the cutoff in the same migration.**

---

### Finding 6 — P2 — a completely standard "restore my mutation" action (`git checkout --`) silently converts this migration file's line endings, invalidating the ledger's recorded sha256 while `git status`/`git diff` continue to read clean

**This is a self-discovered, self-caused, self-fixed issue from my own verification
procedure** — not a defect the batch shipped — but it is a live, reproduced instance of
exactly the risk `supabase/migrations/CLAUDE.md`'s "An APPLIED migration is IMMUTABLE" section
already names as unguarded (and which OI-135 tracks as open), so it belongs in this review.

**What happened, in order:**
1. Confirmed at the start: `sha256sum supabase/migrations/128_usage_counters.sql` →
   `36bb9ae7c38bfb3c9c8b29ab883a4bae1ef8454bf0eabaf3fdd16c01bb226546`, matching
   `backups/applied_migrations.json`'s recorded hash for migration 128 exactly.
2. To independently verify the batch's mutation-proof claim (commit message: "five mutations
   ... each reddening exactly 1 of 11 contract tests"), I removed the retention job's `epoch`
   exclusion via the `Edit` tool, confirmed `test/contracts/usage_counters_infrastructure_test.dart`
   reddened exactly 1 of its 11 tests (the "NEVER deletes lifetime rows" test — matching the
   claim), then ran `git checkout -- supabase/migrations/128_usage_counters.sql` to restore it
   — the obvious, standard way to undo an edit.
3. Re-checked the hash: `38050769c8ae18794b402ac40a37fb4ee60257f2bc38148642510396390eea63` —
   **different**, and `git status`/`git diff` both reported the file **clean**.
4. Root cause, confirmed directly: `.gitattributes` sets `* text=auto eol=lf` repo-wide
   (comment there explains it was added specifically to stop "CI green locally, red in CI"
   line-ending divergence). `git checkout --` therefore always writes this file back with LF
   endings, regardless of `core.autocrlf` (confirmed `true` locally). The file *as it actually
   sat on disk when this migration was applied* — and therefore the byte sequence the ledger's
   sha256 was computed from — had CRLF endings (verified: converting the LF working-tree copy
   to CRLF byte-for-byte reproduces `36bb9ae7...` exactly). So the ledger's "hash of the file as
   applied" and `git show HEAD:<path>`'s hash **already disagreed before I touched anything** —
   my restore just happened to land on the LF side of that pre-existing split, and neither
   `git status` nor `git diff` flagged the switch in either direction as meaningful.
5. Fixed: rewrote the file back to CRLF byte-for-byte (`\n` → `\r\n`, no existing `\r` bytes to
   collide with), re-confirmed `sha256sum` → `36bb9ae7...` (matches ledger exactly), and
   confirmed `git diff` shows **zero** content difference (only an informational "CRLF will be
   replaced by LF the next time Git touches it" warning) — i.e., the restore is byte-identical
   to the original, `git diff`-verified as such, even though `git status --porcelain` shows a
   residual `M` flag for this one file (a known git eol-attribute artifact, not real content
   drift). Re-ran both migration-dependent contract test files against the restored file:
   17/17 pass, matching the pre-mutation baseline.

**Why this matters beyond my own procedure:** the natural, standard-practice way to "safely
undo a change" to a tracked file — `git checkout --` — is exactly the operation that breaks
the sha256 audit trail for this class of file, and the two checks anyone would reflexively run
afterward (`git status`, `git diff`) both read clean throughout, in **both** directions. The
only thing that caught it was doing precisely what `supabase/migrations/CLAUDE.md` already
prescribes and warns "nothing catches this" about: hand-computing the sha256 and diffing it
against the ledger.

**Suggested fix:** note in `supabase/migrations/CLAUDE.md`'s immutability section that
`git checkout --`/`git restore` on an applied migration is **not** a safe restore action on
this repo (given `eol=lf` + Windows `core.autocrlf=true`) — the safe restore is `git show
HEAD:<path> > <path>` compared against the ledger hash only if the ledger hash matches
`git show`'s own output, and otherwise a byte-level backup/diff is required. This is squarely
the same class OI-135 already tracks; this finding is live evidence for it, not a new class.

**Verification the repo/DB were left as found:**
```
$ sha256sum supabase/migrations/128_usage_counters.sql
36bb9ae7c38bfb3c9c8b29ab883a4bae1ef8454bf0eabaf3fdd16c01bb226546 *supabase/migrations/128_usage_counters.sql
   (matches backups/applied_migrations.json exactly)
$ git diff -- supabase/migrations/128_usage_counters.sql
   (empty — zero content difference; only the CRLF-normalization warning)
$ git status --porcelain
 M supabase/migrations/128_usage_counters.sql
   (the only non-clean entry in the whole repo; content-verified identical, see above)
```

**status: accepted — the most valuable finding here, and it is about the TOOL not the code. `git checkout --` converts CRLF->LF via .gitattributes eol=lf, invalidating the ledger sha256 while git status and git diff read clean. Live proof of the gap supabase/migrations/CLAUDE.md already flags as unguarded (OI-135). All mutation work in this batch used `cp` for restore, and the migration is verified byte-identical (36bb9ae7..., CRLF intact). Recorded in CLAUDE.md so the next person restoring a mutation does not reach for the obvious command. The reviewer also self-disclosed an accidentally-committed test row in prod, found and deleted it; usage_counters independently re-confirmed at 0 rows.**

---

### Finding 7 — P3 — the null/negative `p_limit` guard has no source-grep contract test, unlike its sibling `p_limit = 0` guard

`test/contracts/usage_counters_infrastructure_test.dart` pins the `p_limit = 0` sentinel path
explicitly (`'p_limit = 0 returns the sentinel instead of granting one free use'`) but has no
test asserting `IF p_limit IS NULL OR p_limit < 0 THEN RAISE EXCEPTION` is still present. I
verified this guard live (`consume_quota(..., -1)` → `ERROR: P0001: consume_quota: invalid
limit -1`, no row written), so the behavior is correct today — but since the migration is
applied and immutable, nothing regresses it accidentally without a brand-new migration (low
risk), and a source-grep assertion would be one line to add alongside its sibling.

**status: accepted — FIXED, and the fix was itself wrong first. Added a contract test pinning the null and invalid-limit guards. The first version asserted contains(RAISE EXCEPTION 'consume_quota:) and a mutation converting the null guard to RETURN -1 left it GREEN, because the OTHER raise still matched. Membership is not completeness. Now each guard is pinned by its own message; re-mutated and it reddens 1 of 12.**

---

## Lenses returning clean

- **`test_can_actually_fail`** (beyond Finding 6's discovery): ran
  `dart run scripts/check_usage_counter_source.dart` (`Running build hooks...` then
  `[usage-counter-source] PASS — 5 known EF quota counter(s), 9 known migration(s), no new
  ones.`) and `--list` (baseline: `ai-media-proxy/index.ts:74,96`, `delete-account/index.ts:146`,
  `verify-payment/index.ts:225`, `weekly-report/index.ts:96`; migrations `010, 026, 028, 101,
  111, 113, 114, 120, 127`) against the real tree — matches the allowlists in
  `scripts/usage_counter_source_lib.dart` exactly. Independently ran 2 of the ledger's claimed
  6 mutations against `scripts/usage_counter_source_lib.dart` (widen the quota-filter regex to
  match `.neq`; disable comment-stripping) — each reddened exactly 1 of 12 tests, restored via
  `git checkout --` (a plain `.dart` file, no eol trap — confirmed `git status` clean after).
  Separately re-derived the migration's own 5-mutation/11-test claim (commit message) by
  removing the retention job's epoch exclusion — reddened exactly 1 of 11
  (`usage_counters_infrastructure_test.dart`), matching the claim, then restored per Finding 6.
  Ran the 3 explicitly requested files together: 29/29 pass
  (`flutter test test/contracts/usage_counters_infrastructure_test.dart
  test/contracts/usage_quota_ledger_writer_to_reader_test.dart
  test/scripts/usage_counter_source_lib_test.dart`). Confirmed
  `test/edge_functions/usage_counters_rls_denies_client_test.dart` compiles and SKIPs
  gracefully with no local credentials, and confirmed via `.github/workflows/test.yml:441,465`
  + `SupabaseTestHelper.hasCredentials`/`credentialsComplete` that CI's `supabase-tests` job
  really does run `test/edge_functions/` (not `test/contracts/`, where it would skip forever
  reading green) whenever all 4 Supabase secrets are configured.
- **`live_state`**: verified directly against `dedsavbjuwgarrhphgnl` (confirmed correct
  project via `get_project`): `usage_counters` columns/types/nullability/defaults match the
  migration exactly; PK `(user_id, quota_key, window_start)`; FK
  `usage_counters_user_id_fkey` → `users(id)` with `confdeltype='c'` (CASCADE);
  `relrowsecurity=true`, `relforcerowsecurity=false`; `pg_policies` count = 0; both
  `consume_quota` and `cleanup_usage_counters` have `prosecdef=false` (INVOKER); cron job
  `usage_counters_retention_daily` is `jobid=37`, `schedule='45 3 * * *'`, `active=true`,
  `username='postgres'`, `command=' SELECT public.cleanup_usage_counters(); '` — matching
  CRON_REGISTRY.md's row exactly; confirmed the claimed free 03:45 UTC slot by listing all 29
  active cron jobs sorted by schedule (nearest neighbors genuinely 03:00/03:30/04:22/04:25/
  04:38/04:41, matching the migration's own comment); confirmed all 29 `cron.job` rows have
  `username='postgres'`, matching the migration's claim; confirmed `rolbypassrls`:
  `postgres`/`service_role`=true, `authenticated`/`anon`=false; confirmed `anon` and
  `authenticated` both hold live EXECUTE on `consume_quota` (`has_function_privilege` = true
  for both) yet both are refused **`42501`** calling it live (tested directly, not via the
  client library); confirmed `service_role` write succeeds and increments 1,2,3,4,5 then -1,-1
  against `p_limit=5` (sequential, not the claimed 19-concurrent test — see caveat below);
  confirmed `p_limit=0` returns `-1` and writes no row; confirmed `p_limit=-1` raises
  `P0001: consume_quota: invalid limit -1`; confirmed `usage_counters` is empty (0 rows) both
  before and after all testing (after cleaning up Finding 6's leaked row). **Caveat, stated
  honestly:** I verified sequential atomicity/monotonicity live but did NOT reproduce the
  diagnose-doc's specific "19 concurrent calls returned exactly 1…19" claim — that needs
  genuinely parallel client connections, which a single `execute_sql` MCP call can't produce.
  I have no reason to doubt it (Postgres `INSERT ... ON CONFLICT DO UPDATE` is a well-
  established atomic primitive under MVCC), but I did not independently reproduce that
  specific number and say so rather than claim full verification.
- **`blast_radius_mismatch`**: `git diff --name-only 57706f74..HEAD | dart run
  scripts/blast_radius_from_diff.dart -` → `platform`. Classified the migration file alone
  (on-disk, so the content rule can actually read it — per the row this same batch added to
  CLAUDE.md §4.9 about failing open on nonexistent paths): also `platform`. Confirmed the
  `SECURITY-DEFINER` (hyphenated) dodge is real, not just claimed: `grep -in
  "security.definer|security_definer"` finds exactly one hit, the header's own hyphenated
  phrase; the live rule is `RegExp(r'security\s+definer', caseSensitive: false)`, which
  requires whitespace and does not match a hyphen — and this is not merely a regex dodge,
  since `prosecdef=false` for both functions confirms live that neither actually is DEFINER
  mode. Checked `docs/blast_radius.yaml`'s `platform` tier `requires:` list
  (`regression_test, behavioral_test_path, code_review_b_pass, feature_flag`):
  `regression_test`/`behavioral_test_path` present and verified; `feature_flag` is satisfied in
  substance (the entire feature is "zero call sites", which is a stronger kill-switch than a
  boolean flag); `code_review_b_pass` is the exact gap Finding 1 already covers.
- **`modelled_on_is_a_checkable_claim`**: the plan's citation of
  `test/edge_functions/pgvector_test.dart` as placement precedent for
  `usage_counters_rls_denies_client_test.dart` is accurate — read both files; identical
  `@TestOn('vm')` + `library;` header, identical `SupabaseTestHelper.hasCredentials` skip
  idiom, identical `setUpSucceeded` late-init guard pattern. The CRON_REGISTRY row for job 128
  sharing migration 121's `(intra-DB)` / `n/a` vault-dependency classification is also
  accurate (both are cron jobs with no Edge Function/Vault dependency). Note, stated for
  precision rather than as a finding: migration 121's retention functions are `SECURITY
  DEFINER`, while 128's are deliberately `SECURITY INVOKER` — this is **not** a broken
  "modelled on 121" claim, because no citation in the diff actually claims the security mode
  was copied from 121; the only stated parallel is the registry classification, which holds.
- **`missing_input`** (beyond Finding 1): re-derived the EF allowlist by grepping every
  `count: "exact"` site in `supabase/functions/` (11 total) and manually inspecting each —
  confirmed the 5 sites in `allowedEdgeFunctionSites` are exactly the ones filtered on a
  `channel` `.eq`/`.in`, and the other 6 (evaluate-rank-promotions, i-see-you-callout ×2,
  log-client-error, rolling-context ×2) are correctly excluded (different table, or `.neq`
  prune counts). Re-derived the migration allowlist similarly (`grep -l count(*)` files ∩
  files mentioning `ai_coach_interactions`); the one file that showed up outside the allowlist
  (`066_cleanup_pending_chat_duplicates.sql`) has its `count(*)` only inside a `--`-commented
  verification block, which the gate's own comment-stripping correctly ignores — not a gap.
  Confirmed migration 010's `COUNT(*)` (uppercase) is still caught by the gate's
  `caseSensitive: false` regex, explaining why it's allowlisted despite not appearing in a
  naive case-sensitive grep.
- **`asserted_fixture_value`** (beyond Finding 2): `docs/sot_registry.yaml`'s
  `usage_quota_ledger` entry line ranges (`69-113`, `133-145`) verified byte-exact against the
  migration. `docs/audit/GATE_INDEX.md`'s "Total gates: 97" and the new
  `check_usage_counter_source.dart` row confirmed mechanically fresh via
  `dart run scripts/check_gate_index_fresh.dart` → PASS, not hand-counted. Ran
  `check_gate_test_ledger.dart` (PASS, 96 gates), `check_sot_registry_parity.dart` (PASS, 0
  errors — 1 unrelated pre-existing warning), `check_schema_column_refs.dart` (PASS, 841 refs,
  0 drift), `check_applied_migrations_ledger.dart` (Gate 39, PASS, 134 records),
  `check_cron_registry.dart` (Gate 31, PASS), `check_sot_behavioral_test_paths.dart` (Gate 42,
  PASS, 126 concepts), `check_no_deferral_euphemism.dart` (PASS), `validate_diagnose_doc.dart`
  on the new diagnose-doc (PASS — schema-only, which is exactly why Finding 2 slipped through
  it). All `related_bugs:` IDs in the diagnose-doc (`c9e3b1`, `b8f4c2`, `a9d3f1`, `7ad0d3`)
  resolve to real, existing diagnose-docs with plausible relevance to each cited claim.
  `flutter analyze` on the 6 new/changed non-migration files: clean, 4.8s, none are `part`/
  `part of` files so a scoped analyze is valid here.

## Verification log (commands run, condensed)

```
git log --oneline 57706f74..HEAD ; git diff --stat 57706f74..HEAD
sha256sum supabase/migrations/128_usage_counters.sql   # before/after, see Finding 6
dart run scripts/check_usage_counter_source.dart [--list]
flutter test test/scripts/usage_counter_source_lib_test.dart      # baseline 12/12, then 2 mutations, 1/12 red each, restored
flutter test test/contracts/usage_counters_infrastructure_test.dart   # baseline 11/11, then 1 mutation, 1/11 red, restored (Finding 6)
flutter test test/contracts/usage_counters_infrastructure_test.dart test/contracts/usage_quota_ledger_writer_to_reader_test.dart test/scripts/usage_counter_source_lib_test.dart   # 29/29
flutter test test/edge_functions/usage_counters_rls_denies_client_test.dart   # 1/1, SKIPPED (no local creds)
flutter analyze <6 new files>   # clean
mcp: get_project(dedsavbjuwgarrhphgnl) ; execute_sql × ~20 (schema, constraints, RLS, policies,
  prosecdef, cron.job, pg_roles.rolbypassrls, has_function_privilege, live consume_quota probes
  as service_role/authenticated/anon, cleanup of one leaked test row)
dart run scripts/blast_radius_from_diff.dart - (whole diff, and the migration file alone)
dart run scripts/check_gate_index_fresh.dart ; check_gate_test_ledger.dart ;
  check_sot_registry_parity.dart ; check_schema_column_refs.dart ;
  check_applied_migrations_ledger.dart ; check_cron_registry.dart ;
  check_sot_behavioral_test_paths.dart ; check_no_deferral_euphemism.dart ;
  validate_diagnose_doc.dart docs/diagnoses/2026-09-05-...-d3a7f1.md
```

Final repo state: `git status --porcelain` shows exactly one entry
(`M supabase/migrations/128_usage_counters.sql`), content-verified byte-identical to the
original via sha256 and `git diff` (empty) — see Finding 6. Final DB state: `usage_counters`
has 0 rows (verified after cleanup); no other objects created or left behind.


## Founder triage notes

Triaged 2026-09-05 by the batch author, before the merge. **7 accepted, 0 false_alarm.**
Four fixed in code/docs, three recorded as named limitations or invariants rather than
silently carried. False-alarm rate 0/7.

**What this pass was worth.** The P1 would have failed CI at the merge commit — the keystone
plan-review record simply did not exist yet. And finding 6 is a tooling discovery the batch
could not have made from inside: `git checkout --` is the obvious way to undo a test mutation
and it silently rewrites this file's line endings, breaking the ledger hash while every git
command reports clean. The reviewer found it by doing the natural thing and then checking the
hash anyway.

**Two findings were defects in this batch's own corrections**, which is the pattern worth
noticing: the diagnose-doc citations were captured before a later edit to the same file, and
the test written to close finding 7 was itself defeated by a mutation until its assertion was
made per-guard rather than per-pattern.
