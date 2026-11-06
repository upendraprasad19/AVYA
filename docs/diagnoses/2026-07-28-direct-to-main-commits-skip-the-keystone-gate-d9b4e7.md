---
bug_id: d9b4e7
date: 2026-07-28
batch: oi58-version-bump-lines
status: fixed
blast_radius: platform
symptom: >
  Commits pushed straight to main skipped the keystone plan-review gate
  entirely — it exited at `rev-parse HEAD^2` before reading anything. Observed
  twice on account-tier auth code that landed with no branch, no merge and no
  review record.
concept: plan_review_record_enforcement
sot_registry_entry: not_applicable
writers: >
  scripts/check_plan_review_record_exists.dart (the direct-commit loop);
  scripts/plan_review_record_lib.dart isVersionBumpCommit +
  normalizeVersionToken + versionBumpPaths + versionLinePubspec +
  versionLineConstants (pure helpers)
readers: >
  .github/workflows/test.yml job `plan-review-record` is the enforcing consumer;
  scripts/git_safety_hook.dart also invokes the gate advisory-only on
  push-shaped commands
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/version_bump_exemption_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  gate entry conditional on a second parent existing; an exemption decided by
  file PATHS when the thing exempted is defined by file CONTENT; an all-of test
  over an allow-list treated as sufficient; parsing text that the entity being
  checked controls; an unanchored RegExp used with hasMatch as a line validator
proposed_fix: >
  Judge every direct-to-main commit in the pushed range on its own tier. Decide
  the version-bump exemption by fetching each touched file's blob at <sha>^ and
  <sha>, replacing the version token with a placeholder, and requiring the
  normalised blobs to be byte-identical. No diff is parsed.
regression_test_planned: >
  test/scripts/version_bump_exemption_test.dart — 16 pure-function controls
  organised by ATTACK, one per payload that defeated an earlier attempt or the
  B-pass, plus 8 e2e scenarios in gate_input_family_e2e_test.dart.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change — CI enforcement tooling" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: verified, evidence: "GitHub Actions is the only external surface; the plan-review-record job's invocation is unchanged — only what the gate does with a direct commit changes" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "every attack round-1 review used to break attempt 3 was re-executed against the blob design and now returns false: extra Dart on the version line, a second file mutated behind a real bump, payload elsewhere in the file, a nested version: key, create, delete, no-op, third file, unfetched blob, no version token. Genuine bumps still pass, including pubspec-only and CRLF. `flutter test test/scripts/` → 95 green." }
impact_analysis: >
  CI-only; no product code and no user-facing behaviour. The change can only ADD
  failures: a direct >=account commit that previously passed silently now fails
  unless every touched file is byte-identical to its parent modulo the version
  token. The workflows that must keep working — the release version bump, the
  pubspec-only bump, and the two-commit release push — each have a control.
---

# Direct-to-main commits skipped the gate, and it took four attempts to close it

## What was wrong

`scripts/check_plan_review_record_exists.dart` exited at
`if (!_gitOk(['rev-parse','--verify','--quiet','HEAD^2'])) exit(0)`. Anything
committed straight to `main` has no second parent, so the gate never looked.

Not theoretical. Of the last 60 first-parent commits, 5 were single-parent and 3
were ≥account: `be3b4baf` (account, in-app password reset, 11 files),
`8c38c855` (account, password-recovery routing, 8 files), and `2c4cbddd`
(platform, the versionCode bump — the mechanical case an exemption exists for).

## Four attempts, and the one thing they had in common

| # | Rule | How independent review broke it |
|---|---|---|
| 1 | per-PUSH union of direct commits' paths | one `feature` docs commit beside the bump killed the exemption — the standard release flow (`2c4cbddd` + `6a364656`, the two halves of APK +37) |
| 2 | per-commit, `paths.every(allowList.contains)` | all-of over an **allow-list** accepts every subset: a commit touching only `app_constants.dart` rewrote `monthlyPriceInr` and `freeAiMessagesPerDay` under a "version-bump exemption" banner |
| 3 | per-commit, every changed **line** must match a version regex | three independent bypasses in one review pass (below) |
| 4 | per-commit, every touched **file** byte-identical to its parent modulo the version token | **two more bypasses at B-pass**, both in the normalisation rather than the idea (below) — fixed within this attempt |

Attempt 3's three bypasses are worth keeping, because they share one root:

- a content line beginning `++ ` was parsed as a `+++ ` **header**, skipped
  unvalidated, and could even reassign which file's regex applied;
- a file git renders with no `+`/`-` lines at all — one NUL byte makes it
  binary, and a `.gitattributes` `-diff` entry does it deliberately (that file
  is itself `feature` tier) — was never inspected, while the other file's
  version line satisfied a single global flag;
