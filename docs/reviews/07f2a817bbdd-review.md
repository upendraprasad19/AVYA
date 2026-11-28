---
reviewed_at: 2026-09-29T08:50:22+05:30
staged_against: 07f2a817bbdd
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [merge_reconciliation_fidelity, writer_reader_drift, guard_without_its_mirror]
findings_count: 1
verdict: accepted
---

# Code Review — Merge reconciliation 07f2a817bbdd

> Note: the review below was run against staged hash `c57a4d922cb1`. Fixing Finding 1 (a
> `.claude/skills/debugging/SKILL.md` renumber) and a stale cross-reference it surfaced in
> `docs/plan-reviews/oi-245-246-restore-fixes.md` changed the staged diff and moved the hash to
> `07f2a817bbdd` — this file was renamed to match, per the gate's naming contract. No other
> content below was re-verified against the new hash; the fix is a 2-line renumber with no
> semantic effect on anything the review actually checked.

## Scope

This is a **merge-reconciliation-only review**, per the precedent established in
`.claude/skills/code-review/SKILL.md`'s tuning-history entries dated 2026-09-27(d) and
2026-09-28 (second entry today). It is scoped to: did the conflict RESOLUTION of
`git merge origin/main --no-commit --no-ff` (merging `origin/main` tip `6d733480`,
`day-swapper-closeout`, into `oi-245-246-restore-fixes` tip `2d0e7240`) lose, corrupt, or
misplace anything; and is this branch's own new code (OI-245, OI-246, the two Edge Function
regression fixes) still correct sitting on top of the day-swapper batch's refactors. It is
explicitly NOT a re-review of either parent's own already-reviewed feature work (day-swapper +
sync-load's own B-pass/plan-review on `main`; this branch's own B-pass at
`docs/reviews/82620b20f504-review.md`).

Merge base: `794bc2fe` (`Merge branch 'close-oi-258'`). `HEAD` (ours, pre-merge):
`2d0e7240` (`chore(test): remove unused dart:io import...`, parent `6e3975ae` — the OI-245/246
fix commit). `MERGE_HEAD` (theirs): `6d733480`.

## Verification performed

For every claim below, the underlying git objects were read directly (`git show <rev>:<path>`
for base/ours/theirs/staged), never taken from the task brief's prose.

