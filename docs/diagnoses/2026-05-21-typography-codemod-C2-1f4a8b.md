---
bug_id: 1f4a8b
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / finding C2
status: shipped
symptom: |
  `lib/core/theme/typography.dart` exists as the canonical Wardroom
  3-font system (`AppTypography.body`, `.bodyM`, `.mono`, `.h1`, etc.)
  but only ~2 production files routed through it. The other 175
  callsites (across 32 files; previously under-counted as ~9 due to a
  single-line regex bug in Gate 37) inlined
  `GoogleFonts.getFont('DM Sans', fontSize: ..., fontWeight: ..., color: ..., ...)`
  directly. This defeated:

    - Font caching — every `getFont` invocation re-resolves the font asset.
    - Theme-level overrides — `AppTypography` is the single tunable surface
      where the entire body voice can shift (size, family, weight, line
      height) in one place.
    - Palette / scale change cadence — any tweak required a 175-site
      sweep instead of a one-line edit.

  Gate 37 (`scripts/check_no_raw_google_fonts.dart`) existed in
  warn-only mode flagging only 9 single-line callsites because its
  regex was not multi-line aware; the multi-line/dotAll regex applied
  during this batch flushed out the true 175-callsite scope.
concept: typography_canonical_source
sot_registry_entry: typography_canonical_source
writers:
  - { file: lib/core/theme/typography.dart, method: AppTypography (all scale constants + dmSansFamily / frauncesFamily / buttonLabel helpers), line: 21 }
readers:
  - { file: lib/core/theme/app_theme.dart, method_or_widget: AppTheme._buildTextTheme reads dmSansFamily / frauncesFamily; ElevatedButton + OutlinedButton themes read buttonLabel, line: 105 }
  - { file: lib/features/ai_coach/screens/ai_coach_screen.dart, method_or_widget: 3 codemod-rewritten DM Sans usages, line: 836 }
  - { file: lib/features/ai_coach/widgets/chat_bubble.dart, method_or_widget: 5 codemod-rewritten DM Sans usages (bullet bullets + sub text + retry pill), line: 211 }
  - { file: lib/features/ai_coach/widgets/diff_preview/custom_template_diff.dart, method_or_widget: 12 codemod-rewritten DM Sans usages, line: 40 }
  - { file: lib/features/profile/screens/profile_screen.dart, method_or_widget: 8 snackbar copy callsites — first migrated manually before discovering the multi-line regex true scope, line: 117 }
  - { file: lib/features/train/widgets/challenge_card.dart, method_or_widget: 15 codemod-rewritten DM Sans usages — largest single file (rank ribbons + chips + meta lines), line: 101 }
hive_key_prefix: ""
hive_key_formula: "Not Hive-backed — typography is a process-memory singleton (static fields) seeded at first read."
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/no_raw_google_fonts_test.dart
ist_handling:
  - { file: lib/core/theme/typography.dart, line: 1, fn: No IST surface — typography has no date or time-of-day axis. }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: No user-scoped state — typography is a single shared font / colour / size registry applied identically to every signed-in user. No leakage path.
