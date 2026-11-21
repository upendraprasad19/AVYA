---
reviewed_at: 2026-09-29T20:30:00+05:30
staged_against: aa246de6496f (staged diff at dispatch; 29 files, +3200/-255, base 628798ec)
blast_radius: platform
reviewer: two fresh context-blind agents (adversarial B-pass, sonnet) — A read-only lenses 1-5,7,10 + hash/SHA/mint semantics; B mutation lenses 6+8 in an isolated worktree from the exported staged patch
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, self_attesting_artifact]
findings_count: 18
verdict: accepted
---

# Code Review (B-pass) — migration-ledger-integrity

Branch `migration-ledger-integrity` (OI-135 / OI-137 / OI-263 + the paired-gate grammar fix): Gate 39
now recomputes ledger hashes (LF-or-CRLF dual form, five drifts grandfathered by pinned sha), a
`refs/heads/mig/N` allocator (`scripts/mint_migration.sh`, CAS core copied from `mint_oi.sh`), and a
reservation gate (`scripts/check_migration_number_reserved.dart`). Dispatched AFTER three plan-review
rounds (the apply-time preflight was cut to OI-272 there — its absence is not a finding), the full
pre-commit gate loop, `flutter analyze`, and the full suite (7182) were green.

**Two reviewers, 18 findings (0 P0, 0 P1, 5 P2, 13 P3); 0 false_alarm. Every finding reached a terminal
state in this batch (14 fixed with a regression test and a mutation, 4 accepted with a stated limit
written into the docs).** Every claim was verified by me against the code before acting on it; the
verdict reflects the state AFTER remediation. Verified-clean claims from both reports were also
reproduced (ledger = 159 entries / 157 real hashes / 2 sentinels; 96 LF-only, 56 CRLF-only, 5 neither;
the 5 pins equal the current LF sha; the SHA-256 matches `sha256sum` on 16 inputs incl. every padding
boundary; Gate 39 resolves all 159 ids; `--next` on a scratch clone of the real tree gives 152).

Reviewer disclosures, kept because the behaviour is worth keeping: (A) ran `mint_migration.sh --next`
once against the REAL repo before noticing it does a `git fetch --prune`, which updated shared
tracking refs (read-only on the remote, no commit/push/stash, staged set unchanged); (B) could not
write its own findings file and returned the report inline. Neither touched a real remote.

## Reviewer A

