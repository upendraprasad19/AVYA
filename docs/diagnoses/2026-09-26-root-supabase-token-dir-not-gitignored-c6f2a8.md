---
bug_id: c6f2a8
date: 2026-09-26
batch: ci-green-batch-a (U3 — secret hygiene)
status: fixed
blast_radius: feature
symptom: |
  A live Supabase Management API token sat at the repo ROOT,
  `.supabase/supabase access token.txt` (44 B, 2026-09-23), untracked and NOT
  ignored: `git check-ignore -v` on it exited 1 in the primary worktree. The
  only token rule, `.gitignore:73`, is `supabase/.supabase/`, so a single
  `git add -A` in the primary would have staged the token. Found during the
  2026-09-26 backlog triage, not by any gate.
concept: not_applicable — repository secret hygiene, not a Hive/cloud contract.
sot_registry_entry: not_applicable — no writer/reader pair, Hive key or table.
writers:
  - { file: .gitignore, method_or_widget: "the only token rule `supabase/.supabase/` — covers the nested dir, not a root-level `.supabase/`", line: 73 }
readers:
  - { file: test/scripts/gitignore_classification_test.dart, method_or_widget: "literalEntries + the four list-agreement tests (they prove the LISTS agree, not that git ignores the path)", line: 148 }
  - { file: .claude/deploy_via_api.js, method_or_widget: "default token file (reads supabase/.supabase/, never the root copy)", line: 254 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/scripts/gitignore_classification_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable
forbidden_patterns_checked:
  - "an unanchored `.supabase/` rule — rejected: it would also match any nested `.supabase/` dir anywhere; the anchored `/.supabase/` names exactly the root dir, and `supabase/.supabase/` keeps its own rule."
  - "classifying `.supabase/` as REGENERABLE in retire_worktree_lib.dart — rejected: a worktree holding a token must stay unretirable (retire deletes it); it is added to deliberatelyPreciousIgnoredPaths."
  - "moving the root token into supabase/.supabase/ as part of this fix — rejected (plan-review R1 F1): that path ALREADY holds a DIFFERENT token (cmp exits 1; 2026-08-08). A blind move overwrites whichever is live. Which token is valid is a founder decision; see Residual."
proposed_fix: |
  .gitignore gains an anchored `/.supabase/` rule (with its reason) beside the
  existing `supabase/.supabase/`; `test/scripts/gitignore_classification_test.dart`
  adds `.supabase/` to `deliberatelyPreciousIgnoredPaths` (the test strips a
  leading `/`), and a NEW group that asks git itself — hermetic env
  (GIT_* stripped, GIT_CONFIG_GLOBAL → empty file, GIT_CONFIG_NOSYSTEM=1) —
  whether both token paths are ignored AND that the deciding pattern comes
  from `.gitignore:` (so a developer's own core.excludesFile or
  .git/info/exclude cannot make it pass). The file gains
  `@Timeout(Duration(minutes: 2))` + `library;` because it now spawns git.
regression_test_planned:
  - "test/scripts/gitignore_classification_test.dart — MUTATION-PROVEN 2026-09-26: deleting BOTH the new `/.supabase/` rule and the new list entry (applied: grep counts 0 and 0) reddened exactly 1 of 7 — the new `.supabase/supabase access token.txt is ignored, and by .gitignore` case — while all five list-agreement tests stayed GREEN. That green-while-unignored result is exactly why the new assertion exists (plan-review R1 F6). Restored → 7/7 green. The single-sided mutation (list entry removed, rule kept) is covered by the pre-existing 'every literal .gitignore entry is deliberately classified' test."
impact_analysis: |
  .gitignore + one test file. No product code. Nothing that used to be
  tracked becomes ignored (`git ls-files .supabase` is empty), so no file
  disappears from the index.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter test test/scripts/gitignore_classification_test.dart 7/7 green; mutation above." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "Both token files located and compared WITHOUT reading their contents (ls -la + cmp exit 1): root copy 2026-09-23, nested copy 2026-08-08, different tokens. Root dir mode drwx---rwx, file -rw-rw-r--; /home/ubuntu is drwxr-x---, so no other local user can traverse to either (plan-review R1)." }
---

## Summary

The repo ignored `supabase/.supabase/` but not a root-level `.supabase/`, and a
live Management API token was sitting in exactly that unignored place.

## Fix

Anchored `/.supabase/` rule, precious-list classification, and a direct
git-level assertion that the token paths are ignored by the repo's own
`.gitignore` — the protection the list-agreement tests could not provide.

## Residual (founder action — not code)

Two DIFFERENT tokens exist on this machine: `supabase/.supabase/…` (2026-08-08,
the path every tool reads) and the root `.supabase/…` (2026-09-23). Decide
which is valid (a read-only Management API call with each), keep that one at
`supabase/.supabase/`, revoke the other in the Supabase dashboard, then delete
its file. Until then both are ignored by this fix, so neither can be committed.
