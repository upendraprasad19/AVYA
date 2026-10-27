---
reviewed_at: 2026-10-12
staged_against: 9476cfe014d2 (reviewed, before the fixes below), aca5136156fd (the tree with every fix below applied; the file name)
blast_radius: platform
reviewer: claude-sonnet-via-skill (1 fresh context-blind reader, read-only, exhaustive command list)
lens_set: [writer_reader_drift, guard_without_its_mirror, secrets_in_tree, L8, L17, L25, L41, deferral_phrases]
findings_count: 6
verdict: accepted
---

# Code Review - `rolling-context/**` and `_shared/purge_user_storage*.ts` become catastrophic tier (registry rules + tests)

Diff reviewed: the staged change on branch `blast-radius-data-deleting-paths`: two rules in `docs/blast_radius.yaml`
(`supabase/functions/rolling-context/**` and `supabase/functions/_shared/purge_user_storage*.ts`, both catastrophic, above
the `_shared/**` and `supabase/functions/**` platform rules), the new contract test, a new group in
`review_gate_staged_content_not_working_tree_test.dart` that runs the real commit-time gate in an isolated temp repo, four
new cases in `plan_review_record_gate_e2e_test.dart`, the `line_range` and index-key edits in `docs/sot_registry.yaml`, and the
plan. One fresh reader, read-only, after two plan-review rounds (each: no P0/P1; their findings were verified and folded
before this pass). Headline: **no P0, P1 or P2; six P3.** The two rules, their order, all four registry readers, every test
and the line cites held up; the reader ran all four test files (19, 12, 10 and 20 passing) and `flutter analyze lib/` (0
warnings, 0 errors). All six P3s were verified against the tree by the main thread and fixed in this batch.

## Checked and clean (what the reader ran, and why the lens came back clean)

- **Which rules claim the two paths** (`git show :docs/blast_radius.yaml`): `rolling-context/index.ts` matches :64 (catastrophic,
  wins) then :536; `_shared/purge_user_storage.ts` matches :73 (catastrophic, wins), then :89 and :536. Every rule above :73 is
  catastrophic; no glob in the registry starts with a wildcard, so nothing else can claim either path.
- **The four glob engines** (`blast_radius_from_diff.dart`, `check_code_review_pass_exists.dart`, `check_blast_radius_coverage.dart`,
  `check_plan_review_record_exists.dart`) compile identically except the keystone's `dotAll: true`. `rolling-context/**` ->
  `^supabase/functions/rolling-context/.*$`; the purge glob -> `^supabase/functions/_shared/purge_user_storage[^/]*\.ts$`
  (no subdirectory, no `.md`, no `.ts.bak`, no prefixed name). The header's dotAll and C-quoting claims are accurate.
- **Vacuity.** Every "lone staged" test asserts exit 1 AND the string `requires a STAGED review file`; a `.ts` probe cannot trip the
  SECURITY DEFINER content rule, so the failure can only come from the path tier; the feature-file control asserts
  `PASS: max blast-radius = feature`; the mixed test has neighbours sorting before and after, so a first-wins or last-wins
  gate exits 0. The keystone no-hermes cases assert the exact message and the hermes control passes. Disk-derived lists are
  non-empty or `containsAll` guarded; the gate-reader test uses the gate's public `parseRules`/`globToRegExp`.
- **Machine hazard in the new temp-repo group.** `stageOnly` copies the setup of the groups above it (the isolated-directory
  check before `git init`, `_git` with `-C` and the scrubbed spawn env, the same two-script copy), never commits, and never
  touches shared config. After the runs `git rev-parse --is-bare-repository` is `false`, `git status` is unchanged and no
  temp directory is left in `/tmp`.
- **The derived scan, run and read:** it finds exactly the four known files; an independent grep returned the same four code lines
  plus two comment lines the scan strips; no `DELETE FROM` exists in any non-test source; no `/*` sequence can make the comment
  stripper swallow a real call; `admin-wipe-storage` is an 8-line disabled stub.
- **Claims verified against code:** the `rolling-context/index.ts` lines (:33-34, :393, :395-398, :411-413, :421-428, :432-433,
  :439-440, :492-511, :517, :520-523), `purge_user_storage.ts` (153 lines, `.remove(` at :119, a comment at :114),
  `delete-account/index.ts` (:29, :30, :357, :373), the six behavioural Deno tests plus the five-name equality, `CRON_REGISTRY.md:38`,
  `runbook_deploy_verify_jwt_test.dart:78`, the gate cites, the history counts (19 commits, 4 recent touching 6, 4, 5 and 8 function
  directories; one commit for the purge files), OI-334 and deploy skill 6.13, the registry before/after line numbers, and that every
  helper named as a shared input is imported by other functions.
