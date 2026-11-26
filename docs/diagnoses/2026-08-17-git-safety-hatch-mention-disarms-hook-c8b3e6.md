---
bug_id: c8b3e6
date: 2026-08-17
batch: cycle-time-and-board-gaps
status: fixed
blast_radius: platform
symptom: >
  The git-safety PreToolUse hook — the only mechanical guard forcing every
  commit and push through scripts/safe_commit.sh / safe_push.sh, and the only
  block on a `--no-verify` bypass — could be turned off by MENTIONING an escape
  hatch variable anywhere in the command text. It did not have to be used as a
  prefix; naming it in a shell comment, inside a commit message, or in an
  unrelated preceding `echo` was enough.
  Worst shape, verified against the real hook: a raw force-skip push with
  FOUNDER_APPROVED_NO_VERIFY=1 written only in a trailing `#` comment was
  ALLOWED. There the ENTIRE hook stands down — the skip-hooks flag matches
  first, the hatch reads "approved", the handler exits 0, and the raw-commit and
  raw-push checks below it never execute at all.
  All three demonstrated shapes were correctly BLOCKED before this batch and
  ALLOWED after it. The regression was introduced by the same batch that was
  hardening this hook, and it survived the full gate loop, a green suite and a
  landed commit.
concept: guard_accepts_mention_instead_of_invocation
sot_registry_entry: not_applicable — process/tooling; no Hive or cloud writer/reader contract
writers: >
  scripts/git_safety_lib.dart:100-102 (as shipped in fa65f200) —
  `inlineEnvAssignment` built `RegExp('(?:^|\\s)$n=(...)')` and ran
  `re.firstMatch(raw.trim())` over each statement, so it matched the assignment
  ANYWHERE inside a statement rather than only in the leading prefix position a
  shell would honour. It was added in that commit to make the two documented
  hatches real (an inline prefix never reaches the hook process's own
  environment, so the previous `Platform.environment` reads could never see
  either one) — the intent was correct, the position check was missing.
readers: >
  scripts/git_safety_hook.dart:120-121 — gates the `--no-verify` deny on
  `inlineEnvAssignment(command, 'FOUNDER_APPROVED_NO_VERIFY') == '1'` and exits 0
  when satisfied, skipping every later check;
  scripts/git_safety_hook.dart:137-139 — gates the raw-git deny on
  `inlineEnvAssignment(command, 'ALLOW_RAW_GIT') == '1'`.
  Both READ the helper's return value as an ALLOW, which is why a false positive
  there is a silent bypass rather than a noisy one.
hive_key_prefix: not_applicable — no Hive state involved
hive_key_formula: not_applicable — no Hive state involved
sync_methods: not_applicable — no sync path involved
restore_methods: not_applicable — no restore path involved
cloud_table: not_applicable — no cloud table involved
cloud_columns: not_applicable — no cloud columns involved
contract_test_path: >
  test/contracts/git_safety_lib_test.dart — five new cases in the
  "MENTION IS NOT AN INVOCATION" block (mention in a commit message, in a
  preceding echo, in a trailing shell comment, a prefix on a NON-git statement,
  and the mirror asserting env(1)/stacked/post-cd prefixes still work). The
  pre-existing case "finds it on any statement, not just the first" had PINNED
  the broken behaviour and was rewritten to require the prefix to lead the git
  statement itself.
ist_handling: not_applicable — no date keys or counter resets involved
provider_invalidations: not_applicable — no Riverpod providers involved
telemetry_op_types: not_applicable — hook tooling emits no client telemetry
cross_account_guard: not_applicable — no per-user data involved
forbidden_patterns_checked: >
  Re-ran the hook end-to-end over a 15-case matrix with controls in BOTH
  directions: 3 controls that must block (plain raw commit, plain raw push, raw
  skip-hooks flag), 4 bypass shapes that must now block, and 8 legitimate forms
  that must still pass (both documented hatches, a hatch after a `cd`, a hatch
  via `env(1)`, both sanctioned wrappers, an unrelated command). 15/15.