### A1 — P2 — writer_reader_drift / missing_input
- **file:line:** `scripts/mint_migration.sh` `all_local_branch_numbers`, `do_release`, `do_next`
- **claim:** "filed" was decided from LOCAL branches only. A number filed on a remote-only branch (a cloud session's push) looked UNFILED, `--release` deleted its live reservation, and the next mint re-issued it.
- **verification:** scratch repos: `--next` printed `NEXT=4 UNFILED=3`; `--release 3` released it (rc 0). I re-read the code (only `refs/heads/` was scanned) and reproduced via a new e2e test.
- **status:** accepted — FIXED. `all_branch_numbers` also reads `refs/remotes/<remote>/*` (excluding `mig/*` and `HEAD`). Residual, documented: remote-tracking refs are only as fresh as the clone's last fetch. Test: `--release / --next see a number filed on a REMOTE-ONLY branch`; mutation reddens exactly that test.

### A2 — P2 — blast_radius_mismatch
- **claim:** platform tier `requires: feature_flag`; Gate 39's new hard-fail and the reservation gate ship with no switch and no recorded exemption. (P3 rider: `check_migration_ledger_paired.dart`, whose regex changed, classified `feature`.)
- **verification:** `blast_radius_from_diff.dart -` per path.
- **status:** accepted — DEVIATION STATED in the plan record ("Residual risks"): additive fail-open gates, all 159 real rows verify today, rollback is a revert, a switch on an integrity gate is the lever that lets the defect back in silently. **Flagged for founder veto at merge.** Rider FIXED: paired gate and `migrate_applied_migrations_ledger.dart` pinned platform.

### A3 — P2 — self_attesting_artifact
- **claim:** closure said "13 e2e + 21 lib" (lib had 20); it pointed at a "lease" sentence in the gate ledger that did not exist; 5 mint mutations were recorded nowhere; the plan record's Mutation evidence was a placeholder.
- **verification:** re-ran each test file for real counts (my own first correction was also wrong, so I ran all seven).
- **status:** accepted — FIXED. Counts re-derived by running; the full mutation table (every leg, every red count) lives in the plan record; the CAS-lease limit is stated there.

### A4 — P3 — function_exception_swallow
- **file:line:** `scripts/check_migration_number_reserved.dart` range call
- **claim:** a failed `git diff origin/main...HEAD` (no merge base, shallow clone) was dropped silently and the empty-set path printed "PASS: no added ... files", contradicting the header's own "never a silent pass".
- **verification:** orphan-branch scratch clone: PASS printed while the diff exited 128.
- **status:** accepted — FIXED: a NOTE plus a SKIP in the empty-set case. Test + mutation.

### A5 — P3 — writer_reader_drift
- **claim:** a positive local `mig/N` tracking ref is trusted; a reservation another session `--release`d since is still honoured until the next fetch.
- **status:** accepted as the contract ("existence as of the last sync") — the alternative is an ls-remote on every commit that adds a migration. Documented in the gate header and `supabase/migrations/CLAUDE.md`; Gate 14 is the merge-time backstop.

### A6 — P3 — missing_input
- **claim:** `--reserve N` accepts any 1..999, so `--reserve 900` moves next-free to 901.
- **status:** accepted — documented in the script header and `supabase/migrations/CLAUDE.md`; `--release 900` undoes it. Unbounded on purpose (adopting a number already in use).

### A7 — P3 — writer_reader_drift (prune vs letter suffix)
- **claim:** `names_to_numbers` maps `003b_` to 3, so a published follow-up made its BASE look published; `--prune` (and the API-transport auto-prune) then deleted `mig/3` while `003_*.sql` was still unmerged, and the gate would then fail the branch that legitimately holds it.
- **verification:** scratch: `--reserve 3`, publish `003b_`, `--prune` printed "pruned 1"; I confirmed the reachability from the gate's own letter-suffix leg.
- **status:** accepted — FIXED: `published_base_numbers` (unsuffixed only) for PRUNE; `next_free`/`--release` keep the wider, more conservative reading. Test with a positive control (publishing the base then prunes it) + mutation.

### A8 — P3 — self_attesting_artifact (Extra A)
- **claim:** the dual form is slightly wider than "same content, either ending": `a\r\r\nb` is accepted against the pure-LF hash because `toLf` collapses only the final `\r\n`.
- **status:** accepted — documented in `supabase/migrations/CLAUDE.md`. Lone `\r`, empty input and missing trailing newline are handled exactly; a trailing-newline difference is NOT accepted.

### A9 — P3 — self_attesting_artifact
- **claim:** the plan record called "Decisions" authoritative but still specified the cut preflight, the branch-mismatch WARN and mutations (h)-(m).
- **status:** accepted — FIXED: each marked "CUT → OI-272" in place.

### A10 — P3 — writer_reader_drift (docs/coverage)
- **claim:** (a) a passing `--live` reads as full coverage though 69 of 145 live rows are unprefixed; (b) root CLAUDE.md §4.9 still teaches an `ls | grep | sort` recipe for the next number; (c) `new-worktree.sh` pre-fetches `oi/*` but not `mig/*`.
- **verification:** read the lines; `git grep -n "mig/\*" scripts/new-worktree.sh` found nothing. **(c) was a claimed-fixed-not-landed case: the plan record's round-1 F4 says the fetch line "gains `+refs/heads/mig/*`" and it never did.**
- **status:** accepted — FIXED all three: reduced `--live` NOTE (test asserts it), §4.9 sentence ("read-only recipe; to allocate use the mint"), refspec added to both `new-worktree.sh` fetch lines (`new_worktree_base_test.dart` still green).

## Reviewer B

Baseline 7 files green; `git apply --index` of the staged patch applied cleanly; ~70 mutations, each confirmed applied (occurrence count 1) and restored byte-for-byte; no red was a compile error. Reproduced the author's counts for Gate 39 (CRLF removed 5, LF removed 12, stale 2, sentinel 2), paired (1 each) and reserved (published-skip 2, collision 3, grandfather 1, letter base 3, offline 2).

### B1 — P2 — guard_without_its_mirror
- **claim:** `--no-renames` guards two calls (staged and committed-range) but only the staged half was tested; a COMMITTED `git mv 003 004` dodged the range check. The ledger's "`--no-renames` dropped 1 red" covered half the guard.
- **verification:** mutation on the range call: 0 of 33 red; a probe (commit the rename, expect exit 1) was green on shipped code and red under the mutation.
- **status:** accepted — FIXED: e2e `a COMMITTED rename cannot dodge the range check either` (mutation g1: 1 red).

### B2 — P3 — guard_without_its_mirror
- **claim:** three-dot -> two-dot undetected; a file origin/main deleted after the fork would read as an add (false FAIL).
- **status:** accepted — FIXED: test where origin/main deletes 003 after the fork and the branch adds a reserved 004 (mutation g2: 2 red).

### B3 — P2 — guard_without_its_mirror / asserted_fixture_value
- **claim:** the "--stub ... refuses to overwrite" test's tail re-reserves an already-taken number, so it exits 3 at the CAS and never reaches `write_stub`; the no-clobber guard had no test though the comment said it did.
- **verification:** `if [ -e "$f" ]` -> `if false`: 0 of 23 red. I confirmed the only reachable path is adoption of a FREE number whose file exists.
- **status:** accepted — FIXED: adoption test (`--reserve 10 --stub x` beside a hand-written `010_x.sql`); the misleading tail comment corrected (mutation n1: 1 red).

### B4 — P3 — guard_without_its_mirror
- **claim:** `contains_line`'s exact-line `-x` untested (no fixture has a number that is a substring of another).
- **status:** accepted — FIXED: reserve 15 beside a `150_*.sql` file; `--release 15` must succeed (mutation n2: 1 red).

### B5 — P3 — guard_without_its_mirror (nine untested mint guards)
- **claim:** 10-race give-up, 999 exhaustion, mid-retry sync failure, explicit tracking-ref update, API post-mint prune, `--next` working-tree-ledger leg, `--next` origin/main-tree leg — each applied, 0 red; the CAS lease is parity-only.
- **status:** accepted — FIXED: one test each (mutations n3-n9, 1 red apiece). The give-up test's hook is counter-bounded so a mutant fails an assertion instead of hanging; the mid-retry test needed a fixture correction I found by reading the failure (breaking the fetch URL also broke the existence probe, a different exit-2 path — now a `.lock` on the tracking ref with `main` advanced). **The CAS lease stays PARITY-ONLY (2 red, every behavioural e2e green), stated in the plan record:** a non-fast-forward reject is also classified as taken. The parity test additionally pins the literal `--force-with-lease="refs/heads/mig/$1:"` independently of `mint_oi.sh`.

### B6 — P3 — guard_without_its_mirror (Gate 39 lib)
- **claim:** pin compare on raw bytes (fixtures LF-only), the resolver's `.sql` filter, and a null `hash` in the lib were all 0-red; `all_*` exclusion is exercised only via the contrived id `all`.
- **status:** accepted — pin/`.sql`/null-hash FIXED (l1 1 red, l2 1, l3 3). The `all_*` exclusion is defence-in-depth for a contrived id, accepted; A5/A6b (stale-exemption, ambiguity) are lib-level by design.

### B7 — P3 — guard_without_its_mirror (reservation gate)
- **claim:** the `mig/N` regexp's end anchor (`mig/4x`), the base-published-from-files leg and the local-refs-first path were 0-red.
- **status:** accepted — FIXED: l4 (1 red), l5 (1 red), g3 (1 red — local ref honoured with the remote unreachable and NOT reported as skipped). The stale-local-ref trust is the accepted contract (A5).

### B8 — P3 — asserted_fixture_value / self_attesting_artifact
- **claim:** denominator "61 of 147" stale (real: 61 of 157); plan-record frontmatter still pending; `check_migration_ledger_paired.dart` / `migrate_applied_migrations_ledger.dart` unpinned; `migration_ledger_hash.dart` (the documented writer) had no test running it. NOT verified by B: the "69 of 145 live rows unprefixed" figure (no live access).
- **status:** accepted — FIXED: denominators corrected (closure + CLAUDE.md §7), both scripts pinned platform, new `migration_ledger_hash_cli_test.dart` (4 tests; mutations c1, c2). The live figure is my own `list_migrations` measurement earlier this session and is stated as measured, not re-derived. Frontmatter flipped only after the final gate loop and full suite were re-run green.

## Founder triage notes

Two decisions are yours, both recorded in the plan record: (1) **D2** — the five drifted ledger hashes
(057, 069, 070, 108, 123) are grandfathered by pinned sha rather than re-stamped; (2) the **platform
`feature_flag` deviation** (A2). Nothing is committed or pushed.