1. **All 8 conflicted files — plumbing reconstruction via `git merge-file -p`.** For each of
   `.claude/skills/code-review/SKILL.md`, `.claude/skills/debugging/SKILL.md`,
   `backups/applied_migrations.json`, `docs/audit/open_issues.md`, `docs/sot_registry.yaml`,
   `lib/core/services/sync/sync_coach.dart`, the naive 3-way merge (base/ours/theirs) was
   reconstructed and diffed against the actually-staged content:
   - `code-review/SKILL.md`, `debugging/SKILL.md`, `sync_coach.dart`: the reconstruction
     differed from the staged content ONLY in the literal conflict-marker lines (textbook clean
     resolution) — with one exception in `sync_coach.dart` worth calling out as a positive
     finding, not a defect: git's naive diff3 reconstruction of that file is actually
     **syntactically broken** (it drops the closing `}` for the newly-inserted
     `isRestoredMediaRow` function, because both sides independently inserted new top-level
     declarations at the exact same point with no shared base content to anchor on). The actual
     staged resolution correctly repairs this by inserting the missing `}` — verified by reading
     `lib/core/services/sync/sync_coach.dart:55-88` directly: `isRestoredMediaRow` (OI-245, this
     branch) and `_coachCreatedAtFromKey` (origin/main, day-swapper) are both present, both
     syntactically complete, both closed correctly. `flutter analyze` was not re-run standalone
     here since the file is part of a larger part-file library (`sync_service.dart`), but the
     brace balance was confirmed by direct reading.
   - `backups/applied_migrations.json`: confirmed via `python3 -m json.load` (parses cleanly,
     159 entries) and a scan of the trailing `"migration"` values: ours added 150, 151; theirs
     added 149; base ended at 148. Staged correctly interleaves them as 148 → 149 (theirs) → 150 →
     151 (ours) — exact numeric order — and `ls supabase/migrations/ | grep -E '^(147|148|149|150|151)_'`
     confirms migration files 147-151 all exist on disk matching this exact ledger order.
   - `docs/audit/open_issues.md`: git's naive reconstruction is broken here too (both sides
     independently appended a new `## OI-268` section at the same point). Since this board is
     insertion-order-sensitive rather than strictly append-only, fidelity was checked as a
     **union-completeness proof** rather than a marker-diff: extracted every `## OI-NNN` header
     from ours (171) and theirs (174), deduped their union, and diffed against the staged set
     (176) — **empty diff, exact match**. Spot-checked two section BODIES byte-for-byte:
     `OI-260` (theirs-only) and `OI-245` (ours-only) both diff empty against their source parent's
     content — nothing was truncated or altered at the splice boundary.
   - `docs/sot_registry.yaml`: 6 distinct sub-conflicts (line-number citations only, no content
     conflicts). Independently re-derived and verified all 3 of the post-gate-fix corrected
     citations against the actual file content (not trusting the task brief's numbers):
     - `resolveSummarySetCount` in `workout_write_service.dart`: registry cites `1491-1505`.
       `grep -n "resolveSummarySetCount"` confirms the signature is at line 1491 and the closing
       `}` is at line 1505. **Exact match.**
     - `syncCoachMemoryNow` in `sync_coach.dart`: registry cites `99-144` for the full function
       and `126-127` for the "upward projection" sub-range. `awk 'NR==99||NR==126||NR==127||NR==144'`
       confirms line 99 is the signature, 126-127 are exactly the `coaching_notes` →
       `coach_notes` mapping lines, and 144 is the closing `}`. **Exact match on all three.**
     - A fourth citation in the same file (`_drainPendingTemplateDeletes` /
       `restoreOpTimeout`, both re-derived during the same hand-resolution) was also spot-checked
       independently: `_drainPendingTemplateDeletes` cites `1479-1520` in
       `sync_workout.dart` — confirmed the function's signature and closing brace sit exactly
       there. `restoreOpTimeout` in `sync_service.dart` cites `2507-2507` — confirmed
       `static const Duration restoreOpTimeout = Duration(seconds: 45);` is exactly at line 2507
       (neither ours' stale `2420` nor theirs' stale `2496-2496` — a genuinely re-derived third
       value, correct).
     - `docs/sot_registry.yaml` is not strict YAML (PyYAML chokes on an unquoted flow-sequence
       item at line 493, `fields_read: [via _schedule.getScheduleForDate(date) at :351, ...]`) —
       confirmed this exact line is byte-identical across base/ours/theirs, i.e. a pre-existing
       repo convention unrelated to and untouched by this merge, not a reconciliation defect.
       (The registry's own gate, `check_sot_registry_parity.dart`, uses different tooling and
       passes — see below.)
   - Both generated files (`docs/audit/OPEN_INDEX.md`, `docs/diagnoses/INDEX.md`) were
     **actually regenerated** against this merged tree via `dart run scripts/build_oi_index.dart`
     and `dart run scripts/build_bug_index.dart`, and diffed byte-for-byte against the staged
     content: **zero diff, both files**. Confirms these are genuinely machine-generated output,
     not hand-edited to merely look regenerated.

2. **`lib/core/services/sync/sync_coach.dart` call sites.** `isRestoredMediaRow` is called at
   `:317` inside `_restoreCoachInteractions`'s row-mapping; `_coachCreatedAtFromKey` is called at
   `:237` inside `_syncCoachInteractions`'s orphan-write payload builder. Both are real,
   non-dead call sites with existing regression tests
   (`test/contracts/coach_restored_media_mode_writer_to_reader_test.dart`,
   `test/contracts/hard_failure_apology_texts_parity_test.dart`). The `now()`-fallback vs.
   `_coachCreatedAtFromKey` discrepancy noticed while reading this region (ours still had a
   `DateTime.now()` fallback at the pre-merge tip; theirs had already replaced it) was traced to
   the merge BASE already matching ours exactly (`grep` on the base file confirms the `now()`
   fallback was untouched by this branch) — so git's 3-way merge correctly auto-resolved to
   theirs' improved version with no conflict and no human intervention needed there. Not a
   defect.

3. **`scripts/sync_hash_skip_atomicity_lib.dart` allowlist addition.** Read
   `_drainPendingExlogDeletes` (`lib/core/services/sync/sync_workout.dart:216-239`) directly: it
   iterates `PendingExlogDeletes.read()`, UPSERTs a tombstone row inside a `try`, and calls
   `PendingExlogDeletes.remove(...)` only on the line immediately after a successful `await`
   upsert — inside the same `try` block, after the write, never before it. The `catch` block logs
   + records telemetry and does NOT call `remove`, so a failed upsert leaves the entry queued for
   the next sync pass. This is structurally identical to the pre-existing
   `_drainPendingTemplateDeletes` (`sync_workout.dart:1479-1520`) that the allowlist comment cites
   as precedent. Ran `check_sync_hash_skip_atomicity.dart` and `check_sot_registry_parity.dart`
   directly against this tree: both **PASS**. The allowlist addition is a genuine fix, not a
   rubber stamp.

4. **Interaction with `SyncSkipIndex` (day-swapper's refactor).** Read `SyncSkipIndex.clearAll`
   (`sync_skip_index.dart:328-350`): it only deletes per-domain fingerprint-index Hive keys (the
   "did we already send this row's current content" mechanism used by the `sync_epoch` repair
   lever). `PendingExlogDeletes`/`PendingTemplateDeletes` are a structurally separate mechanism —
   a delete-tombstone queue stored under `HiveService.instance.userBox`, answering "is there a
   pending delete we haven't pushed yet" — and neither the new nor the pre-existing pending-delete
   queue participates in `clearAll`, by design and consistently on both sides. Cross-checked
   against `docs/architecture/sync.md`'s "Restore conflict policy" section (this branch's own
   added bullet, `:380-394`): the intended mechanism for surviving restore is the server-side
   rename-on-delete trigger (migrations 150+151, `BEFORE INSERT OR UPDATE`), not participation in
   the client-side skip-index. `_drainPendingExlogDeletes` is correctly wired at the top of
   `_syncExerciseLogs` (`:256`), before the `SyncSkipIndex`-based per-row push loop, matching the
   doc comment's stated intent. No interaction defect.

5. **Primary-worktree hygiene / stray debris.** `git status --porcelain` shows 234 entries, all
   `A`/`M`/`D`/`R` (124/105/4/1) — **zero untracked (`??`) files**. None of the primary worktree's
   known unrelated untracked debris (`AVYA_ARCHITECTURE_REPORT.md`, `SPEC_TEMPLATE_BRAINSTORM.md`,
   `scripts/spec_gate_hook.dart`, `scripts/supabase_login_daemon.py`,
   `scripts/supabase_login_pty.py`, visible in the PRIMARY worktree's git status at session start)
   appears anywhere in this linked worktree's status. Confirms no cross-worktree contamination.

## Finding 1 — P2 — guard_without_its_mirror

**Claim:** the hand-resolution of `.claude/skills/debugging/SKILL.md` (conflict #2 in the task
brief) introduced a genuine, NEW bug-class numbering collision at `### 2.74` — two unrelated
entries both titled with the same section number — that exists on neither parent branch alone.

**Evidence:**
- `grep -oE "^### [0-9]+\.[0-9]+" .claude/skills/debugging/SKILL.md | sort | uniq -d` returns 10
  duplicated numbers: `2.36, 2.37, 2.38, 2.39, 2.40, 2.41, 2.53, 2.54, 2.55, 2.74`.
- The first 9 are **pre-existing** — confirmed present, identically, in the merge-base file
  already (`grep` against `base`/`ours`/`theirs` all return the same 9 duplicates) — out of scope
  for this merge-reconciliation review, unrelated to and untouched by this merge.
- `### 2.74` is different: it does **not** appear as a duplicate in `ours` alone (this branch's
  own file has exactly one `### 2.74`, titled "A NEW call site shares an EXISTING source-grep
  test's marker literal..." dated 2026-09-29 — its own new entry, the `_drainPendingExlogDeletes`
  /`indexOf`-anchoring fix). It does **not** appear as a duplicate in `theirs` alone either
  (origin/main's own file has exactly one `### 2.74`, titled "A `getWeek()`-style reader that
  omits absent keys..." dated 2026-09-28). Each branch independently picked `2.74` as its own
  "next free number" (ours' last pre-existing entry was `2.73`; theirs had already moved past it
  to `2.75`/`2.76` with its OWN `2.74`). The merge combined both bodies intact — no content was
  lost or truncated — but did not renumber either one, so the merged file now has **two
  completely different bug-class entries both citing `### 2.74`** (verified via
  `grep -n "^### 2\.74" .claude/skills/debugging/SKILL.md` → lines 1436 and 1503; the staged
  file's numeric tail is `...2.73, 2.74, 2.74, 2.75, 2.76`).
- This is exactly the collision class this same repository's `mint_oi.sh` / `check_oi_numbering_unique.dart`
  machinery exists to prevent for OI numbers (`CLAUDE.md` §7, "OI number uniqueness across
  branches" row) — two independent sessions picking the same next-available sequence number and
  a merge silently landing both. No equivalent allocator or uniqueness gate exists for this
  file's `### N.M` bug-class numbering scheme (`grep -rn "debugging/SKILL.md" scripts/check_*.dart`
  returns nothing), so nothing in the pre-commit/CI gate loop will catch or flag this.
- Not a runtime bug and does not block the merge functionally, but it is a genuine fidelity
  defect the task's own framing ("kept both, no number collision") explicitly claimed did not
  happen, and it degrades the file's own stated purpose (a numbered bug-class index other bug
  fixes are meant to cross-reference by number — e.g. `docs/diagnoses/*.md` `related_bugs:`
  fields citing "bug-class 2.74" would now be ambiguous between the two).

**Suggested fix:** renumber one of the two `2.74` entries to the next free number after the
file's true tail (`2.77`, since `2.76` is theirs' last entry) — most naturally the entry that
sorts later in the merged file (the `_drainPendingExlogDeletes`/`indexOf` entry, currently at
line 1503, which is this branch's own addition and the smaller diff to touch), and update its
own self-reference if any (none found — the entry does not cite its own number internally). No
other file references `### 2.74` by number (checked: `grep -rn "2\.74" .claude .` outside the
SKILL.md file itself returns nothing), so this is a single-line renumber with no fan-out.

**Status:** fixed. Renumbered the `_drainPendingExlogDeletes`/`indexOf`-anchoring entry
(this branch's own, the smaller diff to touch) from `### 2.74` to `### 2.77` — confirmed `2.77`
was free (`grep -n "2\.77" .claude/skills/debugging/SKILL.md` returned nothing before the edit).
Also found, independently, ONE additional stale cross-reference the review's own
`grep -rn "2\.74" .claude .` check missed: `docs/plan-reviews/oi-245-246-restore-fixes.md:120`
cited "§2.74" by number for this same entry — updated to "§2.77 (renumbered from §2.74 during
the origin/main merge-reconciliation...)". Re-grepped the whole tree for `§2\.74\|bug-class 2\.74\|class 2\.74\b`
excluding the SKILL.md file itself after both fixes: zero remaining hits.

## Addendum (2026-09-29, later same day) — the collision recurred IMMEDIATELY

Before this branch's PR could be merged, a THIRD independent branch
(`schedule-status-single-writer`, PR #51) landed on `main`, requiring a second
merge-reconciliation pass (`origin/main` `6d733480`→`3a930526` into this branch).
That pass auto-merged `debugging/SKILL.md` with NO textual conflict — but the
post-merge `grep -oE "^### [0-9]+\.[0-9]+" .claude/skills/debugging/SKILL.md | sort | uniq -d`
sweep (now a standing habit per this review's own detection recipe, added to
CLAUDE.md §4.9 in commit `66a0e367`) caught a SECOND collision: PR #51 had
independently claimed `### 2.77` — the exact number this review had JUST
renumbered this branch's own entry to, hours earlier — for its own unrelated
entry ("A source-grep test survives not just the dead branch it guards, but
also the LATER fix that repairs it", line 1585). Fixed identically: re-derived
the true next-free number (`2.78`, confirmed free), renumbered this branch's
smaller-diff entry again, and fixed the resulting stale citation in
`docs/plan-reviews/oi-245-246-restore-fixes.md`. **This confirms the class is
not a one-off**: a shared self-numbered file with no allocator collides on
every sufficiently-fast-moving concurrent-branch merge, not just the first one
encountered. No change needed to the detection/fix recipe itself — it worked
identically the second time — but the CLAUDE.md pitfall row now cites this
recurrence explicitly as evidence the check must be re-run on EVERY merge
touching the file, not treated as a one-time fix.