forbidden_patterns_checked:
  - { pattern: "GoogleFonts\\.getFont\\(\\s*['\"]DM Sans['\"]", absent_outside: "lib/core/theme/typography.dart", gate: "scripts/check_no_raw_google_fonts.dart (Gate 37 hard-fail mode)" }
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "175 callsites across 32 files rewritten via .codemod_typography.dart. AppTypography import added to 29 files; google_fonts import removed from 32 files. lib/core/theme/typography.dart gained dmSansFamily / frauncesFamily / buttonLabel helpers. lib/core/theme/app_theme.dart switched from 4 direct GoogleFonts.getFont calls to 3 AppTypography reads. flutter analyze lib/ --no-fatal-infos: zero typography-related errors / warnings / infos (pre-existing barcode_service.dart:52 http error confirmed via `git stash && flutter analyze` against main tip — unrelated to this batch)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Typography is process-memory only — static fields on AppTypography. No Hive key / box involvement. No persistence; values re-seed from the static initializer on every cold start." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change — codemod is client-side rendering only. No SQL DDL, no migration." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data migration — visual change only." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function change." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron change." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS change." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage change." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secrets touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service touched. Google Fonts asset URLs are unchanged; only the call-chain that resolves them moved into AppTypography." }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "Gate 37 (scripts/check_no_raw_google_fonts.dart) hard-fail mode reports zero direct GoogleFonts.getFont('DM Sans'...) callsites outside lib/core/theme/typography.dart. test/contracts/no_raw_google_fonts_test.dart spawns the gate as a subprocess (runInShell: true for Windows) and asserts exit 0. SoT registry entry typography_canonical_source added with reader_allow_files exhaustive list + class_constraints documenting the (size, weight) → AppTypography.<scale> mapping policy." }
impact_analysis:
  callers_audited:
    - lib/core/theme/app_theme.dart (4 GoogleFonts.getFont calls → 3 AppTypography references)
    - 8 callsites in lib/features/profile/screens/profile_screen.dart (manual migration BEFORE the multi-line regex flush)
    - 175 codemod-rewritten callsites across 32 files (script: .codemod_typography.dart; mapping policy described in SoT registry class_constraints)
  callers_updated_in_this_batch:
    - All 33 lib/ files touched (32 codemod + lib/core/theme/app_theme.dart). flutter analyze clean across every touched file.
  callers_unchanged:
    - lib/shared/widgets/wardroom/* — Wardroom design primitives intentionally untouched per the audit brief (they define the scales themselves; verified no inline GoogleFonts.getFont('DM Sans') with audit lens prior to codemod execution).
    - lib/features/ai_coach/repositories/ai_coach_repository.dart — explicitly out-of-scope per audit brief (recently refactored in A10; shim file is delicate).
proposed_fix: |
  1. Extend `AppTypography` with three additions that consolidate the
     remaining direct callsites:
       - `dmSansFamily({color})` — family-only DM Sans for TextTheme seed.
       - `frauncesFamily({color})` — family-only Fraunces for TextTheme seed.
       - `buttonLabel` — Fraunces 12 / w600 / +2.5 for global Elevated /
         Outlined button textStyle.

  2. Rewrite `lib/core/theme/app_theme.dart` to read those three new
     helpers; drop its `google_fonts` import.

  3. Run a mechanical codemod (.codemod_typography.dart) over `lib/**/*.dart`:
     for every `GoogleFonts.getFont('DM Sans', ...)` call, parse named
     args (using a paren / quote-aware splitter), pick the closest
     `AppTypography.<scale>` by (fontSize, fontWeight), and rewrite as
     either `AppTypography.<scale>` (exact match) or
     `AppTypography.<scale>.copyWith(...overrides)`.

     Mapping policy:
       12 / w400      → bodySm
       13 / w400      → bodyM
       14 / w400      → body
       15 / w400      → bodyL
       15 / w600      → titleS
       other          → body.copyWith(fontSize: X, fontWeight: Y, ...)
                         (never invents one-off constants)

     Color / letterSpacing / height / fontStyle / decoration are
     forwarded verbatim into the copyWith call.

  4. Run an import fixer (.codemod_imports.dart): for every file that
     newly references `AppTypography`, add
     `import 'package:icanbefitter/core/theme/typography.dart';` after
     the last `import 'package:...'` line. For every file that no
     longer references `GoogleFonts` at all, strip its
     `google_fonts` import.

  5. Flip Gate 37 (`scripts/check_no_raw_google_fonts.dart`) from
     `warnOnly = true` (forced during transitional sweep) to the
     standard `args.contains('--warn-only')`. Hard-fail mode now exits
     1 on any direct DM Sans callsite outside `lib/core/theme/
     typography.dart`.

  6. Add `test/contracts/no_raw_google_fonts_test.dart` invoking the
     gate via `Process.runSync('dart', ['run',
     'scripts/check_no_raw_google_fonts.dart'], runInShell: true)`
     and asserting exit 0.

  7. Update `docs/sot_registry.yaml` with the new
     `typography_canonical_source` concept (writer:
     typography.dart, reader_allow_files: 33 touched files +
     wardroom glob; reader_manifest_complete: true).
regression_test_planned: |
  test/contracts/no_raw_google_fonts_test.dart asserts Gate 37 exit 0.
  Gate 37 itself is hard-fail mode and is invoked by the pre-commit hook
  via `dart run scripts/check_no_raw_google_fonts.dart` so any future
  regression (a new feature inlines `GoogleFonts.getFont('DM Sans'`)
  blocks at commit time. The test ALSO runs in `flutter test` so the
  CI / pre-push gate catches it independently of the local hook.
followups:
  - "Wardroom primitives in lib/shared/widgets/wardroom/* may have their own ad-hoc GoogleFonts.getFont('DM Sans', ...) callsites. Out of scope per audit brief (they're the design-system source defining the scales themselves), but a future audit lens (e.g. 'design-system primitive purity') should verify those callsites all live in *.jsx ↔ *.dart parity files and aren't introducing competing scales."
  - "Consider extending Gate 37 to ALSO check `GoogleFonts.getFont('Fraunces'...)` and `GoogleFonts.getFont('JetBrains Mono'...)` for the same SoT property. Out of scope for C2 (audit specifically scoped to DM Sans, the 175-callsite hot path), but the gate's single-regex-pattern shape makes adding two more straightforward."
metrics:
  files_touched: 33
  callsites_rewritten: 175
  line_delta_lib: "+347 / -1122 = net -775 across 37 files (multi-line GoogleFonts.getFont calls collapsed to single-line AppTypography.<scale>.copyWith(...))"
  google_fonts_imports_removed: 32
  app_typography_imports_added: 29
  app_typography_new_constants: 3 (dmSansFamily, frauncesFamily, buttonLabel)
  gate_37_before: "warn-only, 9 single-line callsites flagged (false-low due to single-line regex)"
  gate_37_after: "hard-fail, multi-line aware regex, 0 callsites"
---

# Tech-debt audit 2026-05-20 / C2 — Typography codemod

## Why this was a bug class, not just a style nit

`AppTypography` already existed and was nominally the SoT, but its mere
existence didn't enforce anything. Engineers reach for the snippet they
remember (`GoogleFonts.getFont('DM Sans', fontSize: 13, ...)`) and the
SoT goes unused. Gate 37 caught only the single-line shape, which led
to a false-low violation count (9, not 175). The codemod scope this
batch is 19× larger than what Gate 37 reported before the multi-line
regex fix.

## Codemod execution

Two helper scripts written for this batch (and tracked as `.codemod_*`,
gitignored — left in working tree as artifacts):

- `.codemod_typography.dart` — paren/string-aware parser, finds every
  `GoogleFonts.getFont('DM Sans', ...)` call, extracts named args, maps
  to `AppTypography.<scale>` per the (size, weight) policy above, and
  rewrites in place. Output: 32 files / 175 calls.
- `.codemod_imports.dart` — for every file using `AppTypography`,
  ensures the import is present; for every file no longer using
  `GoogleFonts`, removes the unused import. Output: +29 imports, -32 imports.

Both scripts are intentionally NOT committed (throwaway one-shot
tools); they were removed from the working tree after the codemod
landed. The (size, weight) → AppTypography.<scale> mapping policy
they implemented is preserved verbatim in the SoT registry's
`typography_canonical_source.class_constraints` field so future
manual edits follow the same rule.

## Gate state

Before:
```
[Gate 37] WARN (B2-transitional): 9 direct GoogleFonts.getFont('DM Sans'...) callsite(s):
  ... 9 lines ...
EXIT=0
```

After multi-line regex fix (mid-batch):
```
[Gate 37] FAIL: 175 direct GoogleFonts.getFont('DM Sans'...) callsite(s):
EXIT=1
```

After codemod + hard-fail flip:
```
[Gate 37] PASS: all DM Sans usage routes through AppTypography.
EXIT=0
```

## Test

`flutter test test/contracts/no_raw_google_fonts_test.dart` →
`All tests passed!`.
