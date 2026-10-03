---
reviewed_at: 2026-09-23T06:45:00+05:30
staged_against: 0dd33fc9046ec148b3c17ea980329101a57e453f
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, asserted_fixture_value, guard_without_its_mirror]
findings_count: 1
verdict: accepted
---

# Code Review — 0dd33fc9046e

Commit under review: a0c46809 ("chore(build): backfill +44/+45 versionCode
ledger, bump to 1.0.0+46").

## Finding 1 — P2 — asserted_fixture_value
- **file:line:** backups/built_versioncodes.json (the `1.0.0+44` entry's `note`)
- **claim:** the note characterized commit 65bee5d5 as "the very next commit"
  after a4eb42ab. In reality the two commits are 2 days and ~90 commits/11
  merged PRs apart (a4eb42ab 2026-09-19, 65bee5d5 2026-09-21).
- **verification:** `git log --oneline --first-parent a4eb42ab..65bee5d5`
  (11 merges) and `git show -s --format=%ci a4eb42ab 65bee5d5`.
- **note:** the underlying conclusion ("+44 inferred never built") still
  holds — `git log a4eb42ab..65bee5d5 -- backups/built_versioncodes.json`
  is empty and neither ledger has a +44/+45 record-as-built entry anywhere
  in history. Only the timing characterization was wrong.
- **status:** accepted, fixed in the immediate follow-up commit (wording
  corrected to state the actual dates and commit-count gap instead of
  "the very next commit").

## Clean lenses (checked, no findings)
- **writer_reader_drift**: `verify_versioncode_available.dart` reads
  `artifact`/`built_at`/`note` — matches the new entries' shape exactly.
  `dart run scripts/verify_versioncode_available.dart` → PASS for 1.0.0+46.
  `check_app_version_matches_pubspec.dart` → OK, both files at 1.0.0+46.
- **blast_radius_mismatch**: genuinely `platform` — `pubspec.yaml` is a
  hard `glob: platform` rule in `docs/blast_radius.yaml:384`. Confirmed via
  `blast_radius_from_diff.dart` on the correct `--name-only` diff.
- **secrets_in_tree**: none found in the diff.
- **guard_without_its_mirror**: `git grep -n "1.0.0+45"` outside the ledger
  returns zero product-code hits needing an update.
- **General correctness**: both version-bump line diffs are clean
  single-line changes; JSON parses; no other file mangled.

## Founder triage notes
Small, mechanical ledger-backfill + version-bump commit. One wording
correction applied same-review-cycle; no functional issues found.
