---
branch: discipline-overhead
scope: Discipline-overhead reduction batch — ship-dark review tiering (CLAUDE.md §4.12.4 + a matching gate change), push/CI consolidation guidance (§4.3), scripts/safe_commit.sh + safe_push.sh git wrappers, and a new PreToolUse blocking hook (scripts/git_safety_hook.dart) that actually denies raw git commit/push not going through the wrappers, plus a build-apk.md fix
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/discipline-overhead-review.md
---

# Plan-review record — discipline-overhead

## Ground-truth verified (against live repo, pre-implementation)
Investigated via direct file reads before any code was written: `scripts/discipline_hook.dart`
(the existing PreToolUse hook) only injects `additionalContext` — confirmed it cannot block
anything, contrary to an implicit assumption that "a hook" already meant enforcement. Read
`scripts/check_plan_review_record_exists.dart` in full — confirmed its anti-fabrication guard
(a `bpass: accepted` claim requires a real file under `docs/reviews/` containing `verdict:
accepted`) is genuine, not pure self-attestation as first assumed. Read
`scripts/check_commit_from_worktree.dart` for its MERGE_HEAD/CHERRY_PICK_HEAD/REVERT_HEAD
exemption pattern and `ALLOW_MAIN_COMMIT=1` escape hatch — the new hook mirrors both. Read
`.claude/commands/build-apk.md` in full and confirmed (contrary to an initial assumption) it
does NOT invoke `git commit`/`git push` for the main flow, but DOES for the Gate 2 versionCode
bump — a gap that would have broken every future `/build-apk` run. Counted the actual
workout-generator-overhaul batch history (git log) rather than trusting the "batch N of 13"
framing: 29 `workout-*` branch merges shipped it, ≥14 explicitly tagged `ship-dark` in their own
merge subject.

## Implementation
- CLAUDE.md §4.12 item 4 (ship-dark tiering) + §4.3 (push consolidation + wrapper mandate).
- `scripts/check_plan_review_record_exists.dart`: accepts `review_rounds: 1` only paired with a
  self-declared `tier: ship_dark_build`; `bpass: accepted` still independently required at
  >=platform regardless of tier (verified the diff touches only the `rounds` block, not the
  bpass/hermes/anti-fabrication logic below it).
- `scripts/safe_commit.sh` / `scripts/safe_push.sh`: redirect (never pipe) to a log file, verify
  HEAD/status (commit) or `ls-remote` (push) independently of the wrapped command's own exit code.
- `scripts/git_safety_hook.dart` (+ pure `scripts/git_safety_lib.dart`, tested): PreToolUse(Bash)
  hook denying raw `git commit`/`git push` not via the wrappers, and `--no-verify` without
  `FOUNDER_APPROVED_NO_VERIFY=1`. A local re-run of the plan-review-record gate for push-shaped
  commands is advisory-only (see Round 2).
- `docs/ship_dark_pending_review.yaml`: manual ledger tracking flags shipped under the lighter tier.
- `docs/blast_radius.yaml`: platform-tier overrides for the git-safety files themselves, plus the
  pre-existing `check_commit_from_worktree.dart`/`worktree_guard_lib.dart` (same gap, found by
  B-pass, fixed for consistency).

## Round 1 (×2 context-blind — independent Opus agents, re-derived every claim against the actual
repo rather than trusting the plan's prose)
- **F1 — P0:** the ship-dark gate change was documented in CLAUDE.md but never actually coded —
  `check_plan_review_record_exists.dart` still hard-required `review_rounds >= 2` unconditionally.
  Would have made the headline feature dead-on-arrival (CI-red on the first ship-dark merge). Fixed:
  implemented the `tier: ship_dark_build` exception for real, `bpass` check left untouched.
- **F2 — P1:** the original detection regex was anchored with `^` (no MULTILINE) — silently missed
  a `git commit`/`git push` on any line after the first in a multi-line Bash command, the DOMINANT
  shape Claude actually emits. Empirically reproduced by the reviewer. Fixed: extracted
  `scripts/git_safety_lib.dart` with statement-splitting (`\n`/`;`/`&&`/`||`/`|`) detection;
  regression-tested (`test/contracts/git_safety_lib_test.dart`, includes the exact multi-line case).
- **F3 — P1:** `/build-apk`'s Gate 2 versionCode-bump commit is a raw `git commit` that the new hook
  would have blocked, contradicting the author's own (unverified) claim that build-apk never
  commits. Fixed: routed through `safe_commit.sh`; documented the wrapper requirement in
  `build-apk.md` itself.
