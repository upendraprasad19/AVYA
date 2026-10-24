---
reviewed_at: 2026-10-01T19:11:00+05:30
staged_against: 61353c7b6500 (reviewed tree; findings then fixed — final hash a5a985e852f1, this file's name)
blast_radius: platform
reviewer: claude-sonnet-via-skill (3 fresh context-blind subagents: R1 gemini.ts core, R2 alert/tool-loop/call sites, R3 docs/claims)
lens_set: [guard_without_its_mirror, writer_reader_drift, missing_input, asserted_fixture_value, blast_radius_mismatch, secrets_in_tree, function_exception_swallow, unawaited_no_error_sink]
findings_count: 32
verdict: accepted
---

# Code Review (B-pass) — Part A of `gemini3-limits-caching` (Gemini 3.x migration, outage fix)

Scope: staged Part A diff (49 files at review time). Part B (limits) is not started and is NOT covered; the whole-branch B-pass after Part B is separate. Every finding was verified by the author and fixed in this batch (none deferred); reviewers' surviving mutations were re-run (27 of 27 now redden a test).

## R1 — `_shared/gemini.ts` (14 findings, 0 P0/P1)
| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | P2 | signature-400 dummy retry not remembered; fires on primary; re-sends an identical body when the fill changes nothing | accepted — fixed (`dummyHistory` reused; skipped when `filled === messages`); tests ×3 |
| 2 | P2 | empty-text / signature-only part accepted as a terminal reply on the tools path (geminiChat treats `!text` as failure) | accepted — fixed (judge joined trimmed text); test |
| 3 | P2 | geminiChat 5xx retry classification unpinned | accepted — test (503,503,ok retries) |
| 4 | P2 | both wall-clock deadlines unpinned | accepted — fake-clock tests, both loops |
| 5 | P2 | usage logging / absent `usageMetadata` / zero-arg `functionCall` unpinned | accepted — tests |
| 6 | P2 | fill sanity check unpinned for a signature on a later part | accepted — tests |
| 7 | P3 | `[text(sig), functionCall(unsigned)]` shape premise unprobed | accepted — safety net now uses a FORCED fill; shape stays unprobed (smoke checks it; recorded) |
| 8 | P3 | 404 identity / non-pruning of other 4xx unpinned | accepted — test (403 not pruned) |
| 9 | P3 | misleading "trying fallback" log after prune | accepted — fixed (index in the pass snapshot); test |
| 10 | P3 | dead guards / iteration copy (equivalent mutants) | accepted — commented as defensive, not claimed as covered |
| 11 | P3 | signature regex on a 200-char preview, underscore-only | accepted — fixed (`/thought[\s_]?signature/i` on the untruncated body); test |
| 12 | P3 | geminiChat retries deterministic SAFETY blocks | accepted — fixed (`deterministicFailure`); empty MAX_TOKENS still retried (FC1 symptom; recorded in f3a8d1) |
| 13 | P3 | stale comments; row-coverage test hand-listed | accepted — fixed; test iterates every exported `MODEL_*` |
| 14 | P3 | 408/425 no longer retried (old: any null) | accepted — fixed (transient) |

## R2 — alert / tool-loop / call sites (6 findings, 0 P0/P1)
| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | P2 | tool-loop chat catch's `attemptStatuses` unpinned behaviourally (typo mutation: 0 reds) | accepted — behavioural class test through the real `runToolLoop` |
| 2 | P2 | source-grep pins satisfiable by dead code (3 mutations survived) | accepted — position-pinned slices; per-call balanced-paren argument checks |
| 3 | P2 | sentinel stamp turns a delivered apology's retry into a 502 + ~20 s client retry loop | accepted — fixed (`replay_hard_failure` replays the flagged 200; 502 only for the threw row) |
| 4 | P3 | `daily-snapshot` / `rolling-context` feed `failed` rows into prompts | accepted — fixed (NULL-safe `.or`; rolling-context skips embed/summary, still deletes) |
| 5 | P3 | class-keyed dedup could page up to 5× per window | accepted — fixed (`transient` collapsed) |
| 6 | P3 | replay fallback label, throw-catch stamp, food label, dead `SUMMARY_MODEL_LABEL` unpinned | accepted — pinned / removed |

## R3 — docs, diagnose-docs, process (12 findings, 0 P0, 1 P1)
P1 `PROF-07` still said `gemini-2.5-pro` (sweep miss) — fixed. P2: test count 759→821, tier 6/12 `verified`→`fixed_in_this_batch` and a ledger claim that did not exist, probe over-attribution (only 2.5-flash-lite was probed), wrong test pointer in a comment — fixed. P3: stale line cites, M2 count, garbled regex-sweep text, OI wording, `MODEL_UNAVAILABLE` log unpinned, plan §8 pre-closing Part B, record's future `bpass_review:` — fixed/noted. Clean: secrets scan, SoT gates (Gate 42 etc.), OI-276 facts, citations.

## Checked clean (all reviewers)
secrets_in_tree (no key/URL in any new log or diff line); deploy set = exactly six EFs (ai-proxy, ai-media-proxy, weekly-report, assess-body-composition, daily-snapshot, rolling-context); no MODEL_* identity comparison left; `.eq("context_json->>class", …)` is valid PostgREST (≈97%, not runnable here — the failure mode is fail-open to `critical`, never a chat break); old `model_used` labels have no reader.
