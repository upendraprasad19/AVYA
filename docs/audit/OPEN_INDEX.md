# Open Issues — index (auto-generated)

**167 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

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
| OI-149 | breathing_cue holds a bare number on 136 of 292 rows; the original text is… | the founder** — 136 replacement cues… | 2026-08-29 — counted, and the recovery… | [:2474](open_issues.md#L2474) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2506](open_issues.md#L2506) |
| OI-154 | a cleared profile field silently reverts on the next sign-in (P3, was P1) | FOUNDER — product choice (below).… | 2026-09-29 — re-traced against `main` @… | [:2548](open_issues.md#L2548) |
| OI-156 | CLAUDE.md numeric claims drift because nothing re-derives them (P2) | nothing — mechanical | 2026-09-03 — each count re-measured | [:2608](open_issues.md#L2608) |
| OI-157 | no SAST and no SCA run anywhere in CI (P1) | founder call on Semgrep scope | 2026-09-03 — grep, 0 hits | [:2633](open_issues.md#L2633) |
| OI-158 | tests and gates that cannot fail (P2) | TEST-1 needs one device run to establish… | 2026-09-03 — source-verified | [:2653](open_issues.md#L2653) |
| OI-159 | sync and Edge Function correctness residue (P2) | nothing — but see OI-154 for the ARCH-1… | 2026-09-03 — source-verified | [:2676](open_issues.md#L2676) |
| OI-160 | dependency + build-toolchain hygiene (P2) | DEP-7 needs a founder unpin decision | 2026-09-03 — versions read from files | [:2696](open_issues.md#L2696) |
| OI-161 | two blind spots in our own observability and discipline gates (P3) | INFRA-13 is platform-tier, needs its own… | 2026-09-03 — live query + grep | [:2719](open_issues.md#L2719) |
| OI-163 | the four-tag migration header has NO gate, and two places claimed it did… | nothing — needs a gate written,… | 2026-09-05 — repo-wide grep + the live… | [:2761](open_issues.md#L2761) |
| OI-164 | the shared QA account caps CI at ~3 runs per IST day (P2) | a founder decision on test-account… | 2026-09-05 — live `usage_counters` + the… | [:2785](open_issues.md#L2785) |
| OI-166 | regeneration RESTARTS the periodization wave instead of continuing it, so… | OI-175 (the window-alignment half —… | 2026-09-06 — every citation below… | [:2807](open_issues.md#L2807) |
| OI-167 | the debugging skill's bug-class numbers collide 9×, every one is cited by… | nothing technical — needs a per-citation… | 2026-09-07 — `grep -oE '^### 2\.[0-9]+'… | [:2914](open_issues.md#L2914) |
| OI-169 | a local run of `test/edge_functions/` reports "All tests passed" having… | nothing — needs a decision on which… | 2026-09-07 — `flutter test… | [:2965](open_issues.md#L2965) |
| OI-173 | no cold-start weight estimate: a brand-new user, every free user, and any… | none — founder approved 2026-09-06 as… | 2026-09-06 — `plan_generator.dart:234`… | [:2854](open_issues.md#L2854) |
| OI-174 | schedule rows written past `plan_end` are never pruned, and they delay the… | none — NARROWED 2026-09-13 by OI-189… | 2026-09-13 — re-derived while closing… | [:2872](open_issues.md#L2872) |
| OI-175 | a regeneration past the phase's 4th week (`rawWeek > 4`) has no… | FOUNDER — what a regeneration should DO… | 2026-09-06 — `getCurrentWeekNumber()`… | [:2897](open_issues.md#L2897) |
| OI-177 | the live-cron snapshot that gives Gate 31 its only fileless-migration… | none | 2026-09-10 —… | [:2982](open_issues.md#L2982) |
| OI-179 | `alert_cron_function_dead` cannot fire across 100% of its range, and never… | none — one-line predicate fix; the value… | 2026-09-26 — the R2-11 PRECONDITION is… | [:2995](open_issues.md#L2995) |
| OI-180 | `check_sot_registry_parity` silently skips every single-number… | none | 2026-09-10 —… | [:3028](open_issues.md#L3028) |
| OI-184 | 4 tables rely on RLS-zero-policy default-deny alone; the raw grants under… | none — mechanically straightforward (a… | 2026-09-11 — LIVE, via the Management… | [:3041](open_issues.md#L3041) |
| OI-185 | `check_schema_column_refs.dart` validates only the FIRST line of a… | none — carried out of OI-162 (closed… | 2026-09-03 — by the audit (a prototype… | [:3115](open_issues.md#L3115) |
| OI-186 | the AI coach cannot replace ONE day with a different workout: the only… | founder product decision on tier (see… | 2026-09-10 — full census of… | [:3141](open_issues.md#L3141) |
| OI-187 | the AI coach has no read path to the 292-exercise library: the WRITE path… | nothing technical — needs a design… | 2026-09-10 — every claim below re-read… | [:3182](open_issues.md#L3182) |
| OI-188 | no re-entry path for a returning user: the free path hands them a DELOAD… | founder product decision on the… | 2026-09-10 — app behaviour read from… | [:3229](open_issues.md#L3229) |
| OI-190 | Unit 1's §4.11 gate `check_single_schedule_row_builder.dart` is WARN-only… | none — needs a plan. Input is already… | 2026-09-12 — `dart run… | [:3285](open_issues.md#L3285) |
| OI-191 | target_weight_kg can contradict the chosen goal's direction, making the… | none — bounded, no… | 2026-09-13 — reproduced live on the… | [:3299](open_issues.md#L3299) |
| OI-192 | the orphan-sync dedupe can never match a photo turn: client writes… | none — pick ONE placeholder shape (or… | 2026-09-13 — source only:… | [:3358](open_issues.md#L3358) |
| OI-193 | Gate 31 treats a COMMENTED `cron.unschedule('X')` as a real unschedule, so… | none — strip `--` comments before the… | 2026-09-12 —… | [:3368](open_issues.md#L3368) |
| OI-194 | `compute_admin_metrics_daily` (jobid 30) skipped its 2026-09-11 18:15Z… | none for the code (repair (d) below is a… | 2026-09-12 — `select function_name,… | [:3379](open_issues.md#L3379) |
| OI-196 | `morning-alert`'s Telegram sender logs the raw fetch error, whose message… | none — one-line change in one function;… | 2026-09-13 — read… | [:3410](open_issues.md#L3410) |
| OI-197 | Founder observability gaps: payment-flow alerting dormant, EF auth-outage… | none — no schema/migration/payment/auth… | never — this is a gap analysis surfaced… | [:3422](open_issues.md#L3422) |
| OI-199 | cleanup_cron_call_log() spares only TWO global rows, not each function's… | none | 2026-09-14, live read of the function… | [:3468](open_issues.md#L3468) |
| OI-200 | founder_metrics_ops().client_errors_today counts benign event-coded… | none | 2026-09-14, B-pass on migration 135… | [:3533](open_issues.md#L3533) |
| OI-201 | alert_cron_function_dead can burst-dispatch many critical alerts at once;… | none | 2026-09-14, Hermes lens L31… | [:3571](open_issues.md#L3571) |
| OI-205 | Already-authenticated user opening a valid /reset link is silently… | none | 2026-09-16, B-pass on the… | [:3613](open_issues.md#L3613) |
| OI-207 | sot_registry.yaml: hold-weeks line_range citations (762-847, 890-915)… | none | 2026-09-26 — real cause is NOT an… | [:3684](open_issues.md#L3684) |
| OI-208 | AuthNotifier._teardown() swallows internal failures with no signal to… | none | 2026-09-16, B-pass on the… | [:3731](open_issues.md#L3731) |
| OI-210 | future-prediction Edge Function has no live caller anywhere in the shipped… | founder decision (see below — surfaced… | 2026-09-16, B-pass on the… | [:3764](open_issues.md#L3764) |
| OI-211 | Custom exercise equipment field + [] to ['none'] backfill of existing rows… | founder batch scheduling | never | [:3817](open_issues.md#L3817) |
| OI-212 | Custom foods unsearchable from the main food search bar (search never… | founder product decision (separate Your… | never | [:3825](open_issues.md#L3825) |
| OI-213 | Razorpay auto-renew subscriptions (web): mandates, subscription.charged… | founder product decision on timing… | 2026-09-17 — claims traced from the… | [:3833](open_issues.md#L3833) |
| OI-214 | Diet plan Option A: curated Indian meal-template layer (recipe-first… | none | never | [:3854](open_issues.md#L3854) |
| OI-215 | Device verification expansion: Patrol flows for the UI-bug cluster,… | none | never | [:3861](open_issues.md#L3861) |
| OI-216 | snapshot-contract gate: per-entry slack mechanism for shift-sensitive… | none | never | [:3879](open_issues.md#L3879) |
| OI-217 | telemetry v2: aggregate plan-review findings by class… | none | never | [:3894](open_issues.md#L3894) |
| OI-218 | Cloud exlog tombstone residual — moved-out-date rows never tombstoned,… | none | never | [:3953](open_issues.md#L3953) |
| OI-219 | is_pr not rescanned across moveExerciseLogs — collision merge can drop a… | none | never | [:3977](open_issues.md#L3977) |
| OI-220 | Contract-sweep gate: pre-push targeted SoT contract testing | one clean batch under `--warn-only`… | 2026-09-19 — shipped on `gate-integrity`… | [:3910](open_issues.md#L3910) |
| OI-221 | tool_dispatcher defensive date-parse fallbacks can clobber the wrong date… | none | never | [:3996](open_issues.md#L3996) |
| OI-222 | Document versionCode-bump-via-merge CI gap in CLAUDE.md §4.9 | none | never | [:4014](open_issues.md#L4014) |
| OI-227 | Telegram coach connect is broken (no linking token, bot says no user… | none — UI removal is self-contained; the… | 2026-09-21 — founder tapped "Connect… | [:4040](open_issues.md#L4040) |
| OI-228 | AI coach shortenWorkout tool calls get stuck at status:queued with no… | none — Bug A is CLOSED; Bug B's "stuck… | 2026-09-22 (Batch B) — live-traced the… | [:4115](open_issues.md#L4115) |
| OI-229 | AI coach chat replies violate captain_manual.ts hard rules: 100-word cap… | none — both are prompt-adherence gaps in… | 2026-09-21 — both cited… | [:4258](open_issues.md#L4258) |
| OI-231 | AI coach addressed a promoted user by their OLD rank term (Recruit instead… | none — live verification DONE (Batch B,… | 2026-09-22 (Batch B) — settled via the… | [:4370](open_issues.md#L4370) |
| OI-233 | user_daily_snapshots' 4 cron/client writers are not atomic against each… | none — scope and fix shape are already… | 2026-09-21 — explicitly scoped out in | [:4490](open_issues.md#L4490) |
| OI-236 | 12 of 14 Supabase advisor-flagged unused indexes (idx_scan=0) left… | none | never | [:4536](open_issues.md#L4536) |
| OI-237 | Extreme update:insert ratios on scheduled_workouts (34:1) and… | none | never | [:4543](open_issues.md#L4543) |
| OI-239 | Acknowledging an alert re-arms its dedup window instead of waiting out the… | none | never | [:4550](open_issues.md#L4550) |
| OI-240 | _getNextRankFromLadder's remaining/binding_constraint is inaccurate for 3… | none — bounded work, but a genuinely… | 2026-09-22 — every claim below re-read… | [:4577](open_issues.md#L4577) |
| OI-241 | Cross-worktree concurrency: no lock prevents multiple sessions running… | none | never | [:4652](open_issues.md#L4652) |
| OI-244 | Confirm-link tap left auth.one_time_tokens unconsumed — unexplained low… | (1) Vercel deploy authorization for BOTH… | 2026-09-23 — reproduced live on 2 real… | [:4679](open_issues.md#L4679) |
| OI-247 | db_maintenance_nightly (jobid 41) fails every run: VACUUM cannot run… | the first nightly run after the fix… | 2026-09-26 — FIX APPLIED: migration 144… | [:4797](open_issues.md#L4797) |
| OI-248 | client_errors_spike trips on one device's offline telemetry-queue replay… | none — scheduled: batch B. | 2026-09-26 — LIVE: the spike rows came… | [:4807](open_issues.md#L4807) |
| OI-249 | 45 s restore-op timeouts on tiny tables on builds +45 to +47 | none — P2, unscheduled. | 2026-09-26 — LIVE client telemetry:… | [:4816](open_issues.md#L4816) |
| OI-250 | pg_cron self/correlated silence has no out-of-band watcher (146 cannot see… | none | never | [:4825](open_issues.md#L4825) |
| OI-251 | Retention/vacuum effect is unobserved: return_message '1 row' hides DELETE… | none | never | [:4847](open_issues.md#L4847) |
| OI-252 | Workout templates: one stable identity (delete/rename propagation, unit… | founder on-device verification only.… | 2026-09-28 (superseding the 2026-09-27… | [:4868](open_issues.md#L4868) |
| OI-253 | PendingTemplateDeletes queued delete lost on logout/offline sign-out… | a durable, cross-session delete queue… | never | [:4896](open_issues.md#L4896) |
| OI-256 | Profile field-level conflict resolution: per-field merge instead of… | none | never | [:4917](open_issues.md#L4917) |
| OI-257 | Onboarding diet_preference default 'veg' doesn't match Edit Profile's chip… | a product decision — change onboarding's… | `lib/features/onboarding/screens/plan_sc… | [:4948](open_issues.md#L4948) |
| OI-259 | check_plan_review_record_exists.dart cannot parse hand-authored… | none (false-positive class, not a… | 2026-09-28 — confirmed live on GitHub… | [:4958](open_issues.md#L4958) |
| OI-260 | 4 sibling reportGeminiExhaustion-wiring tests… | none — fixable any time by whoever's own… | never | [:5086](open_issues.md#L5086) |
| OI-261 | displaced_<date> swap backups are local-only: never in plan_json or any… | none | 2026-09-28 — `git grep displaced --… | [:5025](open_issues.md#L5025) |
| OI-262 | check_sot_registry_parity only checks N-M line_ranges: bare :NNNN… | none | 2026-09-28 — measured against the gate's… | [:5052](open_issues.md#L5052) |
| OI-264 | docs/sot_registry.yaml is not valid YAML (35 parse errors); every gate… | none | 2026-09-28 — PyYAML safe_load, iterated… | [:5106](open_issues.md#L5106) |
| OI-265 | Boot-time healer needed for pre-existing exlog rows corrupted by the… | none — needs its own writer/reader-chain… | never | [:5137](open_issues.md#L5137) |
| OI-266 | _resolveLoggingType never consults customBox/user_custom_exercises for a… | none — fixable any time by whoever's own… | never | [:5164](open_issues.md#L5164) |
| OI-267 | weeklyReportDataProvider has no write-time invalidation across… | none — fixable any time; needs a… | never | [:5192](open_issues.md#L5192) |
| OI-268 | contract_sweep sets TZ=Asia/Kolkata for its flutter child; on Windows the… | none | 2026-09-29 — same test, TZ unset PASS vs… | [:5236](open_issues.md#L5236) |
| OI-269 | workout_log_exercises readers don't filter deleted_at (weekly-recalc +… | none | never | [:5269](open_issues.md#L5269) |
| OI-270 | PendingTemplateDeletes shares PendingExlogDeletes' fixed const-list… | none | never | [:5316](open_issues.md#L5316) |
| OI-271 | Edit Profile: emptying the Body fat % box does not clear the stored value… | none — nothing external; founder… | 2026-09-29 — read… | [:5340](open_issues.md#L5340) |
| OI-272 | Reconcile live prod migrations against the applied-migrations ledger… | none | 2026-09-29 — data below re-derived by… | [:5368](open_issues.md#L5368) |
| OI-273 | Branch sweep for merged branches that never had a worktree here… | none — this unit's exclusion from its… | 2026-09-29 — every constraint below was… | [:5406](open_issues.md#L5406) |
| OI-274 | Vercel Flutter SDK re-clone on every build wastes ~1/3 of build time (no… | none — fixable any time; needs… | 2026-09-30 — confirmed live via Vercel's… | [:5426](open_issues.md#L5426) |
| OI-275 | Cut release-cycle wall-clock: a version-only bump runs the full suite 3x… | none — founder directive 2026-10-01 is… | 2026-10-01 — timings below are from the… | [:5471](open_issues.md#L5471) |
| OI-276 | Chat video analysis feature: nothing in the client uploads video (no… | founder prioritisation… | 2026-10-01 — `grep -rn pickVideo lib/`… | [:5493](open_issues.md#L5493) |
| OI-277 | Free-tier chat cost exposure after the Gemini 3.1 Flash-Lite move:… | no real PRO/volume data yet — PRO only… | 2026-10-01 — inputs: measured avg chat… | [:5504](open_issues.md#L5504) |
| OI-278 | Telegram bot chat cap parity: bot is disabled; when re-enabled its cap… | the Telegram bot (separate OpenClaw VPS… | 2026-10-01 —… | [:5515](open_issues.md#L5515) |
| OI-279 | Phase 1b: pull-on-resume - a backgrounded device refreshes itself (7-day… | Phase 1 (e5b2a9) merged to `main`; needs… | 2026-10-02 - read on the branch: the… | [:5526](open_issues.md#L5526) |
| OI-280 | Phase 2 multi-device delta sync: updated_at+deleted_at on every synced… | Phase 1b (OI-279) merged; needs the… | 2026-10-02 - read… | [:5545](open_issues.md#L5545) |
| OI-281 | Meal deletes never reach the cloud: NutritionWriteService.deleteLog is… | needs a cloud tombstone (`deleted_at`)… | 2026-10-02 - code read, NOT reproduced… | [:5560](open_issues.md#L5560) |
| OI-283 | Live-DB SQL harness runners (check_onconflict_live_arbiter,… | founder decision: provision a CI secret… | 2026-10-02: both runners work by hand… | [:5571](open_issues.md#L5571) |
| OI-284 | Completed day-swap row keeps its pre-swap title after a cross-device… | its own plan + two context-blind review… | 2026-10-03 - live rows (user d7a67a37):… | [:5580](open_issues.md#L5580) |
| OI-285 | mergeScheduleBundleIntoHive decides snapshot winners once before the loop… | its own plan + review; touches the… | 2026-10-03 - code read:… | [:5587](open_issues.md#L5587) |
| OI-286 | Replaced-swap notice: a device whose local swap loses to a newer… | OI-285 (the notice needs the per-week… | 2026-10-03 - code read: L3… | [:5594](open_issues.md#L5594) |
| OI-287 | Day-swap allowance is per-device: a swap on web leaves the phone showing… | founder go on the read path:… | 2026-10-03 - live: phone daily snapshot… | [:5601](open_issues.md#L5601) |
| OI-288 | Discipline: accepted-residual wording in tests pinned a defect as correct… | its own L-tier branch (root CLAUDE.md +… | 2026-10-03 -… | [:5608](open_issues.md#L5608) |
| OI-289 | Nutrition cross-device probe: verify meal add/edit/delete converge… | the founder running the two-device walk… | never - asked by the founder 2026-10-01… | [:5615](open_issues.md#L5615) |
| OI-290 | DaySwapRules leaves week_number unclassified (travels as content); hygiene… | founder call - close as no-symptom… | 2026-10-03 - `day_swap_rules.dart:17-28`… | [:5622](open_issues.md#L5622) |
| OI-292 | morning-alert push names a workout from YESTERDAY's snapshot: the 02:00… | a design decision on the date-correct… | 2026-10-03 -… | [:5629](open_issues.md#L5629) |
| OI-293 | Restore outcomes are unobservable on a release Android device:… | its own plan: the outcome must… | 2026-10-03 -… | [:5636](open_issues.md#L5636) |
| OI-294 | Launch-path restore never refreshes Home: checkAndSync ->… | its own plan: pick the signal (bump… | 2026-10-03 - code read, not reproduced… | [:5643](open_issues.md#L5643) |
| OI-295 | Schedule writers that pass no WidgetRef (deload_evaluator lift via… | an audit of every ref-less schedule… | 2026-10-03 - code read, not reproduced:… | [:5650](open_issues.md#L5650) |
| OI-301 | No gate stops a stray file at the repo root: existsSync (14 bytes of junk)… | its own plan + review (a new… | 2026-10-03 - `git ls-files` at the repo… | [:5657](open_issues.md#L5657) |