- F6/F7 — P2: `safe_push.sh` could false-FAIL on a transient `ls-remote` blip after a genuinely
  successful push, and had no passthrough for `-u`/`--force-with-lease`/`--tags`. Fixed: retry
  before failing; extra-args passthrough.
- F5 — P2: no test/pure-lib split for the new hook, unlike the pattern it mirrors. Fixed: extracted
  `git_safety_lib.dart` + contract test (this is what caught F2 for real, not just by inspection).
- F4/F8/F9 — P2/P3, non-blocking, acknowledged (F4: local precheck's cwd-vs-integration-push
  scenario, addressed by Round 2's advisory-only redesign; F9: the ledger is manually-maintained by
  design, explicitly deferred to a follow-up gate per §4.11).

## Round 2 (×2 — on the Round-1-hardened diff) — findings, fixed
- Re-verified every Round-1 fix independently (re-read the code, ran the hook binary and the
  contract test directly) — all VERIFIED-FIXED, no round-1 fix left STILL-BROKEN, and the
  corrections introduced no regression (bpass/hermes cross-check clean).
- **N1 — the one blocking finding:** the local plan-review-record precheck hard-denied any
  push-shaped command on a non-zero exit from the gate script, with NO escape hatch — capable of
  wedging the sole sanctioned integration-push path if the precheck itself ever misbehaved
  (toolchain hiccup, an edge case in its own logic), on a safety batch that exists specifically to
  prevent unescapable failure modes. Fixed: made the precheck advisory-only (warn, never deny,
  wrapped in try/catch) — it is a pure local optimization since CI re-runs the identical gate as
  the real backstop, so this loses zero enforcement, only the "catch before the round-trip" timing
  benefit in the cases it doesn't fire cleanly.
- N2-N6/F9 — P2/P3, non-blocking, acknowledged (N2: `dart run` cold-start cost on every Bash call,
  a known UX tradeoff not addressed this batch; N3: env-var-prefixed/subshell-wrapped raw commands
  are an unhandled edge case, low practical risk, defense-in-depth only; N4: cwd-vs-cd-prefixed
  integration push — CI backstops regardless; N5: round relaxation isn't clamped below catastrophic,
  but bpass+hermes still gate it there; N6: `tier:` key-naming clarity, cosmetic).

## B-pass (fresh Sonnet subagent, 5-lens adversarial pass, after both review rounds) — 6 findings,
all fixed in-batch (see `docs/reviews/discipline-overhead-review.md` for full detail)
- Finding 1 (P1): the N1 fix existed only in the working tree at review time — committed.
- Finding 2 (P1): `git_safety_hook.dart`/`git_safety_lib.dart`/`.claude/settings.json` had no
  explicit blast-radius override (feature-tier catch-all) despite being the highest-blast-radius
  files in the diff — a future change touching only them would clear zero review gate. Fixed:
  explicit platform-tier overrides, extended to the pre-existing worktree-guard files for
  consistency (same gap, same reasoning).
- Finding 3 (P2): the advisory warning used raw `stderr.writeln` on a non-blocking return —
  `discipline_hook.dart`'s own documented channel contract says that's debug-log-only, so the
  warning likely wasn't visible at all. Fixed: mirrors `discipline_hook.dart`'s
  `hookSpecificOutput.additionalContext` JSON channel exactly.
- Finding 4 (P2): missing stdin timeout/hasTerminal guard, unlike the sibling hook — a hang risk
  on every future Bash call. Fixed: mirrored the existing pattern exactly.
- Finding 5 (P2): zero test coverage of the hook's actual stdin-JSON wire contract (only the pure
  functions were tested). Fixed: added `test/contracts/git_safety_hook_integration_test.dart`, 8
  cases spawning the real subprocess with real JSON — caught and fixed an unrelated Windows
  `Process.start` PATHEXT issue (`runInShell: true`) in the process of making it actually pass.
- Finding 6 (P3): unchecked `cd "$REPO_ROOT"` in both wrapper scripts. Fixed: guarded both.

## Verdict: converged
Three independent passes (×2 context-blind + B-pass) each found genuinely new, material issues —
including one P0 (a headline feature that was documented but never implemented) and one review-
round-2 finding on the review-round-1 fix itself (N1), exactly the "corrections can introduce new
defects" pattern §4.12 exists to catch. No pass rubber-stamped the prior one; every finding was
independently re-verified against the actual code (not the author's prose) before being accepted
as fixed. Final state: `flutter analyze` clean; `flutter test test/contracts/git_safety_lib_test.dart
test/contracts/git_safety_hook_integration_test.dart` 30/30 green; the full pre-commit gate suite
passed on the landing commit. Self-initiated B-pass run before merge per §4.3.
