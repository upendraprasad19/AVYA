# Open Issues — index (auto-generated)

**244 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 2 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below… | 2026-08-05 — flag inventory, dependency… | [:256](open_issues.md#L256) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:385](open_issues.md#L385) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:393](open_issues.md#L393) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — visibility read live (`gh… | [:402](open_issues.md#L402) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — every PR's… | [:433](open_issues.md#L433) |
| OI-58 | Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a) | none — but see the correction below; the… | never (for the residual below; the… | [:467](open_issues.md#L467) |
| OI-60 | Flip `enable_hold_weeks` | 3 remaining flip-on blockers** in… | 2026-09-26 — blocker list re-derived:… | [:541](open_issues.md#L541) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which… | 2026-09-26 — narrowed. v74: H2 is in… | [:627](open_issues.md#L627) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency… | 2026-09-26 — FC6 SHIPPED… | [:638](open_issues.md#L638) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:650](open_issues.md#L650) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — BLOCKER ONLY (the founder… | [:659](open_issues.md#L659) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:679](open_issues.md#L679) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:696](open_issues.md#L696) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:728](open_issues.md#L728) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent… | [:747](open_issues.md#L747) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5,… | [:95](open_issues.md#L95) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-09-26 — ROOT CAUSE FOUND: the… | [:146](open_issues.md#L146) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the… | [:179](open_issues.md#L179) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already… | 2026-08-05 (telemetry-readiness… | [:781](open_issues.md#L781) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | founder scheduling of U2b (its own plan… | 2026-09-26 — NARROWED. The "Box not… | [:829](open_issues.md#L829) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED… | 2026-09-26 — mostly fixed by OI-181… | [:887](open_issues.md#L887) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now… | 2026-08-10 (`wc -l` = **800** on `main`… | [:946](open_issues.md#L946) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split… | 2026-08-04 (call-site counts below… | [:1020](open_issues.md#L1020) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and… | 2026-08-05 (found by measuring the… | [:1062](open_issues.md#L1062) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it… | 2026-08-05 — surfaced by the analyzer… | [:1122](open_issues.md#L1122) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT… | 2026-08-06 — found by the round-2… | [:1150](open_issues.md#L1150) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism… | 2026-08-07 — both definitions read… | [:1184](open_issues.md#L1184) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy… | 2026-09-26 — 2 live mismatches, not 5:… | [:1237](open_issues.md#L1237) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own… | 2026-08-08 — B-pass on branch… | [:1416](open_issues.md#L1416) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is… | 2026-08-11 — round-2 context-blind… | [:1447](open_issues.md#L1447) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or… | 2026-08-11 — prior-art sweep + round-2… | [:1487](open_issues.md#L1487) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis,… | 2026-08-11 — round-2 review of… | [:1520](open_issues.md#L1520) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a… | never — this is OI-102's unanswered… | [:1541](open_issues.md#L1541) |
| OI-107 | `build-apk.md`'s two inline `gh run list` copies should move onto… | nothing technical. It is deliberately… | 2026-08-12 — both call sites read… | [:1570](open_issues.md#L1570) |
| OI-108 | `safe_commit.sh` silently accepts a git FLAG as the commit message (P2) | nothing. The fix is a few lines; it is… | 2026-08-12 — hit live while committing… | [:1601](open_issues.md#L1601) |
| OI-110 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate… | 2026-08-08 (`dart run… | [:1334](open_issues.md#L1334) |
| OI-111 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a… | 2026-08-07 (grep below run against… | [:1305](open_issues.md#L1305) |
| OI-113 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`,… | [:1371](open_issues.md#L1371) |
| OI-114 | `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only… | nothing | 2026-08-10 (read the file; confirmed the… | [:1390](open_issues.md#L1390) |
| OI-117 | a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2) | nothing. | 2026-08-13 — observed live. The… | [:1654](open_issues.md#L1654) |
| OI-119 | `git_safety_hook.dart` matches command TEXT, so it blocks commands that… | nothing, but it needs a false-positive… | 2026-08-13. ⚠ **The two detectors are… | [:1707](open_issues.md#L1707) |
| OI-120 | the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of… | nothing; needs the same measurement… | 2026-08-13 — both numbers read directly,… | [:1678](open_issues.md#L1678) |
| OI-122 | `check_regression_catalog.dart` runs `flutter test` with no concurrency… | nothing technical. Needs a measurement… | 2026-08-13 — read directly at… | [:1632](open_issues.md#L1632) |
| OI-123 | the test-suite UPSERT path is guarded only transitively, by file ordering… | nothing — scoped and understood; needs… | 2026-08-15 — Hermes lens (destructive-op… | [:1768](open_issues.md#L1768) |
| OI-124 | the device delete-account test hard-deletes `auth.users` with NO… | nothing technical. It is currently… | 2026-08-15 — Hermes lens (destructive-op… | [:1799](open_issues.md#L1799) |
| OI-125 | Selectable past hold weeks (FOB-6) — 6 named lifecycle traps | none technically — but it is a NEW… | 2026-08-13 — filed from… | [:1823](open_issues.md#L1823) |
| OI-126 | The `logged` / `custom_template` training-day predicate split (5 call… | none. The flip-on commit needs its own… | 2026-08-13 — the 5 call sites and the… | [:1850](open_issues.md#L1850) |
| OI-127 | `plan_start` moving under a live hold week: is the streak identity still… | none. Route to the piece that already… | 2026-08-13 — the four `plan_start` write… | [:1894](open_issues.md#L1894) |
| OI-130 | concurrent sessions have no way to see what another is working on, so the… | nothing technical, but the cheap fixes… | 2026-08-16 — three measured instances,… | [:1944](open_issues.md#L1944) |
| OI-131 | the golden tests are excluded from every gate on every platform, so they… | nothing technical — but it needs a… | 2026-08-20 — measured while fixing… | [:2001](open_issues.md#L2001) |
| OI-134 | mutation-proving runs in the shared worktree, where §4.13's guarantee does… | nothing. Small and self-contained. | 2026-08-20 — observed live, twice, by… | [:2042](open_issues.md#L2042) |
| OI-136 | Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files… | nothing technical. Needs the same… | 2026-08-20 — measured, not inferred.… | [:2083](open_issues.md#L2083) |
| OI-139 | the only tool that DELETES developer work is tiered `feature`; every tool… | FOUNDER. This is a governance decision,… | 2026-08-25 — `grep -n retire_worktree… | [:2127](open_issues.md#L2127) |
| OI-140 | nothing detects a duplicate diagnose `bug_id`, though the identical… | none. | 2026-09-26 — LIVE, worse than filed: 3… | [:2165](open_issues.md#L2165) |
| OI-141 | retire the notification-preferences snapshot fallback once APK +39 is… | APK +39 adoption — a founder release… | 2026-08-26 — filed as the tracked half… | [:1266](open_issues.md#L1266) |
| OI-142 | deploy-artifact commits are unenforced: prod runs Edge Function code whose… | none. | 2026-08-27 — the class was LIVE in the… | [:2243](open_issues.md#L2243) |
| OI-143 | nothing checks whether a multi-task BATCH is finished; the Stop hook only… | nothing technical. Needs a design call… | 2026-08-28 — observed live, repeatedly,… | [:2203](open_issues.md#L2203) |
| OI-145 | 34 licence-clean drawings depict bodyweight exercises the library does not… | nothing technical. It needs the… | 2026-08-29 — the 302-entry manifest of… | [:2286](open_issues.md#L2286) |
| OI-146 | three duplicate exercise rows, two of them dead, one skewing selection… | nothing. Needs a decision on whether the… | 2026-08-29 — name-normalised (case,… | [:2326](open_issues.md#L2326) |
| OI-147 | remove Donkey Calf Raise: a one-row deletion that touches the cloud seed,… | nothing technical. Needs the… | 2026-08-29 — every claim below… | [:2382](open_issues.md#L2382) |
| OI-148 | 23 equipment-variant exercises the plate mapping surfaced, blocked on a… | the selection-skew question below. Not… | 2026-08-29 — each named row checked… | [:2444](open_issues.md#L2444) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2474](open_issues.md#L2474) |
| OI-154 | a cleared profile field silently reverts on the next sign-in (P3, was P1) | FOUNDER — product choice (below).… | 2026-09-29 — re-traced against `main` @… | [:2516](open_issues.md#L2516) |
| OI-156 | CLAUDE.md numeric claims drift because nothing re-derives them (P2) | nothing — mechanical | 2026-09-03 — each count re-measured | [:2576](open_issues.md#L2576) |
| OI-157 | no SAST and no SCA run anywhere in CI (P1) | founder call on Semgrep scope | 2026-09-03 — grep, 0 hits | [:2601](open_issues.md#L2601) |
| OI-158 | tests and gates that cannot fail (P2) | TEST-1 needs one device run to establish… | 2026-09-03 — source-verified | [:2621](open_issues.md#L2621) |
| OI-159 | sync and Edge Function correctness residue (P2) | nothing — but see OI-154 for the ARCH-1… | 2026-09-03 — source-verified | [:2644](open_issues.md#L2644) |
| OI-160 | dependency + build-toolchain hygiene (P2) | DEP-7 needs a founder unpin decision | 2026-09-03 — versions read from files | [:2664](open_issues.md#L2664) |
| OI-161 | two blind spots in our own observability and discipline gates (P3) | INFRA-13 is platform-tier, needs its own… | 2026-09-03 — live query + grep | [:2687](open_issues.md#L2687) |
| OI-163 | the four-tag migration header has NO gate, and two places claimed it did… | nothing — needs a gate written,… | 2026-09-05 — repo-wide grep + the live… | [:2729](open_issues.md#L2729) |
| OI-164 | the shared QA account caps CI at ~3 runs per IST day (P2) | a founder decision on test-account… | 2026-09-05 — live `usage_counters` + the… | [:2753](open_issues.md#L2753) |
| OI-166 | regeneration RESTARTS the periodization wave instead of continuing it, so… | OI-175 (the window-alignment half —… | 2026-09-06 — every citation below… | [:2775](open_issues.md#L2775) |
| OI-167 | the debugging skill's bug-class numbers collide 9×, every one is cited by… | nothing technical — needs a per-citation… | 2026-09-07 — `grep -oE '^### 2\.[0-9]+'… | [:2882](open_issues.md#L2882) |
| OI-169 | a local run of `test/edge_functions/` reports "All tests passed" having… | nothing — needs a decision on which… | 2026-09-07 — `flutter test… | [:2933](open_issues.md#L2933) |
| OI-173 | no cold-start weight estimate: a brand-new user, every free user, and any… | none — founder approved 2026-09-06 as… | 2026-09-06 — `plan_generator.dart:234`… | [:2822](open_issues.md#L2822) |
| OI-174 | schedule rows written past `plan_end` are never pruned, and they delay the… | none — NARROWED 2026-09-13 by OI-189… | 2026-09-13 — re-derived while closing… | [:2840](open_issues.md#L2840) |
| OI-175 | a regeneration past the phase's 4th week (`rawWeek > 4`) has no… | FOUNDER — what a regeneration should DO… | 2026-09-06 — `getCurrentWeekNumber()`… | [:2865](open_issues.md#L2865) |
| OI-177 | the live-cron snapshot that gives Gate 31 its only fileless-migration… | none | 2026-09-10 —… | [:2950](open_issues.md#L2950) |
| OI-179 | `alert_cron_function_dead` cannot fire across 100% of its range, and never… | none — one-line predicate fix; the value… | 2026-09-26 — the R2-11 PRECONDITION is… | [:2963](open_issues.md#L2963) |
| OI-180 | `check_sot_registry_parity` silently skips every single-number… | none | 2026-09-10 —… | [:2996](open_issues.md#L2996) |
| OI-184 | 4 tables rely on RLS-zero-policy default-deny alone; the raw grants under… | none — mechanically straightforward (a… | 2026-09-11 — LIVE, via the Management… | [:3009](open_issues.md#L3009) |
| OI-185 | `check_schema_column_refs.dart` validates only the FIRST line of a… | none — carried out of OI-162 (closed… | 2026-09-03 — by the audit (a prototype… | [:3083](open_issues.md#L3083) |
| OI-186 | the AI coach cannot replace ONE day with a different workout: the only… | founder product decision on tier (see… | 2026-09-10 — full census of… | [:3109](open_issues.md#L3109) |
| OI-187 | the AI coach has no read path to the 292-exercise library: the WRITE path… | nothing technical — needs a design… | 2026-09-10 — every claim below re-read… | [:3150](open_issues.md#L3150) |
| OI-188 | no re-entry path for a returning user: the free path hands them a DELOAD… | founder product decision on the… | 2026-09-10 — app behaviour read from… | [:3197](open_issues.md#L3197) |
| OI-190 | Unit 1's §4.11 gate `check_single_schedule_row_builder.dart` is WARN-only… | none — needs a plan. Input is already… | 2026-09-12 — `dart run… | [:3253](open_issues.md#L3253) |
| OI-191 | target_weight_kg can contradict the chosen goal's direction, making the… | none — bounded, no… | 2026-09-13 — reproduced live on the… | [:3267](open_issues.md#L3267) |
| OI-192 | the orphan-sync dedupe can never match a photo turn: client writes… | none — pick ONE placeholder shape (or… | 2026-09-13 — source only:… | [:3326](open_issues.md#L3326) |
| OI-193 | Gate 31 treats a COMMENTED `cron.unschedule('X')` as a real unschedule, so… | none — strip `--` comments before the… | 2026-09-12 —… | [:3336](open_issues.md#L3336) |
| OI-194 | `compute_admin_metrics_daily` (jobid 30) skipped its 2026-09-11 18:15Z… | none for the code (repair (d) below is a… | 2026-09-12 — `select function_name,… | [:3347](open_issues.md#L3347) |
| OI-196 | `morning-alert`'s Telegram sender logs the raw fetch error, whose message… | none — one-line change in one function;… | 2026-09-13 — read… | [:3378](open_issues.md#L3378) |
| OI-197 | Founder observability gaps: payment-flow alerting dormant, EF auth-outage… | none — no schema/migration/payment/auth… | never — this is a gap analysis surfaced… | [:3390](open_issues.md#L3390) |
| OI-199 | cleanup_cron_call_log() spares only TWO global rows, not each function's… | none | 2026-09-14, live read of the function… | [:3436](open_issues.md#L3436) |
| OI-200 | founder_metrics_ops().client_errors_today counts benign event-coded… | none | 2026-09-14, B-pass on migration 135… | [:3501](open_issues.md#L3501) |
| OI-201 | alert_cron_function_dead can burst-dispatch many critical alerts at once;… | none | 2026-09-14, Hermes lens L31… | [:3539](open_issues.md#L3539) |
| OI-205 | Already-authenticated user opening a valid /reset link is silently… | none | 2026-09-16, B-pass on the… | [:3581](open_issues.md#L3581) |
| OI-207 | sot_registry.yaml: hold-weeks line_range citations (762-847, 890-915)… | none | 2026-09-26 — real cause is NOT an… | [:3652](open_issues.md#L3652) |
| OI-208 | AuthNotifier._teardown() swallows internal failures with no signal to… | none | 2026-09-16, B-pass on the… | [:3699](open_issues.md#L3699) |
| OI-210 | future-prediction Edge Function has no live caller anywhere in the shipped… | landing L4 of… | 2026-09-16, B-pass on the… | [:3732](open_issues.md#L3732) |
| OI-211 | Custom exercise equipment field + [] to ['none'] backfill of existing rows… | founder batch scheduling | never | [:3801](open_issues.md#L3801) |
| OI-212 | Custom foods unsearchable from the main food search bar (search never… | founder product decision (separate Your… | never | [:3809](open_issues.md#L3809) |
| OI-213 | Razorpay auto-renew subscriptions (web): mandates, subscription.charged… | founder product decision on timing… | 2026-09-17 — claims traced from the… | [:3817](open_issues.md#L3817) |
| OI-214 | Diet plan Option A: curated Indian meal-template layer (recipe-first… | none | never | [:3838](open_issues.md#L3838) |
| OI-215 | Device verification expansion: Patrol flows for the UI-bug cluster,… | none | never | [:3845](open_issues.md#L3845) |
| OI-216 | snapshot-contract gate: per-entry slack mechanism for shift-sensitive… | none | never | [:3863](open_issues.md#L3863) |
| OI-217 | telemetry v2: aggregate plan-review findings by class… | none | never | [:3878](open_issues.md#L3878) |
| OI-218 | Restore-recreated terminal schedule rows lose… | none | never | [:3937](open_issues.md#L3937) |
| OI-219 | is_pr not rescanned across moveExerciseLogs — collision merge can drop a… | none | never | [:3973](open_issues.md#L3973) |
| OI-220 | Contract-sweep gate: pre-push targeted SoT contract testing | one clean batch under `--warn-only`… | 2026-09-19 — shipped on `gate-integrity`… | [:3894](open_issues.md#L3894) |
| OI-221 | tool_dispatcher defensive date-parse fallbacks can clobber the wrong date… | none | never | [:3992](open_issues.md#L3992) |
| OI-222 | Document versionCode-bump-via-merge CI gap in CLAUDE.md §4.9 | none | never | [:4010](open_issues.md#L4010) |
| OI-227 | Telegram coach connect is broken (no linking token, bot says no user… | none — UI removal is self-contained; the… | 2026-09-21 — founder tapped "Connect… | [:4036](open_issues.md#L4036) |
| OI-228 | AI coach shortenWorkout tool calls get stuck at status:queued with no… | none — Bug A is CLOSED; Bug B's "stuck… | 2026-09-22 (Batch B) — live-traced the… | [:4111](open_issues.md#L4111) |
| OI-229 | AI coach chat replies violate captain_manual.ts hard rules: 100-word cap… | none — both are prompt-adherence gaps in… | 2026-09-21 — both cited… | [:4254](open_issues.md#L4254) |
| OI-231 | AI coach addressed a promoted user by their OLD rank term (Recruit instead… | none — live verification DONE (Batch B,… | 2026-09-22 (Batch B) — settled via the… | [:4366](open_issues.md#L4366) |
| OI-233 | user_daily_snapshots' 4 cron/client writers are not atomic against each… | none — scope and fix shape are already… | 2026-09-21 — explicitly scoped out in | [:4486](open_issues.md#L4486) |
| OI-236 | 12 of 14 Supabase advisor-flagged unused indexes (idx_scan=0) left… | none | never | [:4532](open_issues.md#L4532) |
| OI-239 | Acknowledging an alert re-arms its dedup window instead of waiting out the… | none | never | [:4539](open_issues.md#L4539) |
| OI-240 | _getNextRankFromLadder's remaining/binding_constraint is inaccurate for 3… | none — bounded work, but a genuinely… | 2026-09-22 — every claim below re-read… | [:4566](open_issues.md#L4566) |
| OI-241 | Cross-worktree concurrency: no lock prevents multiple sessions running… | none | never | [:4641](open_issues.md#L4641) |
| OI-244 | Confirm-link tap left auth.one_time_tokens unconsumed — unexplained low… | (1) Vercel deploy authorization for BOTH… | 2026-09-23 — reproduced live on 2 real… | [:4668](open_issues.md#L4668) |
| OI-247 | db_maintenance_nightly (jobid 41) fails every run: VACUUM cannot run… | the first nightly run after the fix… | 2026-09-26 — FIX APPLIED: migration 144… | [:4786](open_issues.md#L4786) |
| OI-248 | client_errors_spike trips on one device's offline telemetry-queue replay… | none — scheduled: batch B. | 2026-09-26 — LIVE: the spike rows came… | [:4796](open_issues.md#L4796) |
| OI-249 | 45 s restore-op timeouts on tiny tables on builds +45 to +47 | none — P2, unscheduled. | 2026-09-26 — LIVE client telemetry:… | [:4805](open_issues.md#L4805) |
| OI-250 | pg_cron self/correlated silence has no out-of-band watcher (146 cannot see… | none | never | [:4814](open_issues.md#L4814) |
| OI-251 | Retention/vacuum effect is unobserved: return_message '1 row' hides DELETE… | none | never | [:4836](open_issues.md#L4836) |
| OI-252 | Workout templates: one stable identity (delete/rename propagation, unit… | founder on-device verification only.… | 2026-09-28 (superseding the 2026-09-27… | [:4857](open_issues.md#L4857) |
| OI-253 | PendingTemplateDeletes queued delete lost on logout/offline sign-out… | a durable, cross-session delete queue… | never | [:4885](open_issues.md#L4885) |
| OI-256 | Profile field-level conflict resolution: per-field merge instead of… | none | never | [:4906](open_issues.md#L4906) |
| OI-257 | Onboarding diet_preference default 'veg' doesn't match Edit Profile's chip… | a product decision — change onboarding's… | `lib/features/onboarding/screens/plan_sc… | [:4937](open_issues.md#L4937) |
| OI-259 | check_plan_review_record_exists.dart cannot parse hand-authored… | none (false-positive class, not a… | 2026-09-28 — confirmed live on GitHub… | [:4947](open_issues.md#L4947) |
| OI-260 | 4 sibling reportGeminiExhaustion-wiring tests… | none — fixable any time by whoever's own… | never | [:5075](open_issues.md#L5075) |
| OI-261 | displaced_<date> swap backups are local-only: never in plan_json or any… | none | 2026-09-28 — `git grep displaced --… | [:5014](open_issues.md#L5014) |
| OI-262 | check_sot_registry_parity only checks N-M line_ranges: bare :NNNN… | none | 2026-09-28 — measured against the gate's… | [:5041](open_issues.md#L5041) |
| OI-264 | docs/sot_registry.yaml is not valid YAML (35 parse errors); every gate… | none | 2026-09-28 — PyYAML safe_load, iterated… | [:5095](open_issues.md#L5095) |
| OI-265 | Boot-time healer needed for pre-existing exlog rows corrupted by the… | none — needs its own writer/reader-chain… | never | [:5126](open_issues.md#L5126) |
| OI-266 | _resolveLoggingType never consults customBox/user_custom_exercises for a… | none — fixable any time by whoever's own… | never | [:5153](open_issues.md#L5153) |
| OI-267 | weeklyReportDataProvider has no write-time invalidation across… | none — fixable any time; needs a… | never | [:5181](open_issues.md#L5181) |
| OI-268 | contract_sweep sets TZ=Asia/Kolkata for its flutter child; on Windows the… | none | 2026-09-29 — same test, TZ unset PASS vs… | [:5225](open_issues.md#L5225) |
| OI-269 | workout_log_exercises readers don't filter deleted_at (weekly-recalc +… | none | never | [:5258](open_issues.md#L5258) |
| OI-270 | PendingTemplateDeletes shares PendingExlogDeletes' fixed const-list… | none | never | [:5306](open_issues.md#L5306) |
| OI-271 | Edit Profile: emptying the Body fat % box does not clear the stored value… | none — nothing external; founder… | 2026-09-29 — read… | [:5330](open_issues.md#L5330) |
| OI-272 | Reconcile live prod migrations against the applied-migrations ledger… | none | 2026-09-29 — data below re-derived by… | [:5358](open_issues.md#L5358) |
| OI-273 | Branch sweep for merged branches that never had a worktree here… | none — this unit's exclusion from its… | 2026-09-29 — every constraint below was… | [:5396](open_issues.md#L5396) |
| OI-274 | Vercel Flutter SDK re-clone on every build wastes ~1/3 of build time (no… | none — fixable any time; needs… | 2026-09-30 — confirmed live via Vercel's… | [:5416](open_issues.md#L5416) |
| OI-276 | Chat video analysis feature: nothing in the client uploads video (no… | founder prioritisation… | 2026-10-01 — `grep -rn pickVideo lib/`… | [:5461](open_issues.md#L5461) |
| OI-277 | Free-tier chat cost exposure after the Gemini 3.1 Flash-Lite move:… | no real PRO/volume data yet — PRO only… | 2026-10-01 — inputs: measured avg chat… | [:5472](open_issues.md#L5472) |
| OI-278 | Telegram bot chat cap parity: bot is disabled; when re-enabled its cap… | the Telegram bot (separate OpenClaw VPS… | 2026-10-01 —… | [:5483](open_issues.md#L5483) |
| OI-279 | Phase 1b: pull-on-resume - a backgrounded device refreshes itself (7-day… | Phase 1 (e5b2a9) merged to `main`; needs… | 2026-10-02 - read on the branch: the… | [:5494](open_issues.md#L5494) |
| OI-280 | Phase 2 multi-device delta sync: updated_at+deleted_at on every synced… | Phase 1b (OI-279) merged; needs the… | 2026-10-02 - read… | [:5515](open_issues.md#L5515) |
| OI-281 | Meal deletes never reach the cloud: NutritionWriteService.deleteLog is… | needs a cloud tombstone (`deleted_at`)… | 2026-10-02 - code read, NOT reproduced… | [:5530](open_issues.md#L5530) |
| OI-283 | Live-DB SQL harness runners (check_onconflict_live_arbiter,… | founder decision: provision a CI secret… | 2026-10-02: both runners work by hand… | [:5541](open_issues.md#L5541) |
| OI-284 | Completed day-swap row keeps its pre-swap title after a cross-device… | the founder's on-device check (an APK… | 2026-10-03 - live rows (user d7a67a37):… | [:5550](open_issues.md#L5550) |
| OI-285 | mergeScheduleBundleIntoHive decides snapshot winners once before the loop… | its own plan + review; touches the… | 2026-10-03 - code read:… | [:5557](open_issues.md#L5557) |
| OI-286 | Replaced-swap notice: a device whose local swap loses to a newer… | OI-285 (the notice needs the per-week… | 2026-10-03 - code read: L3… | [:5564](open_issues.md#L5564) |
| OI-287 | Day-swap allowance is per-device: a swap on web leaves the phone showing… | founder go on the read path:… | 2026-10-03 - live: phone daily snapshot… | [:5571](open_issues.md#L5571) |
| OI-288 | Discipline: accepted-residual wording in tests pinned a defect as correct… | its own L-tier branch (root CLAUDE.md +… | 2026-10-03 -… | [:5578](open_issues.md#L5578) |
| OI-289 | Nutrition cross-device probe: verify meal add/edit/delete converge… | the founder running the two-device walk… | never - asked by the founder 2026-10-01… | [:5585](open_issues.md#L5585) |
| OI-290 | DaySwapRules leaves week_number unclassified (travels as content); hygiene… | founder call - close as no-symptom… | 2026-10-03 - `day_swap_rules.dart:17-28`… | [:5592](open_issues.md#L5592) |
| OI-292 | morning-alert push names a workout from YESTERDAY's snapshot: the 02:00… | a design decision on the date-correct… | 2026-10-03 -… | [:5599](open_issues.md#L5599) |
| OI-293 | Restore outcomes are unobservable on a release Android device:… | its own plan: the outcome must… | 2026-10-03 -… | [:5606](open_issues.md#L5606) |
| OI-294 | A cold-start restore that never returns (killed or hung mid-restore)… | its own plan (split out of… | 2026-10-04 - code read, NOT reproduced… | [:5613](open_issues.md#L5613) |
| OI-295 | Schedule writers that pass no WidgetRef (deload_evaluator lift via… | an audit of every ref-less schedule… | 2026-10-03 - code read, not reproduced:… | [:5620](open_issues.md#L5620) |
| OI-296 | Coach progress tools read long windows unpaginated: getProgressSummary's… | founder-owned checks only. The code… | 2026-10-03 by source read + live SQL:… | [:5809](open_issues.md#L5809) |
| OI-297 | Body measurements have no input UI, no history view and no cadence prompt:… | none (L2a, the merge-safe push and one… | 2026-10-03:… | [:5818](open_issues.md#L5818) |
| OI-298 | No effort capture (RIR/RPE): workout_logs.rpe is never written (0 rows… | founder — DECIDED 2026-10-06: left out… | 2026-10-03:… | [:5829](open_issues.md#L5829) |
| OI-299 | No computed athlete-state digest: the coach has no deterministic… | OI-296 (landing L1); landing L3 of the… | 2026-10-03: the coach assembles history… | [:5838](open_issues.md#L5838) |
| OI-300 | Progress Review: a grounded, coach-generated multi-month review (new… | OI-299 (same landing, L3) of the… | 2026-10-03: the only multi-period report… | [:5848](open_issues.md#L5848) |
| OI-301 | No gate stops a stray file at the repo root: existsSync (14 bytes of junk)… | its own plan + review (a new… | 2026-10-03 - `git ls-files` at the repo… | [:5627](open_issues.md#L5627) |
| OI-302 | Restore keeps the OLDEST cloud workout_logs row for a date completed twice… | a decision: pick the NEWEST row per date… | 2026-10-04 - code read:… | [:5635](open_issues.md#L5635) |
| OI-303 | Delete the disable_completed_title_heal kill switch and its closed-path… | the founder's on-device check of OI-284… | 2026-10-04 - code read: the kill switch… | [:5642](open_issues.md#L5642) |
| OI-304 | InsightCard and DeepAnalysisCard are never mounted: PatternDetector's… | founder decision D2 (L2b plan v3.1,… | 2026-10-04 by grep at `4fef03a7`:… | [:5857](open_issues.md#L5857) |
| OI-305 | Date-of-birth floor is inconsistent (onboarding allows age 10, Edit… | founder — DECIDED 2026-10-06: keep the… | 2026-10-04: `identity_screen.dart:82`… | [:5866](open_issues.md#L5866) |
| OI-306 | primary_goal_updated_at has zero writers and goal_changed_at is Hive-only… | none | 2026-10-04: `goal_changed_at` is written… | [:5877](open_issues.md#L5877) |
| OI-307 | workout_log_exercises keeps a second LIVE summary row when a log's set… | founder-owned checks only. All three… | 2026-10-04. Writer:… | [:5886](open_issues.md#L5886) |
| OI-308 | getExerciseHistory computes total_volume_kg = weight x reps x sets… | founder-owned check only. Fixed in L1b… | 2026-10-04: `getExerciseHistory.ts:88`… | [:5895](open_issues.md#L5895) |
| OI-309 | Merge-conflict treadmill: every >=account PR conflicts with main again and… | a plan (it changes hooks and the… | 2026-10-05 - measured on PR #73… | [:5663](open_issues.md#L5663) |
| OI-310 | App links (sign-up, welcome, Profile) open the icanbefitter.com blog… | the code half only — the policy was… | 2026-10-06. The app opens… | [:5904](open_issues.md#L5904) |
| OI-311 | A spawned `dart run` exited 254 in CI with no stderr in the log (run… | none for diagnosis - the second and… | 2026-10-06 - read from… | [:5673](open_issues.md#L5673) |
| OI-312 | Exercise-log deletes never reach the cloud: migration 151's BEFORE INSERT… | founder-owned device check. Fixed… | 2026-10-06, live, inside a DO block that… | [:5914](open_issues.md#L5914) |
| OI-313 | Installed-APK residuals of L1a: APKs without the L1a-2 client fixes keep… | upstream — no minimum-version /… | 2026-10-06 — writers:… | [:5923](open_issues.md#L5923) |
| OI-315 | ProgressPhotoRepository.cleanupOrphanedStorage has zero callers, and the… | a plan: a server-side per-day cap is a… | 2026-10-06 - `git grep -n… | [:5688](open_issues.md#L5688) |
| OI-316 | The progress-photos bucket and its SELECT/DELETE/INSERT policies have no… | a plan for a recurring catalog check (a… | 2026-10-06 - the B1 live evidence (E10)… | [:5697](open_issues.md#L5697) |
| OI-318 | A 127 s cold-start restore on 2026-10-06 (per-op 9-41 s, two 45 s… | a recurrence: a restore over 60 s on any… | 2026-10-06 - `client_errors` for the… | [:5649](open_issues.md#L5649) |
| OI-319 | current_streak_weeks is a lifetime counter that never resets when the… | a founder product decision (not… | 2026-10-06 - code read: no code path… | [:5656](open_issues.md#L5656) |
| OI-323 | weekly-report has no server-side per-day cap for PRO: consume_quota runs… | a FOUNDER product decision: cap PRO… | 2026-10-08 - read… | [:5706](open_issues.md#L5706) |
| OI-324 | SupabaseService.callFunction has no timeout of its own… | none - an engineering choice (a default… | 2026-10-08 - read… | [:5715](open_issues.md#L5715) |
| OI-325 | Profile weekly-report card still says 'Weekly AI Report'… | a FOUNDER copy decision: the one name… | 2026-10-08 - `grep -rn "Weekly AI… | [:5724](open_issues.md#L5724) |
| OI-326 | Restore-after-sign-in cost with the paged Edge Function (v10) is… | the founder: one sign-out/in on the… | 2026-10-09 - read the closure ledger… | [:5733](open_issues.md#L5733) |
| OI-327 | Weekly streak never resets when the daily streak breaks:… | a founder product decision: should a… | 2026-10-09 - read… | [:5741](open_issues.md#L5741) |
| OI-328 | One-off production credit of the 2026-09-14 week for user d7a67a37… | an explicit founder go: it is a live… | 2026-10-09 - read the plan… | [:5749](open_issues.md#L5749) |
| OI-329 | water_logs still takes about 54 updates per day after the sync-load batch… | none, fixable now; start by reading… | 2026-10-09 - live `pg_stat_user_tables`… | [:5758](open_issues.md#L5758) |
| OI-330 | workout_log_exercises updates rose from about 5 to about 62 per day across… | none, but it needs a diagnosis first… | 2026-10-09 - live `pg_stat_user_tables`… | [:5774](open_issues.md#L5774) |
| OI-331 | No detector for leftover background processes: a helper agent's unbounded… | none | 2026-10-09 - found live: two bash… | [:5785](open_issues.md#L5785) |
| OI-332 | weight_logs and sleep_logs pushes send explicit nulls for notes, quality,… | none today; becomes a defect the day any… | 2026-10-11 - live read-only counts on… | [:5796](open_issues.md#L5796) |
| OI-333 | daily-snapshot/index_test.ts leaks DISABLE_GEMINI_FAILURE_ALERT into the… | none | 2026-10-11 -… | [:5932](open_issues.md#L5932) |
| OI-334 | deploy_via_api.js rollback gaps: the pre-deploy cloud snapshot writes 0… | none - an engineering choice (see the… | 2026-10-11 - two measurements during the… | [:5943](open_issues.md#L5943) |
| OI-335 | Gate 50 (check_reader_manifest_complete) never evaluates a SoT concept… | none for the registry wording; making… | 2026-10-11 by reading:… | [:5956](open_issues.md#L5956) |
| OI-336 | Referral reward UX: the referrer's counts surface (friends joined /… | the founder: (1) the commit/merge go for… | 2026-10-12 - by reading the repo:… | [:5967](open_issues.md#L5967) |
| OI-337 | The commit-time gates read staged paths with a plain git diff --cached… | none - an engineering choice; a… | 2026-10-12 - by reading and by… | [:5980](open_issues.md#L5980) |
| OI-338 | delete_account_purges_all_user_buckets_test.dart reads USER_OWNED_BUCKETS… | none - a test-only edit… | 2026-10-12 - by reading… | [:5993](open_issues.md#L5993) |
| OI-339 | A Razorpay refund made only in the dashboard is invisible to the referral… | the founder's decision on how refunds… | 2026-10-13 - by reading.… | [:6009](open_issues.md#L6009) |
| OI-340 | A chargeback or UPI dispute after the referral reward vested has no… | the founder's decision: accept the loss,… | 2026-10-13 - by reading.… | [:6022](open_issues.md#L6022) |
| OI-341 | A friend on the 7-day referral trial cannot buy: create-razorpay-order… | Piece A: nothing (live, switch unset;… | 2026-10-13 - by reading.… | [:6035](open_issues.md#L6035) |
| OI-343 | Referral abuse by throwaway accounts: email confirmation is on but… | the founder's decision: accept the… | 2026-10-13 - by reading the live auth… | [:6050](open_issues.md#L6050) |
| OI-345 | Remove the enable_body_measurements OFF path (flag checks, kill switch,… | founder-owned check of the RELEASE build… | 2026-10-16:… | [:6063](open_issues.md#L6063) |
| OI-346 | Existing accounts accepted the v1 (blog) policy; nothing asks them to… | store launch (upstream_blocked;… | 2026-10-16: `AppConstants.termsVersion`… | [:6072](open_issues.md#L6072) |
| OI-347 | Free-access codes: the founder wants to give out codes that grant PRO for… | none (a plan is the next step; the… | 2026-10-16 - by reading… | [:6081](open_issues.md#L6081) |
| OI-348 | Post-build check list: every founder-owned device, signed-in and… | the final AAB/APK build… | 2026-10-17 - by reading every… | [:6094](open_issues.md#L6094) |
| OI-349 | Onboarding welcome screen overflows at 2x system text on a 640-dp phone:… | the founder's call on whether 2x system… | 2026-10-17 - by running the screen under… | [:6145](open_issues.md#L6145) |
| OI-350 | verify-payment captures an authorized payment and echoes its Razorpay… | none | 2026-10-17 - by reading… | [:6154](open_issues.md#L6154) |
| OI-351 | razorpay-webhook: after a payment.authorized auto-capture, a failed insert… | none | 2026-10-17 - by reading… | [:6161](open_issues.md#L6161) |
| OI-352 | Active Workout meta line prints hard-coded '0kg' for every scheduled lift | none (pick up after the… | 2026-10-18 - by code read only, NOT on… | [:6169](open_issues.md#L6169) |
| OI-353 | Plan suggested_weight (ProgressionResolver) is never read by the Active… | none (pick up after the… | 2026-10-18 - by code read: the plan… | [:6182](open_issues.md#L6182) |
| OI-354 | Active Workout hero tile + full-screen viewer (animated WEBP) blocked on… | the animated-WEBP asset pipeline and its… | 2026-10-18 - design locked in… | [:6195](open_issues.md#L6195) |
| OI-355 | Active Workout _persistActiveState reads the build-time widget.data, so… | none (pick up after the… | 2026-10-18 - by code read (plan review… | [:6206](open_issues.md#L6206) |
| OI-357 | Active Workout U2: per-set last values, new-user weight mirror, faded… | the flip batch landing (branch… | never | [:6219](open_issues.md#L6219) |
| OI-358 | Active Workout: adding an exercise already in the session crashes the… | none | never | [:6232](open_issues.md#L6232) |
| OI-359 | verify-payment calls Razorpay capture before the payment-owner check… | none | 2026-10-20 - by code read (hermes pass… | [:6241](open_issues.md#L6241) |
| OI-360 | verify-payment and razorpay-webhook log whole PostgREST error objects and… | none | 2026-10-20 - by code read (hermes pass… | [:6250](open_issues.md#L6250) |
| OI-362 | Active Workout: remove the per-set (OFF) path and the… | OI-348 row A12 (the release-build device… | never | [:6259](open_issues.md#L6259) |
| OI-363 | Active Workout: the FINISH/CANCEL button row overflows sideways at 320 dp… | none | never | [:6270](open_issues.md#L6270) |
| OI-364 | Remove the disable_lapse_gap_policy kill switch (client Hive key + server… | founder device check of the PRO gap… | 2026-10-21 - by code read: only READERS… | [:6285](open_issues.md#L6285) |
| OI-365 | Coach tools and app features do the same jobs through separate code (first… | none (founder 2026-10-21: this audit is… | 2026-10-21 - by code read at… | [:6296](open_issues.md#L6296) |
| OI-366 | create-razorpay-order has no rate limit and honours expired or exhausted… | none for the code; the founder's call on… | 2026-10-21 - by reading (hermes pass… | [:6330](open_issues.md#L6330) |
| OI-367 | Referral reward can be farmed once the purchase door is open: no minimum… | the founder's product call before store… | 2026-10-21 - by reading (hermes pass… | [:6339](open_issues.md#L6339) |
| OI-368 | Coach chat: the coach replies 'Roger. Logged.' when nothing was logged (no… | the `ai-proxy` + `ai-media-proxy` deploy… | never | [:6348](open_issues.md#L6348) |
| OI-369 | Coach chat: the coach says 'Logged' while the LOG SET card still waits for… | the `ai-proxy` + `ai-media-proxy` deploy… | never | [:6363](open_issues.md#L6363) |
| OI-372 | Weekday exercise swap has no UI: the engine takes any date, but only the… | none | 2026-10-21 (code read on… | [:6376](open_issues.md#L6376) |
| OI-373 | Coach: one workout request can produce either a typed logSet card (APPLY)… | none | never | [:6407](open_issues.md#L6407) |
| OI-374 | Coach: remove the DISABLE_WRITE_CLAIM_RULE kill switch once the… | the `coach-log-truth` batch shipping and… | never | [:6418](open_issues.md#L6418) |
| OI-375 | Coach: the FC2 queued acknowledgement hard-codes 'Recruit' instead of the… | none | never | [:6429](open_issues.md#L6429) |
| OI-376 | Workout invalidation: WorkoutWriteService.onInvalidate is a dead hook and… | none | never | [:6440](open_issues.md#L6440) |
| OI-377 | Train: WorkoutRepository.getExerciseLogsForDate duplicates the canonical… | none | never | [:6451](open_issues.md#L6451) |
| OI-378 | Riverpod 3.2.1: debug assertion actualPausedCount == expectedPausedCount… | upstream: riverpod above 3.2.1… | never | [:6462](open_issues.md#L6462) |
| OI-379 | Coach-logged workouts never add to total_workouts_done or run the rank… | none | never | [:6473](open_issues.md#L6473) |
| OI-380 | Train: the expanded day row shows 'N sets 0 reps X kg' for distance-type… | none | never | [:6484](open_issues.md#L6484) |
| OI-381 | Set counts read '1 sets' in the remaining renderers (prescriptions,… | none | never | [:6495](open_issues.md#L6495) |
| OI-382 | WorkoutWriteService.logExercise accepts a negative durationSec (only… | none | never | [:6506](open_issues.md#L6506) |
| OI-383 | Razorpay Android SDK is pinned (checkout 1.6.41, standard-core 1.7.19) and… | none | 2026-10-21 (Maven Central: checkout… | [:6519](open_issues.md#L6519) |
| OI-385 | Generator: 27 library rows in slot patterns are unreachable on attempts… | Batch B generator rework (spec… | 2026-10-22 — measured from… | [:6542](open_issues.md#L6542) |
| OI-386 | Generator: 11 of 13 attempt-1 sub-focus strings match 0 rows (slot… | Batch B generator rework (spec… | 2026-10-22 — measured from… | [:6553](open_issues.md#L6553) |
| OI-387 | Library: 6 kept bodyweight rows (E272 E273 E276 E277 E289 E290) invisible… | Batch B generator rework (spec… | 2026-10-22 — measured from… | [:6564](open_issues.md#L6564) |
| OI-388 | Generator: gym plans serve bodyweight-only self-resisted curls and triceps… | Batch B generator rework (spec… | 2026-10-22 — counted from the… | [:6577](open_issues.md#L6577) |
