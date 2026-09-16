# Open Issues — index (auto-generated)

**117 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 6 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below… | 2026-08-05 — flag inventory, dependency… | [:253](open_issues.md#L253) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:343](open_issues.md#L343) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:351](open_issues.md#L351) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — visibility read live (`gh… | [:360](open_issues.md#L360) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — every PR's… | [:391](open_issues.md#L391) |
| OI-58 | Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a) | none — but see the correction below; the… | never (for the residual below; the… | [:425](open_issues.md#L425) |
| OI-60 | Flip `enable_hold_weeks` | 3 remaining flip-on blockers** in… | 2026-08-20 — the blocker list re-derived… | [:499](open_issues.md#L499) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:582](open_issues.md#L582) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:590](open_issues.md#L590) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52,… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:599](open_issues.md#L599) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:607](open_issues.md#L607) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — BLOCKER ONLY (the founder… | [:616](open_issues.md#L616) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:636](open_issues.md#L636) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:648](open_issues.md#L648) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:665](open_issues.md#L665) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:697](open_issues.md#L697) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent… | [:716](open_issues.md#L716) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5,… | [:95](open_issues.md#L95) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9,… | [:146](open_issues.md#L146) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the… | [:176](open_issues.md#L176) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already… | 2026-08-05 (telemetry-readiness… | [:750](open_issues.md#L750) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and… | 2026-08-03 (twice in one day, both times… | [:798](open_issues.md#L798) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED… | 2026-08-05 — record confirmed present by… | [:842](open_issues.md#L842) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now… | 2026-08-10 (`wc -l` = **800** on `main`… | [:898](open_issues.md#L898) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split… | 2026-08-04 (call-site counts below… | [:972](open_issues.md#L972) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and… | 2026-08-05 (found by measuring the… | [:1014](open_issues.md#L1014) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it… | 2026-08-05 — surfaced by the analyzer… | [:1074](open_issues.md#L1074) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT… | 2026-08-06 — found by the round-2… | [:1102](open_issues.md#L1102) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism… | 2026-08-07 — both definitions read… | [:1136](open_issues.md#L1136) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy… | 2026-08-07 — `_featureSubtitle`'s switch… | [:1189](open_issues.md#L1189) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own… | 2026-08-08 — B-pass on branch… | [:1389](open_issues.md#L1389) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is… | 2026-08-11 — round-2 context-blind… | [:1420](open_issues.md#L1420) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or… | 2026-08-11 — prior-art sweep + round-2… | [:1460](open_issues.md#L1460) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis,… | 2026-08-11 — round-2 review of… | [:1493](open_issues.md#L1493) |
| OI-104 | `check_hooks_installed.dart` detects hook PRESENCE, not staleness;… | nothing technical. | 2026-08-11 — `.git/hooks/pre-commit` and… | [:1514](open_issues.md#L1514) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a… | never — this is OI-102's unanswered… | [:1555](open_issues.md#L1555) |
| OI-107 | `build-apk.md`'s two inline `gh run list` copies should move onto… | nothing technical. It is deliberately… | 2026-08-12 — both call sites read… | [:1584](open_issues.md#L1584) |
| OI-108 | `safe_commit.sh` silently accepts a git FLAG as the commit message (P2) | nothing. The fix is a few lines; it is… | 2026-08-12 — hit live while committing… | [:1615](open_issues.md#L1615) |
| OI-109 | ForgotPasswordSheet's two-step code flow has no test | nothing — bounded work | 2026-08-07 (`grep -rln… | [:1283](open_issues.md#L1283) |
| OI-110 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate… | 2026-08-08 (`dart run… | [:1307](open_issues.md#L1307) |
| OI-111 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a… | 2026-08-07 (grep below run against… | [:1254](open_issues.md#L1254) |
| OI-113 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`,… | [:1344](open_issues.md#L1344) |
| OI-114 | `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only… | nothing | 2026-08-10 (read the file; confirmed the… | [:1363](open_issues.md#L1363) |
| OI-117 | a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2) | nothing. | 2026-08-13 — observed live. The… | [:1668](open_issues.md#L1668) |
| OI-119 | `git_safety_hook.dart` matches command TEXT, so it blocks commands that… | nothing, but it needs a false-positive… | 2026-08-13. ⚠ **The two detectors are… | [:1721](open_issues.md#L1721) |
| OI-120 | the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of… | nothing; needs the same measurement… | 2026-08-13 — both numbers read directly,… | [:1692](open_issues.md#L1692) |
| OI-122 | `check_regression_catalog.dart` runs `flutter test` with no concurrency… | nothing technical. Needs a measurement… | 2026-08-13 — read directly at… | [:1646](open_issues.md#L1646) |
| OI-123 | the test-suite UPSERT path is guarded only transitively, by file ordering… | nothing — scoped and understood; needs… | 2026-08-15 — Hermes lens (destructive-op… | [:1782](open_issues.md#L1782) |
| OI-124 | the device delete-account test hard-deletes `auth.users` with NO… | nothing technical. It is currently… | 2026-08-15 — Hermes lens (destructive-op… | [:1813](open_issues.md#L1813) |
| OI-125 | Selectable past hold weeks (FOB-6) — 6 named lifecycle traps | none technically — but it is a NEW… | 2026-08-13 — filed from… | [:1837](open_issues.md#L1837) |
| OI-126 | The `logged` / `custom_template` training-day predicate split (5 call… | none. Pickable, but it is a live… | 2026-08-13 — the 5 call sites and the… | [:1864](open_issues.md#L1864) |
| OI-127 | `plan_start` moving under a live hold week: is the streak identity still… | none. Route to the piece that already… | 2026-08-13 — the four `plan_start` write… | [:1893](open_issues.md#L1893) |
| OI-130 | concurrent sessions have no way to see what another is working on, so the… | nothing technical, but the cheap fixes… | 2026-08-16 — three measured instances,… | [:1943](open_issues.md#L1943) |
| OI-131 | the golden tests are excluded from every gate on every platform, so they… | nothing technical — but it needs a… | 2026-08-20 — measured while fixing… | [:2000](open_issues.md#L2000) |
| OI-134 | mutation-proving runs in the shared worktree, where §4.13's guarantee does… | nothing. Small and self-contained. | 2026-08-20 — observed live, twice, by… | [:2041](open_issues.md#L2041) |
| OI-135 | 60 of 125 migration-ledger hashes do not match their files, and nothing… | nothing technical. The fix shape is… | 2026-08-20 — measured, not estimated.… | [:2082](open_issues.md#L2082) |
| OI-136 | Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files… | nothing technical. Needs the same… | 2026-08-20 — measured, not inferred.… | [:2120](open_issues.md#L2120) |
| OI-137 | the migration-ledger gate checks that `hash:` EXISTS, never that it is a… | nothing technical. Same… | 2026-08-20 — reproduced, not inferred.… | [:2163](open_issues.md#L2163) |
| OI-138 | `retire_worktree` removes the worktree but leaves the BRANCH, silently… | none. Small, but see the trap below — it… | 2026-08-25 — read… | [:2201](open_issues.md#L2201) |
| OI-139 | the only tool that DELETES developer work is tiered `feature`; every tool… | FOUNDER. This is a governance decision,… | 2026-08-25 — `grep -n retire_worktree… | [:2237](open_issues.md#L2237) |
| OI-140 | nothing detects a duplicate diagnose `bug_id`, though the identical… | none. | 2026-08-25 — `ls docs/diagnoses/*.md \|… | [:2275](open_issues.md#L2275) |
| OI-141 | retire the notification-preferences snapshot fallback once APK +39 is… | APK +39 adoption — a founder release… | 2026-08-26 — filed as the tracked half… | [:1215](open_issues.md#L1215) |
| OI-142 | deploy-artifact commits are unenforced: prod runs Edge Function code whose… | none. | 2026-08-27 — the class was LIVE in the… | [:2350](open_issues.md#L2350) |
| OI-143 | nothing checks whether a multi-task BATCH is finished; the Stop hook only… | nothing technical. Needs a design call… | 2026-08-28 — observed live, repeatedly,… | [:2310](open_issues.md#L2310) |
| OI-145 | 34 licence-clean drawings depict bodyweight exercises the library does not… | nothing technical. It needs the… | 2026-08-29 — the 302-entry manifest of… | [:2393](open_issues.md#L2393) |
| OI-146 | three duplicate exercise rows, two of them dead, one skewing selection… | nothing. Needs a decision on whether the… | 2026-08-29 — name-normalised (case,… | [:2433](open_issues.md#L2433) |
| OI-147 | remove Donkey Calf Raise: a one-row deletion that touches the cloud seed,… | nothing technical. Needs the… | 2026-08-29 — every claim below… | [:2489](open_issues.md#L2489) |
| OI-148 | 23 equipment-variant exercises the plate mapping surfaced, blocked on a… | the selection-skew question below. Not… | 2026-08-29 — each named row checked… | [:2551](open_issues.md#L2551) |
| OI-149 | breathing_cue holds a bare number on 136 of 292 rows; the original text is… | the founder** — 136 replacement cues… | 2026-08-29 — counted, and the recovery… | [:2581](open_issues.md#L2581) |
| OI-151 | telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and… | nothing technical. It is a PRE-LAUNCH… | 2026-08-30 — measured live on… | [:2613](open_issues.md#L2613) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2665](open_issues.md#L2665) |
| OI-154 | a cleared profile field silently reverts on the next sign-in (P1) | needs a design spec (tombstone +… | 2026-09-03 — source, full chain traced | [:2933](open_issues.md#L2933) |
| OI-155 | six gates are wired to no runner, and Gate 33 cannot detect it (P1) | re-enumerate the skip block mechanically | 2026-09-03 — greps with positive control | [:2956](open_issues.md#L2956) |
| OI-156 | CLAUDE.md numeric claims drift because nothing re-derives them (P2) | nothing — mechanical | 2026-09-03 — each count re-measured | [:2980](open_issues.md#L2980) |
| OI-157 | no SAST and no SCA run anywhere in CI (P1) | founder call on Semgrep scope | 2026-09-03 — grep, 0 hits | [:3005](open_issues.md#L3005) |
| OI-158 | tests and gates that cannot fail (P2) | TEST-1 needs one device run to establish… | 2026-09-03 — source-verified | [:3025](open_issues.md#L3025) |
| OI-159 | sync and Edge Function correctness residue (P2) | nothing — but see OI-154 for the ARCH-1… | 2026-09-03 — source-verified | [:3048](open_issues.md#L3048) |
| OI-160 | dependency + build-toolchain hygiene (P2) | DEP-7 needs a founder unpin decision | 2026-09-03 — versions read from files | [:3068](open_issues.md#L3068) |
| OI-161 | two blind spots in our own observability and discipline gates (P3) | INFRA-13 is platform-tier, needs its own… | 2026-09-03 — live query + grep | [:3091](open_issues.md#L3091) |
| OI-163 | the four-tag migration header has NO gate, and two places claimed it did… | nothing — needs a gate written,… | 2026-09-05 — repo-wide grep + the live… | [:3240](open_issues.md#L3240) |
| OI-164 | the shared QA account caps CI at ~3 runs per IST day (P2) | a founder decision on test-account… | 2026-09-05 — live `usage_counters` + the… | [:3264](open_issues.md#L3264) |
| OI-165 | `check_onconflict_live_arbiter.dart` 403s, so every `test/sql/` live… | identifying which token the runner needs… | 2026-09-05 — ran it; and the harness… | [:3286](open_issues.md#L3286) |
| OI-166 | regeneration RESTARTS the periodization wave instead of continuing it, so… | OI-175 (the window-alignment half —… | 2026-09-06 — every citation below… | [:3308](open_issues.md#L3308) |
| OI-167 | the debugging skill's bug-class numbers collide 9×, every one is cited by… | nothing technical — needs a per-citation… | 2026-09-07 — `grep -oE '^### 2\.[0-9]+'… | [:3427](open_issues.md#L3427) |
| OI-168 | nothing fires §4.9's "grep the test tree before you land" rule, so it is… | nothing technical — needs the gate… | 2026-09-07 — the pre-push full suite on… | [:3478](open_issues.md#L3478) |
| OI-169 | a local run of `test/edge_functions/` reports "All tests passed" having… | nothing — needs a decision on which… | 2026-09-07 — `flutter test… | [:3501](open_issues.md#L3501) |
| OI-173 | no cold-start weight estimate: a brand-new user, every free user, and any… | none — founder approved 2026-09-06 as… | 2026-09-06 — `plan_generator.dart:234`… | [:3355](open_issues.md#L3355) |
| OI-174 | schedule rows written past `plan_end` are never pruned, and they delay the… | none — NARROWED 2026-09-13 by OI-189… | 2026-09-13 — re-derived while closing… | [:3373](open_issues.md#L3373) |
| OI-175 | a regeneration past the phase's 4th week (`rawWeek > 4`) has no… | FOUNDER — what a regeneration should DO… | 2026-09-06 — `getCurrentWeekNumber()`… | [:3398](open_issues.md#L3398) |
| OI-177 | the live-cron snapshot that gives Gate 31 its only fileless-migration… | none | 2026-09-10 —… | [:3544](open_issues.md#L3544) |
| OI-178 | pg_cron SQL jobs are structurally invisible to the alerting stack:… | a design decision — telemetry bridge vs.… | 2026-09-10 — `cron_call_log` holds… | [:3557](open_issues.md#L3557) |
| OI-179 | `alert_cron_function_dead` cannot fire across 100% of its range, and never… | none — one-line predicate fix; the value… | 2026-09-10 — `min(started_at)` across… | [:3571](open_issues.md#L3571) |
| OI-180 | `check_sot_registry_parity` silently skips every single-number… | none | 2026-09-10 —… | [:3601](open_issues.md#L3601) |
| OI-181 | nothing catches a MISSING plan-review record at merge time; both prechecks… | none | 2026-09-10 — live, by causing it. Branch… | [:3612](open_issues.md#L3612) |
| OI-182 | the payment grace window closes before the last verify-payment retry fires… | none — needs a founder call on the… | 2026-09-11 — read both constants… | [:3628](open_issues.md#L3628) |
| OI-184 | 4 tables rely on RLS-zero-policy default-deny alone; the raw grants under… | none — mechanically straightforward (a… | 2026-09-11 — LIVE, via the Management… | [:3730](open_issues.md#L3730) |
| OI-185 | `check_schema_column_refs.dart` validates only the FIRST line of a… | none — carried out of OI-162 (closed… | 2026-09-03 — by the audit (a prototype… | [:3804](open_issues.md#L3804) |
| OI-186 | the AI coach cannot replace ONE day with a different workout: the only… | founder product decision on tier (see… | 2026-09-10 — full census of… | [:3830](open_issues.md#L3830) |
| OI-187 | the AI coach has no read path to the 292-exercise library: the WRITE path… | nothing technical — needs a design… | 2026-09-10 — every claim below re-read… | [:3871](open_issues.md#L3871) |
| OI-188 | no re-entry path for a returning user: the free path hands them a DELOAD… | founder product decision on the… | 2026-09-10 — app behaviour read from… | [:3918](open_issues.md#L3918) |
| OI-190 | Unit 1's §4.11 gate `check_single_schedule_row_builder.dart` is WARN-only… | none — needs a plan. Input is already… | 2026-09-12 — `dart run… | [:3985](open_issues.md#L3985) |
| OI-191 | target_weight_kg can contradict the chosen goal's direction, making the… | none — bounded, no… | 2026-09-13 — reproduced live on the… | [:3999](open_issues.md#L3999) |
| OI-192 | the orphan-sync dedupe can never match a photo turn: client writes… | none — pick ONE placeholder shape (or… | 2026-09-13 — source only:… | [:4058](open_issues.md#L4058) |
| OI-193 | Gate 31 treats a COMMENTED `cron.unschedule('X')` as a real unschedule, so… | none — strip `--` comments before the… | 2026-09-12 —… | [:4068](open_issues.md#L4068) |
| OI-194 | `compute_admin_metrics_daily` (jobid 30) skipped its 2026-09-11 18:15Z… | none for the code (repair (d) below is a… | 2026-09-12 — `select function_name,… | [:4079](open_issues.md#L4079) |
| OI-195 | Gate 42 accepts any non-empty `behavioral_test_path:` / `presence_only:`… | none — one `File(path).existsSync()` per… | 2026-09-13 — `grep -n… | [:4110](open_issues.md#L4110) |
| OI-196 | `morning-alert`'s Telegram sender logs the raw fetch error, whose message… | none — one-line change in one function;… | 2026-09-13 — read… | [:4120](open_issues.md#L4120) |
| OI-197 | Founder observability gaps: payment-flow alerting dormant, EF auth-outage… | none — no schema/migration/payment/auth… | never — this is a gap analysis surfaced… | [:4132](open_issues.md#L4132) |
| OI-198 | pr-detection cron: repeated Gateway Timeout on paged_fetch (4x in 24h,… | none | 2026-09-14, live query against… | [:4176](open_issues.md#L4176) |
| OI-199 | cleanup_cron_call_log() spares only TWO global rows, not each function's… | none | 2026-09-14, live read of the function… | [:4199](open_issues.md#L4199) |
| OI-200 | founder_metrics_ops().client_errors_today counts benign event-coded… | none | 2026-09-14, B-pass on migration 135… | [:4264](open_issues.md#L4264) |
| OI-201 | alert_cron_function_dead can burst-dispatch many critical alerts at once;… | none | 2026-09-14, Hermes lens L31… | [:4302](open_issues.md#L4302) |
| OI-202 | users.subscription_status never reconciles to free after expiry | none | 2026-09-15, founder spot-check of… | [:4344](open_issues.md#L4344) |
| OI-204 | Full-rescan sync architecture (_syncExerciseLogs/_syncNutritionLogs) times… | none | 2026-09-16, `client_errors` telemetry… | [:4385](open_issues.md#L4385) |
| OI-205 | Already-authenticated user opening a valid /reset link is silently… | none | 2026-09-16, B-pass on the… | [:4440](open_issues.md#L4440) |
| OI-206 | retire_worktree.dart's regenerable-ignored-paths allowlist is missing… | none | 2026-09-16, live read of… | [:4511](open_issues.md#L4511) |
| OI-208 | AuthNotifier._teardown() swallows internal failures with no signal to… | none | 2026-09-16, B-pass on the… | [:4553](open_issues.md#L4553) |