regression_test_planned: >
  Five cases in test/contracts/git_safety_lib_test.dart's "MENTION IS NOT AN
  INVOCATION" group, each FAILING before the fix and passing after: the hatch var
  in a commit message, in a preceding echo, in a trailing shell comment, and as a
  prefix on a NON-git statement — plus the mirror asserting the documented forms
  (env(1), stacked prefixes, a hatch after `cd`) still resolve. The pre-existing
  "finds it on any statement, not just the first" test asserted the BROKEN
  behaviour and was rewritten to require the prefix to lead the git statement.
  Mutation-proven per leg: restoring the match-anywhere regex reddens 4;
  dropping the same-statement-is-git check reddens 1.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "no lib/ code involved; this is repo tooling" }
  - { tier: 2, name: "Hive local state", status: not_applicable, evidence: "no Hive state involved" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema involved" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "no data involved" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration involved" }
  - { tier: 6, name: "Edge Function deploy", status: not_applicable, evidence: "no Edge Function involved" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron involved" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "no RLS involved" }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "no storage involved" }
  - { tier: 10, name: "Secrets", status: not_applicable, evidence: "no secrets involved" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "no external service involved" }
  - { tier: 12, name: "Client to server contract", status: fixed_in_this_batch, evidence: "the agent-to-git contract IS the surface here; 15-case matrix run against the real hook binary with controls in both directions, all correct" }
proposed_fix: >
  Require the hatch assignment to sit in the LEADING PREFIX CHAIN of a statement
  AND require that same statement's real command word to be `git`. Implemented as
  `_leadingAssignmentIfGitStatement`, which walks the prefix chain with the same
  alternation `stripCommandPrefixes` uses (backslash, command/builtin, env [-i],
  VAR=value) and captures the assignment's name and value as it consumes them;
  after the chain it requires the remainder to match `^git(\s|$)`.
  Deliberately kept as its own function mirroring `stripCommandPrefixes` rather
  than re-deriving what counts as a prefix: if those two ever disagree, the hatch
  applies in positions the strip does not recognise, which is precisely how the
  original hole opened. Plus five mention-does-not-count tests, and a rewrite of
  the one pre-existing test that had pinned the broken behaviour.
impact_analysis: >
  WINDOW: introduced in fa65f200 (2026-08-17, this branch) and fixed the same
  day, before the branch merged. It never reached `main`, never reached a
  release, and no user-facing surface is involved — the blast radius is the
  agent's own write discipline, not the app.
  EXPOSURE IN THAT WINDOW: every commit and push made from this branch ran with
  the weakened hook. Reviewed the session's actual git operations against the
  four bypass shapes — all commits went through scripts/safe_commit.sh (the
  sanctioned path, which the hook allows regardless), and the one `git commit
  --amend` used the documented ALLOW_RAW_GIT prefix in its correct leading
  position. So the weakness was live but not exercised.
  WHAT WOULD HAVE BEEN LOST had it merged: the hook is the sole mechanical
  enforcement of CLAUDE.md §4.3's "commits and pushes go through the wrappers,
  never raw git", which exists because of six documented incidents where a
  backgrounded or piped commit reported success while the pre-commit hook had
  actually failed. It is also the only mechanical block on `--no-verify`. Neither
  has any CI equivalent — CI has no staged diff and never invokes this hook — so
  a bypass here is not backstopped anywhere.
related_bugs: d3f1a7
recurrence: >
  YES, and the recurrence is the finding. This is
  feedback_mistake_guard_without_its_mirror — fixing the instance and not the
  class — committed INSIDE the fix for it.
  Commit fa65f200 fixed exactly this bug class twenty lines further down the same
  file. `commandUsesWrapper`'s docstring says it verbatim: "It used to be a bare
  `command.contains(basename)`, which meant merely NAMING the wrapper anywhere
  disarmed the guard: `echo "remember to use safe_commit.sh" && git commit -m x`
  passed cleanly. Now the wrapper must appear as the command word of a
  statement." That fix even shipped its own mention-does-not-count test.
  The identical hole was then opened in `inlineEnvAssignment`, in the same
  commit, with no such test — and its test suite actively asserted the broken
  behaviour was correct.
---

# c8b3e6 — naming a hatch variable anywhere disarmed the git-safety hook

## What happened

`fa65f200` set out to close a real bypass: `commandInvokesGitSubcommand` anchored
its pattern at `^git`, so any environment prefix (`FOO=1 git commit`) escaped the
raw-git block entirely. Fixing that anchor exposed a second problem — the two
DOCUMENTED escape hatches are written as inline prefixes, and an inline prefix
applies to the pending command's environment, never to the environment of the
hook process inspecting it. So the hook's `Platform.environment` reads could
never see either hatch. `ALLOW_RAW_GIT=1 git commit` had only ever "worked"
because the hook could not SEE the command at all.

`inlineEnvAssignment` was added to read the assignment off the command text and
make the documented incantation the real mechanism. That was the right call. The
defect is that it matched the assignment **anywhere in a statement** instead of
in the leading prefix position:

```dart
final re = RegExp('(?:^|\\s)$n=("[^"]*"|\'[^\']*\'|\\S*)');
```

## Why it is worse than an ordinary false positive

This return value is an **ALLOW**. A false positive is not a missed detection,
it is an unlock. And because the `--no-verify` handler `exit(0)`s as soon as it
believes it is approved, one false positive there disables the raw-commit and
raw-push checks too. One stray mention, whole hook off.

Measured against the real hook (exit 2 = blocked, exit 0 = allowed):

| command | before fa65f200 | after fa65f200 | now |
|---|---|---|---|
| raw force-skip push, hatch var in a trailing `#` comment | 2 | **0** | 2 |
| `git commit -m "noted ALLOW_RAW_GIT=1 in docs"` | 2 | **0** | 2 |
| `echo "try ALLOW_RAW_GIT=1 next time"; git commit -m x` | 2 | **0** | 2 |
| `ALLOW_RAW_GIT=1 echo hi; git commit -m x` | 2 | **0** | 2 |
| plain `git commit -m x` (control) | 2 | 2 | 2 |
| `ALLOW_RAW_GIT=1 git commit --amend` (documented hatch) | 0 | 0 | 0 |

The comment case is the one to remember. Writing a note to yourself about the
approval process, on the same line as a command, silently granted the approval.

## The fix

The assignment must (a) sit in the **leading prefix chain** of a statement — the
only position where a real shell applies it to the command's environment — and
(b) that same statement must actually invoke `git`. Leg (b) matters because
`ALLOW_RAW_GIT=1 echo hi; git commit` does not reach git in a shell either, so
honouring it would be wrong on the shell's own terms, not merely unsafe.

The chain walk deliberately mirrors `stripCommandPrefixes` rather than
re-deriving what a prefix is; if those two drifted, the hatch would apply in
positions the strip does not recognise, which is how the original hole opened.

## Mutation evidence

- Restoring the match-anywhere regex: **4 tests redden**.
- Dropping only leg (b) (the same-statement-must-be-git check): **1 test reddens**.

Each leg has its own failing test rather than one test covering both, so a
partial regression cannot pass.

## How it was found, and what that says

Not by the gate loop, not by the suite, not by review of the diff — all of those
were green, and the commit had already landed. It was found by a context-blind
reviewer told to assume the author was rationalizing and to verify every claim
by execution. It ran the real hook with a control first.

The generalisable part: **when the artifact under change IS the safety
mechanism, its own green result carries almost no information.** The gates ran,
and the thing they were protecting was off.
