---
bug_id: e9b3c7
date: 2026-11-07
batch: retire-golden-failures-allowlist
status: fixed
blast_radius: platform
related_bugs: [d7b3e9, f2a9c7, b4d7e9, a9c4f2, b7d4c8, 8f3e35]
recurrence: >
  SIXTH instance of the retire tool refusing a worktree because a gitignored path that this repo's
  own tooling writes was absent from `regenerableIgnoredPaths`, and the THIRD recorded time THIS
  exact directory has held a merged worktree (2026-09-27, 2026-09-28/29, 2026-11-06, each cleaned by
  hand with `rm -r`). d7b3e9 (2026-08-10) built the list and the exact-match rule. f2a9c7
  (2026-08-25) found that test output blocked any worktree that ran the suite, and in doing so
  wrote down that `test/goldens/**/failures/` is "genuinely regenerable, but a PATTERN" and
  therefore left it out. b4d7e9 (Stop marker) and a9c4f2 (CI queue) were two more producers found
  the same way, by a worktree that would not retire. b7d4c8 (`deno.lock`) was the contradiction
  between the two lists. 8f3e35 is the same shape on the hook side. This one was not a new
  producer: it was the producer f2a9c7 named and deliberately did not fix.
symptom: >
  `dart run scripts/retire_worktree.dart <slug>` prints
  `KEEP    cron-log-retention-oi199-oi471  [1 non-regenerable ignored file(s) ...]` for a worktree
  whose branch is merged, whose tracked tree is clean and which has nothing unpushed. The
  message states a COUNT and never a path. The one path was `test/goldens/wardroom/failures/`
  (8 PNGs of comparator output), left by a full local `flutter test` on the Linux VPS without
  `--exclude-tags golden` (CI passes that flag; the committed baselines are Windows-rendered, so
  the comparison always mismatches on Linux). The operator then had to find the path by hand with
  `git status --porcelain --ignored=matching` and delete it before the retirement the founder had
  already asked for could run.
concept: >
  Exact-match allowlists and glob-ignored output. `.gitignore:193` ignores the comparator output
  with the GLOB `test/goldens/**/failures/`. The matcher cannot accept a glob (d7b3e9's three
  review rounds each found a P0-class variant of looser matching; f2a9c7 and b4d7e9 cite them), and f2a9c7 concluded that this meant the directory
  could not be listed at all. That conclusion confused the PATTERN with what git EMITS for it.
  The tool enumerates with `git status --porcelain --ignored=matching`, which collapses an ignored
  directory to ONE concrete line, `!! test/goldens/wardroom/failures/`, however many PNGs it holds.
  That concrete string is exact, and listing it keeps the matcher exact. The repo already does
  this twice: `*.log` is covered by listing `.claude/.gate_failures.log`, and the bare name
  `GeneratedPluginRegistrant.java` by listing its one real deep path. The golden directory was the
  one glob-produced path the list refused to take, on a rule that was never needed.

  A first diagnosis of the 2026-11-06 hold in this same session was wrong in the other direction:
  it named TWO paths (the golden directory and the generated plugin registrant) from a plain
  `git status --ignored`, which collapses directories differently from the tool's
  `--ignored=matching`. The registrant was already allowlisted by exact path. The fix is scoped
  from the tool's own enumeration, not from that listing.
sot_registry_entry: not_applicable
sot_registry_note: >
  Worktree retirement is operator tooling, not a data concept: no writer/reader pair in
  `docs/sot_registry.yaml`, no Hive key, no cloud column. CLAUDE.md §4.13 point 6 is its contract.
writers:
  - { file: test/goldens/wardroom/ward_rank_pill_golden_test.dart, method: "matchesGoldenFile('goldens/ward_rank_pill_lt.png') hands the comparison to the Flutter SDK's LocalFileComparator (packages/flutter_test/lib/src/_goldens_io.dart, Flutter 3.41.4, generateFailureOutput at line 141), which on a mismatch writes <testName>_masterImage/_testImage/_isolatedDiff/_maskedDiff.png into `<directory of the test file>/failures/`", line: 89 }
  - { file: .gitignore, method: "the GLOB `test/goldens/**/failures/` that makes the directory invisible to `git status --porcelain`, which is why leg 3 exists and why the tool sees it only through --ignored=matching", line: 193 }
