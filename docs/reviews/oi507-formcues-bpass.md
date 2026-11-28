---
reviewed_at: 2026-11-24T03:00:00+05:30
staged_against: head c5b382df (committed three-dot diff origin/main...HEAD; base current, 0 behind)
blast_radius: platform
reviewer: claude-sonnet-fresh-agent
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
verdict_note: author triage; no P0 or P1. The P2 is closed by a live REST check, 4 of 5 P3 are fixed in this batch, 1 P3 is declined with its reason. The founder's separate go for the ai-proxy deploy is still required.
---

# Code Review (B-pass) - OI-507 unit A, getFormCues lookup

Scope: `git diff origin/main...HEAD` at c5b382df (15 files, about 590 lines; unit B / PR 331 already merged and applied live). The reviewer ran the four Deno test files for the tool and its two sibling readers (getFormCues 17, like_escape 3, getExerciseHistory 15, getPRTimeline 9, all green), `deno check` of `ai-proxy/index.ts` (clean) and the Dart cloud-seeded contract test (green). It ran no mutation; its mutation claims are reasoning.

## Finding 1 - P2 - guard_without_its_mirror (the fake cannot observe `neq {}` or an escaped `ilike`; the fail-open alias stage hides a dead stage)
- **file:line:** `supabase/functions/_shared/tools/exercise/getFormCues.ts:117-136`, tests `getFormCues_test.ts:15-39` and `:117-118`
- **claim:** `fake_sb.neq` is `v !== val` and its `ilike` has no `_` wildcard, so the tests pass because of a local wrapper; no live REST evidence existed for `name_aliases=neq.{}` or for `ilike` with `\%`. The stage fails open, so a wrong live filter would be silent and "Quad Stretch" would answer "Banded Quad Stretch".
- **verification:** ran the reads live, read-only, with the public anon key on 2026-11-24 (details in the diagnose `live_rest_check`).
- **suggested-fix:** record two REST reads in the diagnose and add a post-deploy smoke for "Quad Stretch".
- **status:** accepted and closed. `is_active=eq.true&name_aliases=neq.{}` answers 200 with exactly 13 rows (14 before unit B removed the lunge alias; NULL rows absent); `name=ilike.\%` and `name=ilike.\_` answer 0 rows; unescaped `name=ilike.%` answers all 870; `name=ilike.Quad Stretch` answers 0 rows (so the alias stage is what resolves it). The post-deploy smoke is written into the plan and the diagnose.

## Finding 2 - P3 - guard_without_its_mirror (ORDER BY name ties on two active rows with one name)
- **file:line:** `getFormCues.ts:104, 120, 148`
- **claim:** `promote-community-item` inserts `is_active: true` rows with no name check and `exercise_library.name` has no unique index, so a tie makes `limit(1)` planner-dependent again.
- **verification:** `sed -n 185,205p supabase/functions/promote-community-item/index.ts`.
- **status:** accepted and fixed: `.order("id")` after `.order("name")` on all three reads; test T10 (two same-name rows listed higher-id first, on each stage). Mutant: `.order("id")` removed from all three reads, T10 red (1 test), restored.

## Finding 3 - P3 - function_exception_swallow (the `try/catch` around the alias stage is untested)
- **file:line:** `getFormCues.ts:114-137`
- **claim:** the T4 fixtures return an error object or a capped read; none makes the read throw, so removing the `catch` kept all 17 tests green.
- **status:** accepted and fixed: test T11 makes the alias read throw and asserts the partial answer and the `alias stage threw` log. Mutant: `try`/`catch` removed, T11 red (1 test), restored.

## Finding 4 - P3 - guard_without_its_mirror (`*` is deleted, not neutralised)
- **file:line:** `getFormCues.ts:67`, `like_escape.ts:13`
- **claim:** a custom exercise named `Squat*` is searched as `Squat` by the two history readers; an input of only `*` answers "exercise_name is required".
- **status:** declined, with the reason. Removing `*` is a recorded plan decision (rev 2, PostgREST turns `*` into `%` and it cannot be escaped), no library name contains `*` (the reviewer's own check), the two history readers are own-data scope, and the diagnose already lists it as an accepted regression. Replacing `*` with `_` would change two more readers for a name nobody has typed; not a false alarm, a scoped decision.

## Finding 5 - P3 - writer_reader_drift (three doc drifts)
- **file:line:** `docs/audit/open_issues.md:6821`, `docs/naming_conventions.md:725`, the diagnose `readers:` cite `line: 60`
- **claim:** (a) the board says unit A must not merge before OI-523 is applied, now satisfied; (b) a `### 9.x` placeholder heading; (c) line 60 is `ALIAS_READ_CAP`, not the handler.
- **status:** accepted and fixed: (a) reworded to "unit B merged as PR 331 and migration 183 is applied live; the ai-proxy deploy still needs its own go"; (b) heading renamed `### escapeLike / ...`; (c) the cite now points at `async function handler` (line 65).

## Finding 6 - P3 - missing_input (`exercise_name` has no length cap)
- **file:line:** `getFormCues.ts:22-27`
- **claim:** CLAUDE.md section 4.4 rule 18 asks for server-side input limits; a very long name goes into a GET query string and `escapeLike` can double it.
- **status:** accepted and fixed: `.max(200)` on the schema (the longest library name is 50 characters, the longest alias 27); test T12 pins 201 refused and 200 accepted. Mutant: `.max(200)` removed, T12 red (1 test), restored. The two sibling readers keep their own schemas; their reads are own-data scope and bounded by the 5K message limit upstream.

## Founder triage notes
Author triage 2026-11-24: no P0 or P1; the P2 was a real observability gap that the live REST check closes (and that check also confirmed the 13-row alias set after unit B). Five findings fixed or closed in this batch, one declined above. The founder's separate explicit go is still required for the `ai-proxy` deploy.

## Tuning entry
- **2026-11-24** - blast-radius platform - 6 findings (1 P2, 5 P3); 0 false_alarm; tuning: none (the P2 re-states the existing lens-6 rule that a guard's fail-open branch needs a fixture that makes the guarded call fail and a live observation the fake cannot give; no lens change).
