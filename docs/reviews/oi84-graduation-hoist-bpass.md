---
reviewed_at: 2026-08-03T21:05:00+05:30
staged_against: oi84-graduation-hoist (branch), base 570feddf
blast_radius: platform
reviewer: fresh-context-blind-sonnet-subagent
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — `oi84-graduation-hoist`

Unit B / OI-84 — the graduation god-screen split. Self-triggered per CLAUDE.md
§4.3 (≥`account`, touches code), run BEFORE the `--no-ff` merge.

## Why this file is not named after the staging hash

The `/code-review` skill names the artifact `docs/reviews/<staging-hash>-review.md`.
That convention exists for `check_code_review_pass_exists.dart`, which — verified
by reading it — **exits 0 for any tier below `catastrophic`** (`:196`). This unit
is `platform` (and was `account` when this review ran — the B-pass fix itself
promoted it by editing `docs/blast_radius.yaml`), so either way it is below
catastrophic and the hash name buys no gate coverage, while it carries a real
hazard: the hash excludes `docs/reviews/` but NOT `docs/plan-reviews/`, so
staging the plan-review record moves the hash *after* the review has been named,
and the record's `bpass_review:` pointer then aims at a filename that no longer
exists. That is precisely what turned `main` red earlier today (`ca4ef2c3` —
`bpass_review: docs/reviews/f01e47438d16-review.md does not exist at
b8e9bf3b`). A branch-derived name is stable under every subsequent edit and
cannot desynchronise from the pointer.

## Findings

### Finding 1 — P1 — blast_radius_mismatch — FIXED

- **file:line:** `docs/blast_radius.yaml:207-216`
- **claim:** Three documents in this diff — the diagnose-doc, the OI-84 closure
  block, and `blast_radius_progress_map_writer_paths_test.dart`'s `reason:`
  string — stated in the PAST TENSE that the stale `account`-rule justification
  for `graduation_screen.dart` **"was restated"**. It had not been.
  `docs/blast_radius.yaml` was not in the diff at all, and its comment still
  read "contains a confirmed direct write to the progress map (`_onPro()`)" —
  false the moment the write moved to `runGraduationPhaseAdvance`.
- **verification:** `git diff --cached --name-only | grep -c blast_radius.yaml`
  → `0`; `sed -n '207,212p' docs/blast_radius.yaml` → pre-hoist text verbatim.
- **why it matters:** The tier itself was never wrong (classifier confirms
  `account` for both the screen and `pro_phase_advance.dart`), so no gate was
  weakened. What was wrong is that this diff asserted its own fix had landed —
  the `feedback_mistake_unverified_done_claims` class, committed inside a change
  that names that exact failure mode twice in its own prose.
- **fix:** The yaml comment was actually rewritten (option (a), not the softer
  option (b) of downgrading the claim to "should be restated"). The stale
  justification is a real defect and the three past-tense statements are now
  true. The rule's TIER is unchanged.
- **status:** fixed

### Finding 2 — P3 — documentation precision — NO CHANGE REQUIRED

- **claim:** "no screen exceeds the 800 ceiling" is false codebase-wide — six
  allow-listed screens do (1466 / 966 / 1264 / 939 / 1986 / 1459 lines).
- **verification:** `wc -l` over the six `_allowList` entries.
- **assessment:** The narrower claim this unit actually makes IS true:
  `graduation_screen.dart` is 552 lines and is absent from `_allowList`. The
  broader phrasing comes from Gate 43's own success message
  (`"OK — no screen exceeds $_maxLines lines."`), which is pre-existing and
  untouched by this diff — it means "no NON-allow-listed screen". Changing that
  string is out of this unit's scope and would be an unrelated edit to a gate
  script; noted here so the imprecision is on record rather than silently
  re-quoted.
- **status:** false_alarm (for this diff) — accurate as a note on the gate's
  wording

### Finding 3 — P3 — test robustness — FIXED

- **file:line:** `test/contracts/phase_unlock_end_to_end_test.dart` `_bodyToEof`
- **claim:** The helper's soundness guard matched only a subsequent `^Future<`
  declaration. A later top-level helper with any other return type (`void`,
  `class`, a sync getter) that happened to mention `commitPhaseAdvance(` would
  have made the check vacuous again — the same shape as the numeric window this
  helper had just replaced.
- **verification:** `grep -n "^Future<" lib/shared/services/pro_phase_advance.dart`
  confirms `runGraduationPhaseAdvance` is currently last, so not exploitable
  today.
- **fix:** The guard now matches any top-level declaration start
  (`Future<|void |class |enum |mixin |extension |String |int |bool |double |List<|Map<|Set<|final |const |@`).
- **status:** fixed

## Lenses returning clean (with evidence)

- **writer_reader_drift** — CLEAN. `commitPhaseAdvance` and
  `markPhaseRepeatNudgePending` bodies are byte-unchanged (only their doc
  comments moved). The relocated caller sets `repeatNudgeFlagged = pins != null`
  and calls the nudge writer on exactly the predicate the old inline closure
  used. The screen's `ref.invalidate(phaseRepeatNudgeProvider)` is now gated on
  the returned flag instead of the local `pins != null` — same predicate, passed
  by value. `home_provider.dart:957` unchanged and not in the diff.
- **function_exception_swallow** — CLEAN. Grep for `.invoke(` across all 16
  changed files → the only hit is prose inside a `docs/sot_registry.yaml`
  comment. No new `try`/`catch` inside `runGraduationPhaseAdvance`; it
  propagates into the screen's pre-existing outer `try` exactly as the closure
  did.
- **secrets_in_tree** — CLEAN. Added lines grepped for `sk-`, `rzp_live_`,
  `AKIA[0-9A-Z]{16}`, `-----BEGIN`, `Bearer …`, `[0-9a-fA-F]{32,}` → 0 matches.
- **unawaited_no_error_sink** — CLEAN. Exactly 3 new `unawaited(` call sites,
  all `ErrorTelemetry.logEvent(...)`, whose body is wrapped in
  `try { … } catch (_) { }` (`error_telemetry.dart:280-312`) — the declared
  sink, matching ~6 pre-existing uses in the unchanged part of the screen.
- **blast_radius_mismatch** — one finding (above); tiers themselves verified
  correct by running the classifier positionally per path.

## Independently re-verified claims

- FOUR `lib/shared → lib/features` imports, not three — both the `package:` and
  the relative `../../../features/` spellings checked.
- The preview test's new orphan guard genuinely asserts the screen renders the
  extracted widgets.
- The new read-only content assertions on `phase2_preview_card.dart` are real
  and currently satisfied.
- `graduation_screen.dart` = 552 lines; absent from `_allowList`; `_maxLines`
  still 800.
- The diagnose-doc passes `validate_diagnose_doc.dart`.

## Verdict

**accepted.** One P1 (a false past-tense claim about this diff's own fix) fixed
by making the claim true. One P3 fixed. One P3 recorded as a pre-existing
imprecision in a gate's success message, out of scope for this unit.