readers:
  - { file: scripts/retire_worktree.dart, method_or_widget: "leg 3: `git status --porcelain --ignored=matching`, one `!!` line per ignored directory, each passed to isRegenerableIgnored; every miss increments the blocking count", line: 288 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "regenerableIgnoredPaths: the exact-match list; the new entry is the concrete directory string", line: 342 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "isRegenerableIgnored: backslash normalisation then List.contains, nothing else", line: 350 }
  - { file: test/scripts/gitignore_classification_test.dart, method_or_widget: "the second-suite guard: every directory under test/goldens holding tests must have `<dir>/failures/` listed", line: 204 }
hive_key_prefix: null
hive_key_formula: "not_applicable: no Hive involvement; the directory is plain files on disk."
sync_methods: not_applicable (operator tooling, no cloud fan-out).
restore_methods: not_applicable (nothing is restored; the next failing golden run rewrites the directory).
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/retire_worktree_lib_test.dart
ist_handling:
  - { file: scripts/retire_worktree_lib.dart, line: 342, fn: "not_applicable: a path allowlist, no date key and no counter reset." }
provider_invalidations: none (no client state).
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable. Retirement removes a worktree only after its branch is merged (leg 1), the tracked
  tree is clean (leg 2) and nothing is unpushed (leg 4); this fix widens leg 3 by exactly one path.
forbidden_patterns_checked: >
  - EXACT match preserved. The matcher is untouched (`isRegenerableIgnored` is byte-identical);
    only a list entry is added. The lib test pins eighteen near-misses that must keep BLOCKING: a file
    inside the directory (both separator spellings), no trailing slash, the parent, grandparent and
    great-grandparent, the TRACKED baselines directory `test/goldens/wardroom/goldens/`, another
    suite, a path-prefixed copy, a name-extended `failures-old/`, a `failures.bak/` form, a
    different-case form and six spellings git never prints (`./`, `/`, doubled slashes, a dot
    segment), so the matcher cannot be taught to tidy a path into the listed string.
  - No pattern or glob entry added. The glob `test/goldens/**/failures/` is still unclassifiable;
    mutant (c) puts it in the list and is killed.
  - A second golden suite is NOT inherited. The e2e fixture holds a worktree with
    `test/goldens/zzsuite/failures/x.png` (fictional name) that must still be KEPT and survive
    byte-intact after `--execute --all`.
  - The tracked baselines are not touched: they live in the sibling `test/goldens/wardroom/goldens/`,
    whose path is pinned as blocking.
  - Hand-saved files: a file a human saves by hand into the `failures/` directory is now deleted
    with its worktree. Accepted: the directory is the comparator's per-run output and is ignored
    precisely because it is "never source" (the comment at .gitignore:190-192).
proposed_fix: >
  Add `'test/goldens/wardroom/failures/'` to `regenerableIgnoredPaths`, replacing the "DELIBERATELY
  ABSENT" comment with the evidence for the entry. Add the class guard that makes the next golden
  suite impossible to land unlisted. Correct the `.gitignore:190` comment, which attributed the
  writer to `golden_toolkit`: the writer is the Flutter SDK's own comparator (the project's golden
  tests call `matchesGoldenFile`), and a wrong writer is what sends the next reader to the wrong
  package when asking what else may write there.
regression_test_planned:
  - test/scripts/retire_worktree_lib_test.dart
  - test/scripts/retire_worktree_e2e_test.dart
  - test/scripts/gitignore_classification_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ file touched; scripts/ tooling and tests only." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes the directory." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table, no policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "The directory holds four image kinds per failed comparison (master, test, isolated diff, masked diff) and nothing else; no script, hook or CI file writes into it (checked by grep over scripts/, .github/, .claude/ and test/ before the plan). The exact-match rule is preserved because earlier rounds destroyed real secrets through looser matching (.envrc, .envs/, supabase/.env)." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service in the path." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed." }