- **Drift (L25):** no CLAUDE.md, architecture doc, runbook or skill states a tier for either path or counts the catastrophic rules;
  the only line-number cites into the registry are in historical documents. **Secrets:** a grep of the added lines for `sk-`,
  `rzp_live`, `AKIA`, `-----BEGIN`, `service_role` found nothing; `git diff --cached --check` is clean. **Deferral phrases:** none.
  **`line_range`:** `39-536` is in bounds (547 lines); the parity gates only bounds-check it.

## Findings

All six are P3, all accepted, all fixed in this batch.

### Finding 1 - P3 - guard_without_its_mirror (the derived test had blind arms) - status: accepted, fixed
- **file:line:** `test/contracts/blast_radius_data_deleting_paths_catastrophic_test.dart` (the derived group).
- **Evidence:** (a) no file uses `DELETE FROM`, so dropping that arm, or flipping `caseSensitive`, reddened nothing; (b) only
  `_test.ts` was excluded, but `_shared/sanitize_for_prompt.test.ts` shows the `.test.ts` convention exists here; (c) a raw
  `fetch(..., { method: "DELETE" })` was not scanned (`delete-account/index.ts:325` already makes one).
- **Fix applied:** the matcher is a pure top-level regex with a raw-HTTP-DELETE arm, `_isTestSource` covers both conventions, and
  a literal self-check test pins seven forms that must match, five look-alikes that must not, and the test-file predicate. Verified by
  four mutants (drop the `DELETE FROM` arm, the HTTP arm, the `.remove(` arm, the `.test.ts` convention): all four redden. The plan's
  caveat now says direct calls only (an RPC or another library is not detected).
- **verification:** `git grep -nE 'method:\s*["'"'"']DELETE' -- supabase/functions ':!*_test.ts' ':!*.test.ts'` returns only `delete-account/index.ts:325`.

### Finding 2 - P3 - writer_reader_drift / L8 (the SoT index did not list the new pin) - status: accepted, fixed
- **file:line:** `docs/sot_registry.yaml`, concept `blast_radius_registry_coverage`.
- **Fix applied:** added `behavioral_test_path_data_deleting_paths: test/contracts/blast_radius_data_deleting_paths_catastrophic_test.dart`
  after the sibling key; plan section 2 says so.

### Finding 3 - P3 - false claim in a header - status: accepted, fixed
- The test header said "Five layers"; the file has six (the derived group). Now six, with `5. DERIVED`.

### Finding 4 - P3 - overclaim in the registry comment - status: accepted, fixed
- `docs/blast_radius.yaml` said "The two other paths that delete user data"; live SQL in migrations also deletes rows (named in the plan).
  Now "The two other Edge Function paths that delete user data".

### Finding 5 - P3 - L41 cross-document consistency, and a weak stated reason - status: accepted, fixed
- `docs/operations/CRON_REGISTRY.md:38` said only "Nightly AI context rebuild" while the `clean-orphan-media` row says "DELETES Storage
  objects". The plan had declined to edit it because the file "is parsed by `check_cron_registry.dart` and a snapshot gate"; the reader
  showed that is false for the description cell (`check_cron_registry.dart:105,107` only tests that each job NAME occurs; the
  unbounded-reads gate reads the Function column only). **Fix applied:** the row now says it deletes summarised `ai_coach_interactions`
  turns (last cell only, no `|`); the cron-registry gates and the four tests that read the file pass; the plan's reason was corrected.

### Finding 6 - P3 - no_deferrals accounting (process) - status: accepted, fixed in the plan
- The plan's "raised, not decided" items had no terminal states. **Fix applied:** plan section 6 now carries a terminal-state table
  (`blocked_on_user` for the rename/non-ASCII commit-gate hole, the migration deleters and the bucket-list test blind spots, each with
  the reason; `closed_in_commit` for the CRON_REGISTRY row; `verified_clean` for the redundant purge control). The OI for the commit-time
  hole is not minted: `scripts/mint_oi.sh` pushes a reservation ref and waits for the founder's go. Also fixed, not counted as findings:
  the upsert region is :492-511, and the plan's re-derivation command also prints two comment lines.

## Not verified (by the reader)

- The plan's "measured with `dart run`" outputs (the reader may not run `dart run`; it derived the base-platform claim from the registry
  order, and the main thread ran the classifier). The recorded mutation results (the plan-review record lands in a later commit). The
  analyzer on the three test files (the main thread ran it: 0 warnings, one info on a prefix name copied from the sibling test).
  The rename and non-ASCII reading (the main thread reproduced it with a temporary index file). The Deno job (CI only). The
  founder's chat words "okay catastrophic" (not in the tree; the decision is recorded in paraphrase at `docs/plans/oi320-referrer-cap.md:77`).
