---
bug_id: c7d2e4
date: 2026-09-19
batch: gate-integrity Task 3 (OI-195)
status: fixed
blast_radius: platform
concept: sot_registry_behavioral_test_path_resolution
sot_registry_entry: null
writers:
  - { file: docs/sot_registry.yaml, method_or_widget: "behavioral_test_path: values — 138 keys across 140 concepts, incl. the sibling behavioral_test_path_cqrs: at :826 and the 8-space-indented key at :4219", line: 49 }
  - { file: docs/sot_registry.yaml, method_or_widget: "presence_only: true trailing prose citing repo paths (test/sql/oi153_pro_media_caps_live_verify.sql, supabase/functions/ai-media-proxy/index_test.ts)", line: 10551 }
  - { file: docs/sot_registry.yaml, method_or_widget: "presence_only_reason: | block scalar citing two Deno test files", line: 6082 }
readers:
  - { file: scripts/check_sot_behavioral_test_paths.dart, method_or_widget: "_missingOnDisk — the ONE helper both sinks resolve through (pre-fix: no reader of the referent existed; :103-114 read the field's SHAPE only)", line: 75 }
  - { file: scripts/check_sot_behavioral_test_paths.dart, method_or_widget: "btpMatch branch — comment-strips the value, widened to behavioral_test_path(_<suffix>)?, resolves it", line: 182 }
  - { file: scripts/check_sot_behavioral_test_paths.dart, method_or_widget: "checkProsePaths — repo-shaped paths in presence_only prose / presence_only_reason bodies", line: 155 }
  - { file: scripts/check_sot_behavioral_test_paths.dart, method_or_widget: "problems = [...staleRequired, ...missing, ...missingFiles] — strict exit 1, --warn-only exit 0 naming the miss", line: 252 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/scripts/sot_behavioral_test_paths_gate_test.dart
ist_handling:
  - "No date surface touched — gate-script change only."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — commit-time gate over a docs/ YAML file; no user data, no production read or write path touched."
forbidden_patterns_checked:
  - { pattern: "satisfying the gate by DELETING a citation instead of resolving it", absent: true, evidence: "docs/sot_registry.yaml is untouched by this commit (git diff --stat names only the gate, its test, and this doc); the real registry passes with 138 + 4 paths resolved, 0 missing" }
  - { pattern: "a second existence helper (one per sink) that would let one sink regress behind the other's green", absent: true, evidence: "grep -n existsSync scripts/check_sot_behavioral_test_paths.dart -> 3 lines: a header comment (:46), _missingOnDisk (:76), the registry-file guard (:109); the only path-resolving call is _missingOnDisk and both sinks route through it" }
  - { pattern: "asserting on the word WARN in the warn-only test ([Gate 42 WARN] PASS: already contains it)", absent: true, evidence: "the warn-only test asserts exit 0 AND contains('ghost_test.dart')" }
  - { pattern: "Platform.resolvedExecutable as the spawn binary (flutter_tester -> hang)", absent: true, evidence: "dartBinOf() copied verbatim from test/scripts/cron_registry_snapshot_gate_test.dart" }
  - { pattern: "registering a git-free fixture in test/contracts/gate_e2e_env_hermetic_test.dart", absent: true, evidence: "_helpers const untouched; hermetic gate 11/11 green" }
  - { pattern: "--no-verify or gate bypass", absent: true }
proposed_fix: |
  Resolve every cited path against CWD through ONE helper (_missingOnDisk):
  comment-strip each behavioral_test_path(_<suffix>) value, then
  File(...).existsSync(); scan presence_only trailing prose and
  presence_only_reason bodies (block scalar OR plain scalar) for
  repo-shaped paths and resolve those too. Misses join `problems`
  (strict -> exit 1; --warn-only -> exit 0, miss still NAMED). The tally
  counts every presence_only: true line and how many also cite a
  behavioral path. Red-path subprocess test drives the REAL gate.
regression_test_planned:
  - "test/scripts/sot_behavioral_test_paths_gate_test.dart — 9 tests: 3 pass-paths (existing path with trailing comment; block citing an existing path with trailing punctuation) and 6 RED PATHS (missing behavioral path strict; warn-only names it; sibling _<suffix> key; presence_only prose; presence_only_reason block; blank line inside a block; plain-scalar reason). Record field is `exitCode` so the ledger's `exitCode, 1` red-path form matches."
impact_analysis: |
  Production impact: NONE — the diff touches one pre-commit/CI gate script,
  one new test file, and this doc. No lib/, supabase/, or migration change.
  Blast radius platform because gate scripts govern every commit; the
  registry itself is untouched and passes the strengthened gate today
  (138 behavioral values + 4 prose citations resolved, 0 missing), so no
  commit anywhere goes red on landing. From this commit on, a registry
  entry that cites a test never written (or a presence_only justification
  citing a live-verify file that does not exist yet — the OI-153 B-pass
  finding 2 shape) blocks the commit instead of printing PASS. Cost: 142
  existsSync calls per gate run (sub-millisecond each).
symptom: |
  `dart run scripts/check_sot_behavioral_test_paths.dart` printed
  `[Gate 42] PASS: all 133 SoT concepts have behavioral_test_path; 7 carry
  presence_only: true` for ANY non-empty value — a fixture registry citing
  `test/contracts/ghost_test.dart` (no such file) exited 0 (measured
  2026-09-19: 5 of 7 red-path tests green-against-the-bug before the fix).
  The same registry's writer/reader `file:` half had been resolved on disk by
  check_sot_registry_parity.dart for months; the test half never was
  (OI-195, found by the OI-153 B-pass finding 2). The "7" tally was also
  wrong by construction: 17 lines carry presence_only: true, 10 of whose
  concepts also cite a behavioral path and were therefore never counted.
root_cause: |
  Gate 42's value branch (pre-fix :103-114) validated the SHAPE of a
  `behavioral_test_path:` value — non-empty, not a placeholder marker, not
  `""`/`''` — and set a boolean. `grep -n "existsSync\|File(" scripts/check_sot_behavioral_test_paths.dart`
  matched only the registry file itself (:51-52 pre-fix). The field is a
  CLAIM about the tree ("this test exists and pins this concept") and nothing
  read the referent. Three further gaps of the same shape sat beside it: the
  key regex was `behavioral_test_path\s*:` so the sibling
  `behavioral_test_path_cqrs:` (:826) was invisible; a trailing `# id — note`
  (:3236, :6064, :6350) would have been part of the "path" had one been
  resolved; and `presence_only` justification prose — free text that cites
  live-verify SQL and Deno test files — was never scanned at all. Same class
  as 0a1e17 (a gate enforcing half of its contract) and a9f2c6 (a gate exiting
  0 while doing nothing about the case it exists for).
writer_reader:
  writers: [docs/sot_registry.yaml behavioral_test_path(_*) values + presence_only prose]
  readers: [scripts/check_sot_behavioral_test_paths.dart _missingOnDisk via the btpMatch branch and checkProsePaths]
fix: |
  scripts/check_sot_behavioral_test_paths.dart: `_missingOnDisk(path)` (one
  helper, both sinks); `_stripValueComment` (trailing `# …` + surrounding
  quotes) applied BEFORE the placeholder-marker validity check; key regex widened to
  `behavioral_test_path(?:_[a-z0-9_]+)?`; `presence_only: true` trailing
  prose, `presence_only_reason: |`/`>` block bodies (blank lines kept, body
  lines consumed so the main loop never re-reads them as keys) and plain
  `presence_only_reason:` scalars scanned with
  `\b(test|docs|scripts|supabase|lib)/[A-Za-z0-9_./-]+` (trailing `.,;)`
  trimmed); `missingFiles` joins `problems`; a `[file-missing]` report block
  mirroring check_sot_registry_parity.dart; PASS/SUMMARY tallies count every
  presence_only line and the also-behavioral subset. Header lines 1-15 are
  byte-identical so the generated GATE_INDEX.md row is unchanged.
touched_layers_checked:
  - { layer: client code, status: fixed_in_this_batch, evidence: "scripts/check_sot_behavioral_test_paths.dart; flutter analyze on the gate + test -> No issues found; real-tree run -> PASS exit 0 with 138 + 4 paths resolved" }
  - { layer: test harness, status: fixed_in_this_batch, evidence: "test/scripts/sot_behavioral_test_paths_gate_test.dart 9/9 green post-fix; 2 green / 5 red against the pre-fix gate (the 4 RED PATH tests + the warn-only NAMES-it test); 0 per-test timeout: overrides" }
  - { layer: hive, status: not_applicable, evidence: "no Hive box or key involved — docs/ YAML gate" }
  - { layer: postgres schema, status: not_applicable, evidence: "no table touched" }
  - { layer: postgres data, status: not_applicable, evidence: "no table touched" }
  - { layer: migrations applied, status: not_applicable, evidence: "no migration" }
  - { layer: edge function deploy, status: not_applicable, evidence: "no EF touched" }
  - { layer: cron, status: not_applicable, evidence: "no cron job" }
  - { layer: rls, status: not_applicable, evidence: "no policy" }
  - { layer: storage, status: not_applicable, evidence: "no bucket" }
  - { layer: secrets, status: not_applicable, evidence: "no secret read" }
  - { layer: external services, status: not_applicable, evidence: "none" }
  - { layer: client-server contract, status: not_applicable, evidence: "commit-time gate only; no runtime flow" }
mutation_proven: |
  Four mutations, each applied to the green working tree (token counts by
  grep -c 1 -> 0), each compiling (dart analyze: no errors; the 7-9 other
  tests stayed green, so the gate ran), each restored from a byte-verified
  pristine copy (cmp) rather than `git checkout --`, because the fix commit
  must carry these counts and a `fix(`-prefixed interim commit without the
  diagnose-doc is blocked by the commit-msg gate:
    M1 `_missingOnDisk` -> `=> null`            : 7 red (every detection test —
       ghost strict, warn-only names it, sibling key, presence_only prose,
       reason block, blank-line-in-block, plain-scalar reason). One helper
       backs both sinks, which is exactly why one mutation reddens all of them.
    M2 key regex narrowed to `behavioral_test_path\s*:` : 1 red (sibling key).
    M3 comment-strip removed from `_stripValueComment` : 1 red (existing path
       with a trailing comment now reads as missing).
    M4 block collector `indent <= keyIndent` -> `indent >= 0` (collects zero
       lines)                                      : 2 red (reason block, blank
       line inside a block).
  Total 11 reds across 4 mutations, 9-test file. Positive control on the
  REAL registry's shape: a scratch tree with the 140 genuinely-cited paths as
  empty placeholders plus ONE fake concept -> exit 1 naming exactly the two
  injected paths (registry lines 11231/11232 of the scratch copy), 0 false
  positives.
related_bugs:
  - "0a1e17 (Gate 18 enforced only the forbidden-patterns half of its contract — same half-contract class)"
  - "a9f2c6 (three gates exited 0 while doing nothing about the case they exist for)"
  - "OI-153 B-pass finding 2 (a presence_only justification cited a live-verify SQL file that did not exist yet; the gate was green) — the instance that filed OI-195"
  - "OI-180 (the same registry's other silently-skipped field)"
recurrence: "Recurrence of the gate-half-contract class (0a1e17, a9f2c6): a gate that reads a claim's SHAPE and never its REFERENT. Not a writer/reader field-drift instance — the writer and reader agree on the field; the reader simply never dereferenced it. Closes OI-195."
---

## Symptom

`dart run scripts/check_sot_behavioral_test_paths.dart` printed PASS for any
non-empty `behavioral_test_path:` value. A fixture registry citing
`test/contracts/ghost_test.dart` (no such file) exited 0; so did one whose
`presence_only: true` prose cited `test/sql/nope.sql`. Measured 2026-09-19
by running the new red-path test file against the pre-fix gate: 2 green /
5 red (the four RED PATH tests plus the warn-only NAMES-it test).

## Writer / reader

- **Writer:** `docs/sot_registry.yaml` — 138 `behavioral_test_path(_*)`
  keys across 140 concepts (first at `:49`; sibling `behavioral_test_path_cqrs:`
  at `:826`; 8-space-indented key at `:4219`; trailing `# id — note` values at
  `:3236`, `:6064`, `:6350`), 17 `presence_only: true` lines whose prose cites
  4 repo paths (`:10551`, `:6082` block), all of which exist today.
- **Reader (pre-fix):** `scripts/check_sot_behavioral_test_paths.dart:103-114`
  — shape check, boolean set, referent never opened.
- **Reader (post-fix):** `_missingOnDisk` (`:75`) via the `btpMatch` branch
  (`:182`) and `checkProsePaths` (`:155`); `problems` at `:252`.

## Fix evidence

- Real registry, post-fix: `[Gate 42] PASS: all 133 SoT concepts have
  behavioral_test_path; 17 carry presence_only: true (10 of them also cite a
  behavioral path; 7 presence-only). 138 behavioral_test_path value(s) + 4
  presence_only prose citation(s) resolved on disk.` exit 0. Tally
  re-derived: `grep -cE '^\s+presence_only:\s*true' docs/sot_registry.yaml`
  → 17; 133 + 7 = 140 concepts.
- `test/scripts/sot_behavioral_test_paths_gate_test.dart` → 9/9 green.
- Mutations: 7 / 1 / 1 / 2 reds (see frontmatter).
- Positive control against the real registry's shape: exit 1, exactly the two
  injected paths named.