impact_analysis: >
  Product impact ZERO: no user-facing code path. The cost is operational: every merged worktree
  that ran the full local suite on the VPS stayed unretirable until someone found one path by hand
  and deleted it, and the founder had asked for that retirement each time. Three holds were
  recorded (2026-09-27, 2026-09-28/29, 2026-11-06). The recurrence dates live in the maintainer's
  session notes, not in the repo, and were not independently re-verified here.

  WHY IT WAS NOT CAUGHT. The 2026-09-04 class guard (`gitignore_classification_test.dart`)
  partitions every LITERAL .gitignore entry and, by design, skips globs; the header said so out
  loud. f2a9c7 recorded the golden directory as a known exclusion. So the one path the guard was
  blind to by construction was the one that recurred three more times. A decision recorded as
  "stays out" with no test that the reason still held is a decision nobody revisits.

  WHAT CHANGED THE ANSWER. Reading the tool's own enumeration (`retire_worktree.dart:288`) instead
  of re-deriving it: `--ignored=matching` prints ONE exact line for the directory. The objection
  (a pattern cannot be matched exactly) does not apply to the string git emits.

  SUPERSEDED STATEMENTS, named so a later reader does not follow them. The historical records are
  not rewritten (closed_issues.md is append-only and the older diagnose docs are dated evidence);
  this doc is the correction: the lib comment block that read "DELIBERATELY ABSENT" (replaced in
  this change); the `gitignore_classification_test.dart` header sentence that put the golden
  directory with the unclassifiable globs (reworded in this change); f2a9c7's `proposed_fix` and
  its line 74 (`test/goldens/**/failures/ ... is a PATTERN`); a9c4f2's `forbidden_patterns_checked`
  (line 73, "remain unclassifiable"); `docs/audit/closed_issues.md:1329-1331` (OI-128's
  "genuinely regenerable but a pattern"); and `docs/plans/auth-recovery-code-length.md:219`, which
  describes the `rm -r` workaround. The class stays listed under the sixth instance in
  `.claude/skills/debugging/bug-classes.md`.

  RESIDUAL RISK, stated rather than implied. (1) A suite whose golden tests live OUTSIDE
  `test/goldens/` writes its `failures/` next to the test file, which `.gitignore:193` does not
  cover; the tool then sees an untracked directory through leg 2 (dirty), which keeps the worktree.
  That is the safe direction. (2) The guard counts EVERY `_test.dart` under `test/goldens/`,
  not only files that name the comparator (the first version filtered on three symbol names and the
  B-pass showed it was blind to a golden test that reaches `matchesGoldenFile` through a helper kept
  outside the directory). The cost is a harmless extra list entry for a directory that never
  writes `failures/`. (3) The Windows spelling of the tool's
  behaviour is reasoned from the matcher's backslash normalisation and pinned in the lib test; it
  was not run on Windows.
mutation_evidence: >
  Rule 21 mutate-it-and-run-it, self-attested (the tests were written by the author of the fix).
  The matrix was run twice: once before the independent B-pass and once, in full, after its fixes
  changed the tests (the second run is the one recorded here). Fifteen mutants, each applied to a
  copy-restored backup, confirmed APPLIED by a byte comparison against the backup (all differed),
  run against all three test files with `flutter test` (TZ=Asia/Kolkata), and restored
  byte-identical (`cmp`) after every one. Counts are failed tests, lib / e2e / classification, from
  a clean baseline of 52 / 20 / 12 green:
  (a) delete the list entry: 1 / 2 / 1, the classification failure being the second-suite guard.
  (b1) `|| p.startsWith('test/goldens/wardroom/failures/')`, (b2) `|| p.contains(...)`,
  (b3) `|| p.endsWith('wardroom/failures/')`, (b4) the reversed `'...'.startsWith(p)` (parents),
  (d) `|| p.toLowerCase() == '...'`, (e) startsWith without the trailing slash, (f)
  `|| p.startsWith('test/goldens/wardroom/')`: each 1 / 0 / 0. These are killed only by the lib
  near-miss test, by design (the e2e fixture's second suite sits outside the wardroom paths these
  widenings match). That test loops over eighteen near-misses, so a mutant reddens at its first
  one. (c) the glob `test/goldens/**/failures/` in the list instead of the concrete path: 1 / 2 / 1.
  (g) a regex matcher `^test/goldens/[^/]+/failures/$` (any suite): 2 / 2 / 0, killed by the lib
  near-miss, the retained other-suite pin AND the e2e `goldhome` worktree. (h) the entry without its
  trailing slash: 1 / 2 / 1. (i) delete the glob line at .gitignore:193 (replaced by a comment, same
  line count): 0 / 0 / 2, both `git check-ignore` pins. (j) the six spellings git never prints
  (`./...`, `/...`, `//` twice, trailing `//`, a `/./` segment) accepted by an entry-scoped set:
  1 / 0 / 0; this one SURVIVED the first matrix and the B-pass found it, so six such spellings are
  now in the near-miss list. (k) a sibling entry for the TRACKED baselines directory
  `test/goldens/wardroom/goldens/`: 1 / 0 / 0 (only the near-miss pin stands between the baselines
  and the allowlist; leg 2 of the tool, tracked changes, is independent of the list). (l) whole-
  matcher trailing-slash normalisation: 2 / 0 / 0 (the new near-miss test and the pre-existing
  `supabase/functions/.dart_tool/` test). Sanity run (m), pre-listing `test/goldens/home/failures/`
  as a future real suite would: 0 / 0 / 0 on purpose, since the other-suite pins now use the
  fictional `zzsuite` and no unrelated test reddens when a real suite adds its entry (before the
  fix the old `home` pin reddened the unrelated Stop-hook-marker test). Two further checks added a
  fictional `test/goldens/zzsuite/zz_golden_test.dart` containing `matchesGoldenFile` (first
  version of the guard) and, after the widening, `test/goldens/zzwrap/zz_helper_driven_test.dart`
  containing no golden symbol at all (a test that reaches the comparator through a helper): both
  reddened the guard and named the missing directory; the files were removed afterwards
  (`git status test/goldens` empty). No mutant survived the final matrix. Not mutated: the Windows
  separator branch beyond the lib assertions, and the e2e self-check block (a broken fixture throws
  in setUpAll, reddening every test in that file at once).