- `versionLineConstants` was unanchored and applied with `hasMatch`, i.e. a
  *containment* test, so
  `appVersion = '1.0.0+38'; static const bool kBypassProGate = true;`
  counted as "a version line". Valid Dart, and there is no formatter gate in
  pre-commit, pre-push or CI that would have split it.

**The root: attempt 3 parsed text that the commit author writes.** Reviewer's
framing, which is the sentence worth remembering: *attempt 2 was an all-of test
over an allow-list; attempt 3 was an all-of test over the lines the parser chose
to look at — and the attacker controls which lines the parser looks at.* Both
are "accept anything containing X" wearing the costume of "require everything to
be X".

## What the B-pass still found, after two review rounds had passed it

Two P0s, both real, both reproduced by me before acting — and both were attacks
that round 2 had *reported as defeated*:

- **A SECOND version token changes freely.** `normalizeVersionToken` checked
  `hasMatch` (≥ 1) and then called `replaceAll`, so with two version-shaped
  tokens in one file both collapse to the same placeholder and the second one's
  value is unconstrained. Works on `pubspec.yaml` (duplicate top-level key) and
  on `app_constants.dart` (a second class declaring its own `appVersion` —
  valid, compiling Dart with no downstream circuit-breaker at all, unlike
  pubspec where `pub` would eventually object). Fixed by requiring **exactly
  one** match on each side.
- **Converting the file to a symlink.** `git show <rev>:<path>` returns a
  symlink's *link-target text* as though it were file content, so swapping
  `pubspec.yaml` for a symlink whose target string reads like a bumped pubspec
  was granted the exemption. Content cannot see that; the tree mode can. Fixed
  by requiring mode `100644`/`100755` on both sides. (A submodule/gitlink failed
  closed already, but only because `git show` errors on it — relying on that was
  luck, not design.)

The B-pass also mutation-tested the new binary-file control and found it
**vacuous**: the payload sat at `lib/features/auth/icon.png`, which never
reaches `_gitBlob` at all, so the test passed with the guard deleted. Moved to
`pubspec.yaml`, where it genuinely forces the decode.

## The fix

Stop parsing. `isVersionBumpCommit` takes each touched file's **blob before and
after**, replaces the version token with a placeholder, and requires the two
normalised blobs to be **byte-identical**. Anything else in the file — anywhere,
in any encoding, however git chooses to render it — survives normalisation and
breaks equality.

Supporting details, each closing a specific finding:

- the **full** path list is the precondition, so a third file disqualifies
  regardless of what was fetched;
- every changed path must be covered by a fetched blob — a path git reported but
  we could not read is rejected, not assumed benign;
- `versionLinePubspec` is anchored at **column 0** (no `\s*` prefix), so a
  nested `version:` under a `hosted:` block cannot pose as the app version;
- a missing version token on either side returns null and rejects;
- create, delete and no-op all reject.

Deliberately NOT requiring both files: 17 historical commits touched
`pubspec.yaml` alone, so an all-of-both rule would redden the release flow.

Also fixed alongside: `_tierRank` returns `-1` for an unknown tier, and
`-1 < 1` meant a registry typo (`tier: platfrom`) skipped every direct commit
**silently**. It now fails loud. And the final `PASS` line no longer claims
every landing "carries a valid record" — untrue for an exempted direct commit.

## What is still open

**OI-58b.** Branch identity still comes from the merge subject, which is
author-written free text. Its realistic form (one-record-one-landing) and the
residual first-time spoof are not addressed here. The spoof's only real control
is requiring PRs so GitHub writes the subject from the head ref — a
repository-settings decision, and `feedback_mistake_branch_protection_semantics`
records three prior errors on those semantics.

## The method lesson

Attempts 1, 2 and 3 each passed every test written for them. The e2e suite even
had a dedicated control for each *previous* attempt's failure — and none for the
current one's, which is exactly why round 1 could break attempt 3 six ways
against a green suite.

So `test/scripts/version_bump_exemption_test.dart` is organised **by attack, not
by attempt**: every payload that defeated an earlier design is a named test, and
each was executed against the real helper before being written down. A control
that cannot name the bug it would have caught is decoration.

The second lesson is about provenance. Attempt 3 justified its regexes as
"copied from `check_app_version_matches_pubspec.dart`, which already decides
what a version line is". They were — but that gate uses them with `firstMatch`
over a whole file to **extract** a version, where indifference to surrounding
text is the point. Reusing them with `hasMatch` over one line to assert the line
**consists of** nothing else inverts their contract. Borrowed code carries its
original assumptions with it.
