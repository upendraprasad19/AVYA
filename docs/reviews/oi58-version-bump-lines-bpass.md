---
reviewed_at: 2026-07-28
branch: oi58-version-bump-lines
staged_against: a7c62c10ceb4
blast_radius: platform
reviewer: fresh context-blind sonnet subagent (/code-review B-pass)
lens_set: [fail_open_paths, exemption_soundness, regression, test_vacuity, claim_accuracy, gate_wiring]
findings_count: 7
verdict: accepted
---

# B-pass — oi58-version-bump-lines

**2 P0, 1 P1, 4 P3. All fixed.** This pass earned its place twice over: it broke
the exemption after two independent rounds had passed it, and it caught a claim
I had copied into a durable record without checking.

## P0 — a SECOND version token changes freely

`normalizeVersionToken` checked `hasMatch` (≥ 1) then called `replaceAll`. With
two version-shaped tokens in one file, both collapse to the same placeholder, so
the second one's value is unconstrained between before and after.

Works on both exempt-eligible files:

- `pubspec.yaml` with a duplicate top-level `version:` key — line 1 does a
  believable bump while line 2 changes silently;
- `app_constants.dart` with a **second class** declaring its own
  `static const String appVersion` — valid, compiling Dart. Unlike pubspec
  (where `pub` eventually rejects duplicate keys) there is no downstream
  circuit-breaker at all.

Fixed: `allMatches(content).length != 1` → reject. Zero matches is equally
disqualifying — normalising nothing would compare two raw blobs as though they
had been normalised.

## P0 — converting the file to a symlink

`git show <rev>:<path>` returns a symlink's **link-target text** as if it were
file content. Swapping `pubspec.yaml` for a symlink (mode `120000`) whose target
string reads like a bumped pubspec was granted the exemption; the code never
looked at the tree mode anywhere.

Fixed: the record now carries `beforeMode`/`afterMode` and both must be
`100644`/`100755`. A submodule/gitlink already failed closed — but only because
`git show` happens to error on a gitlink, which is luck rather than design, and
luck does not generalise to symlinks.

**Both of these were listed in round 2's report as attacks it had tried and
defeated.** I repeated that in the plan-review record without verifying it. Both
reproduced for me on the first attempt. That is
`feedback_audit_verifier_cannot_trust_own_subagent`, committed inside the record
whose whole purpose is to be the trustworthy account — corrected in place, with
the correction left visible.

## P1 — the new binary-file control was vacuous

The "a BINARY file does not crash the gate" test put its payload at
`lib/features/auth/icon.png`. `_gitBlob` is only called for `isMigrationSqlPath`
or `versionBumpPaths`, so that path never reaches it: the test passed because a
`lib/features/auth/**` file is graded `account` by path alone. Mutation-tested by
the reviewer — deleting the `FormatException` guard changed nothing.

Moved the payload to `pubspec.yaml`, where it genuinely forces the decode. The
guard *is* load-bearing there: with it removed, the same input crashes with
`FormatException` and exit 255.

## P3 — three stale numbers, each re-derived by me

| Claim | Actual |
|---|---|
| `flutter test test/scripts/` → 90 | **95** |
| 79 tracked binary files | **83** (`git diff --numstat <empty-tree> HEAD`) |
| 19 historical pubspec-only bumps | **17** (`git log --no-merges -- pubspec.yaml`, filtered to commits whose whole change is that file) |

None load-bearing — the "don't require both files" decision holds at 17 exactly
as at 19 — but all three had been carried forward from a report rather than
measured.

## P3 — pre-existing, out of scope, recorded

`_validateRecord` falls back to scanning a record's whole prose when the file has
no `---` frontmatter, so a stray `verdict: converged` line could satisfy it. Not
touched by this diff; the sibling `branch:` check already documents the same
fragility. Left as-is rather than widened mid-batch.

## Lenses that returned clean, with evidence

- **fail_open_paths** — all 28 `exit(0)`/`continue`/`return`/`??` sites
  enumerated; every `_git` vs `_gitOrNull` vs `_gitBlob` choice matches its
  documented intent, and no new path resolves a git failure into a PASS.
- **regression** — the real `be3b4baf` and `8c38c855` re-run against the staged
  gate on actual history (not reconstructions): both still FAIL, file counts
  matching. Two-file bump, pubspec-only bump and the two-commit release push all
  PASS.
- **exemption_soundness (the rest)** — submodule swap, case-only rename,
  `.gitattributes` filters, placeholder-text collision, legitimately-encoded
  U+FFFD, empty files, tab-vs-space separators: all correctly refused, each
  executed against the real gate.
- **gate_wiring** — `check_gate_scripts_wired.dart` PASS (90 scripts);
  `validate_diagnose_doc.dart` OK; the `plan-review-record` job's `fetch-depth: 0`
  and `PUSH_BEFORE` wiring confirmed against `test.yml`.
- **Standard 5** — no Hive, no `functions.invoke`, no `unawaited`, no
  credential-shaped literals; the file is entirely synchronous
  (`Process.runSync`). Confirmed by grep, not assumed.