---

# e9b3c7: the golden comparator's `failures/` directory kept every worktree that ran the full suite

## What happened

On 2026-11-06 the retire tool refused the merged, clean, fully pushed worktree
`cron-log-retention-oi199-oi471` with `[1 non-regenerable ignored file(s)]`. The count is all it
says. The path was `test/goldens/wardroom/failures/`, eight PNGs written by the Flutter test
comparator during a full local `flutter test` on the Linux VPS run without `--exclude-tags golden`.
The committed baselines are Windows-rendered, so on Linux the comparison always mismatches and the
comparator always writes its diff images. CI passes `--exclude-tags golden`, which is why CI never
sees it. The same hold had already happened on 2026-09-27 and 2026-09-28/29.

## Why the refusal was correct and still wrong

Leg 3 fails closed: a gitignored path absent from the exact-match list is precious. That direction
is right, and d7b3e9's three review rounds each found a P0-class variant of loosening it (f2a9c7 and b4d7e9 cite them). What was wrong was
the list, and the stated reason for the gap: the directory is a GLOB in `.gitignore`, and an
exact-match list cannot take a glob. But the tool never sees the glob. It sees what
`git status --porcelain --ignored=matching` prints, and for an ignored directory that is one exact
line, `!! test/goldens/wardroom/failures/`.

## The fix

One list entry, the concrete directory string, with the matcher left byte-identical. The same move
already carries `*.log` (via `.claude/.gate_failures.log`) and the bare name
`GeneratedPluginRegistrant.java` (via its one deep path).

Three tests protect it, from different sides:

1. `retire_worktree_lib_test.dart`: the string is TRUE; eighteen near-misses stay FALSE, so a
   later change to prefix, contains, suffix, glob or case-insensitive matching reddens.
2. `retire_worktree_e2e_test.dart`: a real git repo whose fixture `.gitignore` carries the real glob.
   A worktree holding `test/goldens/wardroom/failures/x.png` is retired by `--execute --all`; a
   worktree holding `test/goldens/zzsuite/failures/x.png` is KEPT with the anchored reason and
   survives byte-intact. A setUpAll self-check reads the tool's own enumeration and fails the
   fixture if git does not emit the exact `!!` line, so the scenarios cannot pass vacuously.
3. `gitignore_classification_test.dart`: `git check-ignore` confirms git really ignores both the
   file and the directory string via `.gitignore:193` (delete the glob and the allowlist would call
   an unignored directory regenerable), and a guard walks `test/goldens/` and requires a listed
   `failures/` entry for every directory that holds a `_test.dart`, so the next suite cannot land
   unlisted.

## Class lesson

Do not stop at "it is a pattern". Ask what the TOOL actually receives. A rule recorded as a
reason for exclusion needs a test that the reason still holds, and a first diagnosis of a
blocked-retirement symptom has to come from the tool's own enumeration command, not from a
similar-looking one.
