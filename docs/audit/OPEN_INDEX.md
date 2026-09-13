# Open Issues — index (auto-generated)

**104 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 8 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below… | 2026-08-05 — flag inventory, dependency… | [:253](open_issues.md#L253) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:323](open_issues.md#L323) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:331](open_issues.md#L331) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — visibility read live (`gh… | [:340](open_issues.md#L340) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — every PR's… | [:371](open_issues.md#L371) |
| OI-58 | Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a) | none — but see the correction below; the… | never (for the residual below; the… | [:405](open_issues.md#L405) |
| OI-60 | Flip `enable_hold_weeks` | 3 remaining flip-on blockers** in… | 2026-08-20 — the blocker list re-derived… | [:479](open_issues.md#L479) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:562](open_issues.md#L562) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:570](open_issues.md#L570) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52,… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:579](open_issues.md#L579) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:587](open_issues.md#L587) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — BLOCKER ONLY (the founder… | [:596](open_issues.md#L596) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:616](open_issues.md#L616) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:628](open_issues.md#L628) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:645](open_issues.md#L645) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:677](open_issues.md#L677) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent… | [:696](open_issues.md#L696) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5,… | [:95](open_issues.md#L95) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9,… | [:146](open_issues.md#L146) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the… | [:176](open_issues.md#L176) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already… | 2026-08-05 (telemetry-readiness… | [:730](open_issues.md#L730) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and… | 2026-08-03 (twice in one day, both times… | [:778](open_issues.md#L778) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED… | 2026-08-05 — record confirmed present by… | [:822](open_issues.md#L822) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now… | 2026-08-10 (`wc -l` = **800** on `main`… | [:878](open_issues.md#L878) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split… | 2026-08-04 (call-site counts below… | [:952](open_issues.md#L952) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and… | 2026-08-05 (found by measuring the… | [:994](open_issues.md#L994) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it… | 2026-08-05 — surfaced by the analyzer… | [:1054](open_issues.md#L1054) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT… | 2026-08-06 — found by the round-2… | [:1082](open_issues.md#L1082) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism… | 2026-08-07 — both definitions read… | [:1116](open_issues.md#L1116) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy… | 2026-08-07 — `_featureSubtitle`'s switch… | [:1169](open_issues.md#L1169) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own… | 2026-08-08 — B-pass on branch… | [:1369](open_issues.md#L1369) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is… | 2026-08-11 — round-2 context-blind… | [:1400](open_issues.md#L1400) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or… | 2026-08-11 — prior-art sweep + round-2… | [:1440](open_issues.md#L1440) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis,… | 2026-08-11 — round-2 review of… | [:1473](open_issues.md#L1473) |
| OI-104 | `check_hooks_installed.dart` detects hook PRESENCE, not staleness;… | nothing technical. | 2026-08-11 — `.git/hooks/pre-commit` and… | [:1494](open_issues.md#L1494) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a… | never — this is OI-102's unanswered… | [:1535](open_issues.md#L1535) |
| OI-107 | `build-apk.md`'s two inline `gh run list` copies should move onto… | nothing technical. It is deliberately… | 2026-08-12 — both call sites read… | [:1564](open_issues.md#L1564) |
| OI-108 | `safe_commit.sh` silently accepts a git FLAG as the commit message (P2) | nothing. The fix is a few lines; it is… | 2026-08-12 — hit live while committing… | [:1595](open_issues.md#L1595) |
| OI-109 | ForgotPasswordSheet's two-step code flow has no test | nothing — bounded work | 2026-08-07 (`grep -rln… | [:1263](open_issues.md#L1263) |
| OI-110 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate… | 2026-08-08 (`dart run… | [:1287](open_issues.md#L1287) |
| OI-111 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a… | 2026-08-07 (grep below run against… | [:1234](open_issues.md#L1234) |
| OI-113 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`,… | [:1324](open_issues.md#L1324) |
| OI-114 | `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only… | nothing | 2026-08-10 (read the file; confirmed the… | [:1343](open_issues.md#L1343) |
| OI-117 | a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2) | nothing. | 2026-08-13 — observed live. The… | [:1648](open_issues.md#L1648) |
| OI-119 | `git_safety_hook.dart` matches command TEXT, so it blocks commands that… | nothing, but it needs a false-positive… | 2026-08-13. ⚠ **The two detectors are… | [:1701](open_issues.md#L1701) |
| OI-120 | the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of… | nothing; needs the same measurement… | 2026-08-13 — both numbers read directly,… | [:1672](open_issues.md#L1672) |
| OI-122 | `check_regression_catalog.dart` runs `flutter test` with no concurrency… | nothing technical. Needs a measurement… | 2026-08-13 — read directly at… | [:1626](open_issues.md#L1626) |
| OI-123 | the test-suite UPSERT path is guarded only transitively, by file ordering… | nothing — scoped and understood; needs… | 2026-08-15 — Hermes lens (destructive-op… | [:1762](open_issues.md#L1762) |
| OI-124 | the device delete-account test hard-deletes `auth.users` with NO… | nothing technical. It is currently… | 2026-08-15 — Hermes lens (destructive-op… | [:1793](open_issues.md#L1793) |
| OI-125 | Selectable past hold weeks (FOB-6) — 6 named lifecycle traps | none technically — but it is a NEW… | 2026-08-13 — filed from… | [:1817](open_issues.md#L1817) |
| OI-126 | The `logged` / `custom_template` training-day predicate split (5 call… | none. Pickable, but it is a live… | 2026-08-13 — the 5 call sites and the… | [:1844](open_issues.md#L1844) |
| OI-127 | `plan_start` moving under a live hold week: is the streak identity still… | none. Route to the piece that already… | 2026-08-13 — the four `plan_start` write… | [:1873](open_issues.md#L1873) |
| OI-130 | concurrent sessions have no way to see what another is working on, so the… | nothing technical, but the cheap fixes… | 2026-08-16 — three measured instances,… | [:1923](open_issues.md#L1923) |
| OI-131 | the golden tests are excluded from every gate on every platform, so they… | nothing technical — but it needs a… | 2026-08-20 — measured while fixing… | [:1980](open_issues.md#L1980) |
| OI-134 | mutation-proving runs in the shared worktree, where §4.13's guarantee does… | nothing. Small and self-contained. | 2026-08-20 — observed live, twice, by… | [:2021](open_issues.md#L2021) |
| OI-135 | 60 of 125 migration-ledger hashes do not match their files, and nothing… | nothing technical. The fix shape is… | 2026-08-20 — measured, not estimated.… | [:2062](open_issues.md#L2062) |
| OI-136 | Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files… | nothing technical. Needs the same… | 2026-08-20 — measured, not inferred.… | [:2100](open_issues.md#L2100) |
| OI-137 | the migration-ledger gate checks that `hash:` EXISTS, never that it is a… | nothing technical. Same… | 2026-08-20 — reproduced, not inferred.… | [:2143](open_issues.md#L2143) |
| OI-138 | `retire_worktree` removes the worktree but leaves the BRANCH, silently… | none. Small, but see the trap below — it… | 2026-08-25 — read… | [:2181](open_issues.md#L2181) |
| OI-139 | the only tool that DELETES developer work is tiered `feature`; every tool… | FOUNDER. This is a governance decision,… | 2026-08-25 — `grep -n retire_worktree… | [:2217](open_issues.md#L2217) |
| OI-140 | nothing detects a duplicate diagnose `bug_id`, though the identical… | none. | 2026-08-25 — `ls docs/diagnoses/*.md \|… | [:2255](open_issues.md#L2255) |
| OI-141 | retire the notification-preferences snapshot fallback once APK +39 is… | APK +39 adoption — a founder release… | 2026-08-26 — filed as the tracked half… | [:1195](open_issues.md#L1195) |
| OI-142 | deploy-artifact commits are unenforced: prod runs Edge Function code whose… | none. | 2026-08-27 — the class was LIVE in the… | [:2330](open_issues.md#L2330) |
| OI-143 | nothing checks whether a multi-task BATCH is finished; the Stop hook only… | nothing technical. Needs a design call… | 2026-08-28 — observed live, repeatedly,… | [:2290](open_issues.md#L2290) |
| OI-145 | 34 licence-clean drawings depict bodyweight exercises the library does not… | nothing technical. It needs the… | 2026-08-29 — the 302-entry manifest of… | [:2373](open_issues.md#L2373) |
| OI-146 | three duplicate exercise rows, two of them dead, one skewing selection… | nothing. Needs a decision on whether the… | 2026-08-29 — name-normalised (case,… | [:2413](open_issues.md#L2413) |
| OI-147 | remove Donkey Calf Raise: a one-row deletion that touches the cloud seed,… | nothing technical. Needs the… | 2026-08-29 — every claim below… | [:2469](open_issues.md#L2469) |
| OI-148 | 23 equipment-variant exercises the plate mapping surfaced, blocked on a… | the selection-skew question below. Not… | 2026-08-29 — each named row checked… | [:2531](open_issues.md#L2531) |
| OI-149 | breathing_cue holds a bare number on 136 of 292 rows; the original text is… | the founder** — 136 replacement cues… | 2026-08-29 — counted, and the recovery… | [:2561](open_issues.md#L2561) |
| OI-151 | telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and… | nothing technical. It is a PRE-LAUNCH… | 2026-08-30 — measured live on… | [:2593](open_issues.md#L2593) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2645](open_issues.md#L2645) |
| OI-153 | PRO media caps read a `channel` value nothing writes (P1) | enumerate every `channel` reader first | 2026-09-03 — source + live prod | [:2687](open_issues.md#L2687) |
| OI-154 | a cleared profile field silently reverts on the next sign-in (P1) | needs a design spec (tombstone +… | 2026-09-03 — source, full chain traced | [:2856](open_issues.md#L2856) |
| OI-155 | six gates are wired to no runner, and Gate 33 cannot detect it (P1) | re-enumerate the skip block mechanically | 2026-09-03 — greps with positive control | [:2879](open_issues.md#L2879) |
| OI-156 | CLAUDE.md numeric claims drift because nothing re-derives them (P2) | nothing — mechanical | 2026-09-03 — each count re-measured | [:2903](open_issues.md#L2903) |
| OI-157 | no SAST and no SCA run anywhere in CI (P1) | founder call on Semgrep scope | 2026-09-03 — grep, 0 hits | [:2928](open_issues.md#L2928) |
| OI-158 | tests and gates that cannot fail (P2) | TEST-1 needs one device run to establish… | 2026-09-03 — source-verified | [:2948](open_issues.md#L2948) |
| OI-159 | sync and Edge Function correctness residue (P2) | nothing — but see OI-154 for the ARCH-1… | 2026-09-03 — source-verified | [:2971](open_issues.md#L2971) |
| OI-160 | dependency + build-toolchain hygiene (P2) | DEP-7 needs a founder unpin decision | 2026-09-03 — versions read from files | [:2991](open_issues.md#L2991) |
| OI-161 | two blind spots in our own observability and discipline gates (P3) | INFRA-13 is platform-tier, needs its own… | 2026-09-03 — live query + grep | [:3014](open_issues.md#L3014) |
| OI-163 | the four-tag migration header has NO gate, and two places claimed it did… | nothing — needs a gate written,… | 2026-09-05 — repo-wide grep + the live… | [:3163](open_issues.md#L3163) |
| OI-164 | the shared QA account caps CI at ~3 runs per IST day (P2) | a founder decision on test-account… | 2026-09-05 — live `usage_counters` + the… | [:3187](open_issues.md#L3187) |
| OI-165 | `check_onconflict_live_arbiter.dart` 403s, so every `test/sql/` live… | identifying which token the runner needs… | 2026-09-05 — ran it; and the harness… | [:3209](open_issues.md#L3209) |
| OI-166 | regeneration RESTARTS the periodization wave instead of continuing it, so… | OI-175 (the window-alignment half —… | 2026-09-06 — every citation below… | [:3231](open_issues.md#L3231) |
| OI-167 | the debugging skill's bug-class numbers collide 9×, every one is cited by… | nothing technical — needs a per-citation… | 2026-09-07 — `grep -oE '^### 2\.[0-9]+'… | [:3337](open_issues.md#L3337) |
| OI-168 | nothing fires §4.9's "grep the test tree before you land" rule, so it is… | nothing technical — needs the gate… | 2026-09-07 — the pre-push full suite on… | [:3388](open_issues.md#L3388) |
| OI-169 | a local run of `test/edge_functions/` reports "All tests passed" having… | nothing — needs a decision on which… | 2026-09-07 — `flutter test… | [:3411](open_issues.md#L3411) |
| OI-173 | no cold-start weight estimate: a brand-new user, every free user, and any… | none — founder approved 2026-09-06 as… | 2026-09-06 — `plan_generator.dart:234`… | [:3278](open_issues.md#L3278) |
| OI-174 | schedule rows written past `plan_end` are never pruned, and they delay the… | none — but it is a DESTRUCTIVE migration… | 2026-09-06 — the only schedule deletions… | [:3296](open_issues.md#L3296) |
| OI-175 | a regeneration past the phase's 4th week (`rawWeek > 4`) has no… | FOUNDER — what a regeneration should DO… | 2026-09-06 — `getCurrentWeekNumber()`… | [:3308](open_issues.md#L3308) |
| OI-177 | the live-cron snapshot that gives Gate 31 its only fileless-migration… | none | 2026-09-10 —… | [:3454](open_issues.md#L3454) |
| OI-178 | pg_cron SQL jobs are structurally invisible to the alerting stack:… | a design decision — telemetry bridge vs.… | 2026-09-10 — `cron_call_log` holds… | [:3467](open_issues.md#L3467) |
| OI-179 | `alert_cron_function_dead` cannot fire across 100% of its range, and never… | none — one-line predicate fix; the value… | 2026-09-10 — `min(started_at)` across… | [:3481](open_issues.md#L3481) |
| OI-180 | `check_sot_registry_parity` silently skips every single-number… | none | 2026-09-10 —… | [:3493](open_issues.md#L3493) |
| OI-181 | nothing catches a MISSING plan-review record at merge time; both prechecks… | none | 2026-09-10 — live, by causing it. Branch… | [:3504](open_issues.md#L3504) |
| OI-182 | the payment grace window closes before the last verify-payment retry fires… | none — needs a founder call on the… | 2026-09-11 — read both constants… | [:3520](open_issues.md#L3520) |
| OI-183 | `enforce_vision_analysis_daily_limit`'s channel guard is NULL-unsafe,… | none — one-line NULL-safe rewrite | 2026-09-11 — read the live trigger body… | [:3555](open_issues.md#L3555) |
| OI-184 | 4 tables rely on RLS-zero-policy default-deny alone; the raw grants under… | none — mechanically straightforward (a… | 2026-09-11 — LIVE, via the Management… | [:3603](open_issues.md#L3603) |
| OI-185 | `check_schema_column_refs.dart` validates only the FIRST line of a… | none — carried out of OI-162 (closed… | 2026-09-03 — by the audit (a prototype… | [:3677](open_issues.md#L3677) |
| OI-186 | the AI coach cannot replace ONE day with a different workout: the only… | founder product decision on tier (see… | 2026-09-10 — full census of… | [:3703](open_issues.md#L3703) |
| OI-187 | the AI coach has no read path to the 292-exercise library: the WRITE path… | nothing technical — needs a design… | 2026-09-10 — every claim below re-read… | [:3744](open_issues.md#L3744) |
| OI-188 | no re-entry path for a returning user: the free path hands them a DELOAD… | founder product decision on the… | 2026-09-10 — app behaviour read from… | [:3791](open_issues.md#L3791) |
| OI-189 | Edit-Profile regen now stops at `plan_end`, so orphan rows past it keep… | FOUNDER — a design decision between the… | 2026-09-12 — mechanism re-derived… | [:3841](open_issues.md#L3841) |
| OI-190 | Unit 1's §4.11 gate `check_single_schedule_row_builder.dart` is WARN-only… | none — needs a plan. Input is already… | 2026-09-12 — `dart run… | [:3857](open_issues.md#L3857) |
