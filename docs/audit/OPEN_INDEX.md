# Open Issues — index (auto-generated)

**142 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 2 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below… | 2026-08-05 — flag inventory, dependency… | [:253](open_issues.md#L253) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:382](open_issues.md#L382) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:390](open_issues.md#L390) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — visibility read live (`gh… | [:399](open_issues.md#L399) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — every PR's… | [:430](open_issues.md#L430) |
| OI-58 | Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a) | none — but see the correction below; the… | never (for the residual below; the… | [:464](open_issues.md#L464) |
| OI-60 | Flip `enable_hold_weeks` | 3 remaining flip-on blockers** in… | 2026-08-20 — the blocker list re-derived… | [:538](open_issues.md#L538) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:621](open_issues.md#L621) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:629](open_issues.md#L629) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52,… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:638](open_issues.md#L638) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:646](open_issues.md#L646) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — BLOCKER ONLY (the founder… | [:655](open_issues.md#L655) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:675](open_issues.md#L675) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:687](open_issues.md#L687) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:704](open_issues.md#L704) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:736](open_issues.md#L736) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent… | [:755](open_issues.md#L755) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5,… | [:95](open_issues.md#L95) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9,… | [:146](open_issues.md#L146) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the… | [:176](open_issues.md#L176) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already… | 2026-08-05 (telemetry-readiness… | [:789](open_issues.md#L789) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and… | 2026-08-03 (twice in one day, both times… | [:837](open_issues.md#L837) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED… | 2026-08-05 — record confirmed present by… | [:881](open_issues.md#L881) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now… | 2026-08-10 (`wc -l` = **800** on `main`… | [:937](open_issues.md#L937) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split… | 2026-08-04 (call-site counts below… | [:1011](open_issues.md#L1011) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and… | 2026-08-05 (found by measuring the… | [:1053](open_issues.md#L1053) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it… | 2026-08-05 — surfaced by the analyzer… | [:1113](open_issues.md#L1113) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT… | 2026-08-06 — found by the round-2… | [:1141](open_issues.md#L1141) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism… | 2026-08-07 — both definitions read… | [:1175](open_issues.md#L1175) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy… | 2026-08-07 — `_featureSubtitle`'s switch… | [:1228](open_issues.md#L1228) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own… | 2026-08-08 — B-pass on branch… | [:1428](open_issues.md#L1428) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is… | 2026-08-11 — round-2 context-blind… | [:1459](open_issues.md#L1459) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or… | 2026-08-11 — prior-art sweep + round-2… | [:1499](open_issues.md#L1499) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis,… | 2026-08-11 — round-2 review of… | [:1532](open_issues.md#L1532) |
| OI-104 | `check_hooks_installed.dart` detects hook PRESENCE, not staleness;… | nothing technical. | 2026-08-11 — `.git/hooks/pre-commit` and… | [:1553](open_issues.md#L1553) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a… | never — this is OI-102's unanswered… | [:1594](open_issues.md#L1594) |
| OI-107 | `build-apk.md`'s two inline `gh run list` copies should move onto… | nothing technical. It is deliberately… | 2026-08-12 — both call sites read… | [:1623](open_issues.md#L1623) |
| OI-108 | `safe_commit.sh` silently accepts a git FLAG as the commit message (P2) | nothing. The fix is a few lines; it is… | 2026-08-12 — hit live while committing… | [:1654](open_issues.md#L1654) |
| OI-109 | ForgotPasswordSheet's two-step code flow has no test | nothing — bounded work | 2026-08-07 (`grep -rln… | [:1322](open_issues.md#L1322) |
| OI-110 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate… | 2026-08-08 (`dart run… | [:1346](open_issues.md#L1346) |
| OI-111 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a… | 2026-08-07 (grep below run against… | [:1293](open_issues.md#L1293) |
| OI-113 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`,… | [:1383](open_issues.md#L1383) |
| OI-114 | `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only… | nothing | 2026-08-10 (read the file; confirmed the… | [:1402](open_issues.md#L1402) |
| OI-117 | a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2) | nothing. | 2026-08-13 — observed live. The… | [:1707](open_issues.md#L1707) |
| OI-119 | `git_safety_hook.dart` matches command TEXT, so it blocks commands that… | nothing, but it needs a false-positive… | 2026-08-13. ⚠ **The two detectors are… | [:1760](open_issues.md#L1760) |
| OI-120 | the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of… | nothing; needs the same measurement… | 2026-08-13 — both numbers read directly,… | [:1731](open_issues.md#L1731) |
| OI-122 | `check_regression_catalog.dart` runs `flutter test` with no concurrency… | nothing technical. Needs a measurement… | 2026-08-13 — read directly at… | [:1685](open_issues.md#L1685) |
| OI-123 | the test-suite UPSERT path is guarded only transitively, by file ordering… | nothing — scoped and understood; needs… | 2026-08-15 — Hermes lens (destructive-op… | [:1821](open_issues.md#L1821) |
| OI-124 | the device delete-account test hard-deletes `auth.users` with NO… | nothing technical. It is currently… | 2026-08-15 — Hermes lens (destructive-op… | [:1852](open_issues.md#L1852) |
| OI-125 | Selectable past hold weeks (FOB-6) — 6 named lifecycle traps | none technically — but it is a NEW… | 2026-08-13 — filed from… | [:1876](open_issues.md#L1876) |
| OI-126 | The `logged` / `custom_template` training-day predicate split (5 call… | none. Pickable, but it is a live… | 2026-08-13 — the 5 call sites and the… | [:1903](open_issues.md#L1903) |
| OI-127 | `plan_start` moving under a live hold week: is the streak identity still… | none. Route to the piece that already… | 2026-08-13 — the four `plan_start` write… | [:1932](open_issues.md#L1932) |
| OI-130 | concurrent sessions have no way to see what another is working on, so the… | nothing technical, but the cheap fixes… | 2026-08-16 — three measured instances,… | [:1982](open_issues.md#L1982) |
| OI-131 | the golden tests are excluded from every gate on every platform, so they… | nothing technical — but it needs a… | 2026-08-20 — measured while fixing… | [:2039](open_issues.md#L2039) |
| OI-134 | mutation-proving runs in the shared worktree, where §4.13's guarantee does… | nothing. Small and self-contained. | 2026-08-20 — observed live, twice, by… | [:2080](open_issues.md#L2080) |
| OI-135 | 60 of 125 migration-ledger hashes do not match their files, and nothing… | nothing technical. The fix shape is… | 2026-08-20 — measured, not estimated.… | [:2121](open_issues.md#L2121) |
| OI-136 | Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files… | nothing technical. Needs the same… | 2026-08-20 — measured, not inferred.… | [:2159](open_issues.md#L2159) |
| OI-137 | the migration-ledger gate checks that `hash:` EXISTS, never that it is a… | nothing technical. Same… | 2026-08-20 — reproduced, not inferred.… | [:2202](open_issues.md#L2202) |
| OI-138 | `retire_worktree` removes the worktree but leaves the BRANCH, silently… | none. Small, but see the trap below — it… | 2026-08-25 — read… | [:2240](open_issues.md#L2240) |
| OI-139 | the only tool that DELETES developer work is tiered `feature`; every tool… | FOUNDER. This is a governance decision,… | 2026-08-25 — `grep -n retire_worktree… | [:2276](open_issues.md#L2276) |
| OI-140 | nothing detects a duplicate diagnose `bug_id`, though the identical… | none. | 2026-08-25 — `ls docs/diagnoses/*.md \|… | [:2314](open_issues.md#L2314) |
| OI-141 | retire the notification-preferences snapshot fallback once APK +39 is… | APK +39 adoption — a founder release… | 2026-08-26 — filed as the tracked half… | [:1254](open_issues.md#L1254) |
| OI-142 | deploy-artifact commits are unenforced: prod runs Edge Function code whose… | none. | 2026-08-27 — the class was LIVE in the… | [:2389](open_issues.md#L2389) |
| OI-143 | nothing checks whether a multi-task BATCH is finished; the Stop hook only… | nothing technical. Needs a design call… | 2026-08-28 — observed live, repeatedly,… | [:2349](open_issues.md#L2349) |
| OI-145 | 34 licence-clean drawings depict bodyweight exercises the library does not… | nothing technical. It needs the… | 2026-08-29 — the 302-entry manifest of… | [:2432](open_issues.md#L2432) |
| OI-146 | three duplicate exercise rows, two of them dead, one skewing selection… | nothing. Needs a decision on whether the… | 2026-08-29 — name-normalised (case,… | [:2472](open_issues.md#L2472) |
| OI-147 | remove Donkey Calf Raise: a one-row deletion that touches the cloud seed,… | nothing technical. Needs the… | 2026-08-29 — every claim below… | [:2528](open_issues.md#L2528) |
| OI-148 | 23 equipment-variant exercises the plate mapping surfaced, blocked on a… | the selection-skew question below. Not… | 2026-08-29 — each named row checked… | [:2590](open_issues.md#L2590) |
| OI-149 | breathing_cue holds a bare number on 136 of 292 rows; the original text is… | the founder** — 136 replacement cues… | 2026-08-29 — counted, and the recovery… | [:2620](open_issues.md#L2620) |
| OI-151 | telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and… | nothing technical. It is a PRE-LAUNCH… | 2026-08-30 — measured live on… | [:2652](open_issues.md#L2652) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2704](open_issues.md#L2704) |
| OI-154 | a cleared profile field silently reverts on the next sign-in (P1) | needs a design spec (tombstone +… | 2026-09-03 — source, full chain traced | [:2972](open_issues.md#L2972) |
| OI-156 | CLAUDE.md numeric claims drift because nothing re-derives them (P2) | nothing — mechanical | 2026-09-03 — each count re-measured | [:3019](open_issues.md#L3019) |
| OI-157 | no SAST and no SCA run anywhere in CI (P1) | founder call on Semgrep scope | 2026-09-03 — grep, 0 hits | [:3044](open_issues.md#L3044) |
| OI-158 | tests and gates that cannot fail (P2) | TEST-1 needs one device run to establish… | 2026-09-03 — source-verified | [:3064](open_issues.md#L3064) |
| OI-159 | sync and Edge Function correctness residue (P2) | nothing — but see OI-154 for the ARCH-1… | 2026-09-03 — source-verified | [:3087](open_issues.md#L3087) |
| OI-160 | dependency + build-toolchain hygiene (P2) | DEP-7 needs a founder unpin decision | 2026-09-03 — versions read from files | [:3107](open_issues.md#L3107) |
| OI-161 | two blind spots in our own observability and discipline gates (P3) | INFRA-13 is platform-tier, needs its own… | 2026-09-03 — live query + grep | [:3130](open_issues.md#L3130) |
| OI-163 | the four-tag migration header has NO gate, and two places claimed it did… | nothing — needs a gate written,… | 2026-09-05 — repo-wide grep + the live… | [:3279](open_issues.md#L3279) |
| OI-164 | the shared QA account caps CI at ~3 runs per IST day (P2) | a founder decision on test-account… | 2026-09-05 — live `usage_counters` + the… | [:3303](open_issues.md#L3303) |
| OI-165 | `check_onconflict_live_arbiter.dart` 403s, so every `test/sql/` live… | identifying which token the runner needs… | 2026-09-05 — ran it; and the harness… | [:3325](open_issues.md#L3325) |
| OI-166 | regeneration RESTARTS the periodization wave instead of continuing it, so… | OI-175 (the window-alignment half —… | 2026-09-06 — every citation below… | [:3347](open_issues.md#L3347) |
| OI-167 | the debugging skill's bug-class numbers collide 9×, every one is cited by… | nothing technical — needs a per-citation… | 2026-09-07 — `grep -oE '^### 2\.[0-9]+'… | [:3466](open_issues.md#L3466) |
| OI-168 | nothing fires §4.9's "grep the test tree before you land" rule, so it is… | nothing technical — needs the gate… | 2026-09-07 — the pre-push full suite on… | [:3517](open_issues.md#L3517) |
| OI-169 | a local run of `test/edge_functions/` reports "All tests passed" having… | nothing — needs a decision on which… | 2026-09-07 — `flutter test… | [:3540](open_issues.md#L3540) |
| OI-173 | no cold-start weight estimate: a brand-new user, every free user, and any… | none — founder approved 2026-09-06 as… | 2026-09-06 — `plan_generator.dart:234`… | [:3394](open_issues.md#L3394) |
| OI-174 | schedule rows written past `plan_end` are never pruned, and they delay the… | none — NARROWED 2026-09-13 by OI-189… | 2026-09-13 — re-derived while closing… | [:3412](open_issues.md#L3412) |
| OI-175 | a regeneration past the phase's 4th week (`rawWeek > 4`) has no… | FOUNDER — what a regeneration should DO… | 2026-09-06 — `getCurrentWeekNumber()`… | [:3437](open_issues.md#L3437) |
| OI-177 | the live-cron snapshot that gives Gate 31 its only fileless-migration… | none | 2026-09-10 —… | [:3583](open_issues.md#L3583) |
| OI-178 | pg_cron SQL jobs are structurally invisible to the alerting stack:… | a design decision — telemetry bridge vs.… | 2026-09-10 — `cron_call_log` holds… | [:3596](open_issues.md#L3596) |
| OI-179 | `alert_cron_function_dead` cannot fire across 100% of its range, and never… | none — one-line predicate fix; the value… | 2026-09-10 — `min(started_at)` across… | [:3610](open_issues.md#L3610) |
| OI-180 | `check_sot_registry_parity` silently skips every single-number… | none | 2026-09-10 —… | [:3640](open_issues.md#L3640) |
| OI-182 | the payment grace window closes before the last verify-payment retry fires… | none — needs a founder call on the… | 2026-09-11 — read both constants… | [:3668](open_issues.md#L3668) |
| OI-184 | 4 tables rely on RLS-zero-policy default-deny alone; the raw grants under… | none — mechanically straightforward (a… | 2026-09-11 — LIVE, via the Management… | [:3770](open_issues.md#L3770) |
| OI-185 | `check_schema_column_refs.dart` validates only the FIRST line of a… | none — carried out of OI-162 (closed… | 2026-09-03 — by the audit (a prototype… | [:3844](open_issues.md#L3844) |
| OI-186 | the AI coach cannot replace ONE day with a different workout: the only… | founder product decision on tier (see… | 2026-09-10 — full census of… | [:3870](open_issues.md#L3870) |
| OI-187 | the AI coach has no read path to the 292-exercise library: the WRITE path… | nothing technical — needs a design… | 2026-09-10 — every claim below re-read… | [:3911](open_issues.md#L3911) |
| OI-188 | no re-entry path for a returning user: the free path hands them a DELOAD… | founder product decision on the… | 2026-09-10 — app behaviour read from… | [:3958](open_issues.md#L3958) |
| OI-190 | Unit 1's §4.11 gate `check_single_schedule_row_builder.dart` is WARN-only… | none — needs a plan. Input is already… | 2026-09-12 — `dart run… | [:4031](open_issues.md#L4031) |
| OI-191 | target_weight_kg can contradict the chosen goal's direction, making the… | none — bounded, no… | 2026-09-13 — reproduced live on the… | [:4045](open_issues.md#L4045) |
| OI-192 | the orphan-sync dedupe can never match a photo turn: client writes… | none — pick ONE placeholder shape (or… | 2026-09-13 — source only:… | [:4104](open_issues.md#L4104) |
| OI-193 | Gate 31 treats a COMMENTED `cron.unschedule('X')` as a real unschedule, so… | none — strip `--` comments before the… | 2026-09-12 —… | [:4114](open_issues.md#L4114) |
| OI-194 | `compute_admin_metrics_daily` (jobid 30) skipped its 2026-09-11 18:15Z… | none for the code (repair (d) below is a… | 2026-09-12 — `select function_name,… | [:4125](open_issues.md#L4125) |
| OI-196 | `morning-alert`'s Telegram sender logs the raw fetch error, whose message… | none — one-line change in one function;… | 2026-09-13 — read… | [:4167](open_issues.md#L4167) |
| OI-197 | Founder observability gaps: payment-flow alerting dormant, EF auth-outage… | none — no schema/migration/payment/auth… | never — this is a gap analysis surfaced… | [:4179](open_issues.md#L4179) |
| OI-198 | pr-detection cron: repeated Gateway Timeout on paged_fetch (4x in 24h,… | none | 2026-09-14, live query against… | [:4223](open_issues.md#L4223) |
| OI-199 | cleanup_cron_call_log() spares only TWO global rows, not each function's… | none | 2026-09-14, live read of the function… | [:4246](open_issues.md#L4246) |
| OI-200 | founder_metrics_ops().client_errors_today counts benign event-coded… | none | 2026-09-14, B-pass on migration 135… | [:4311](open_issues.md#L4311) |
| OI-201 | alert_cron_function_dead can burst-dispatch many critical alerts at once;… | none | 2026-09-14, Hermes lens L31… | [:4349](open_issues.md#L4349) |
| OI-202 | users.subscription_status never reconciles to free after expiry | none | 2026-09-15, founder spot-check of… | [:4391](open_issues.md#L4391) |
| OI-205 | Already-authenticated user opening a valid /reset link is silently… | none | 2026-09-16, B-pass on the… | [:4496](open_issues.md#L4496) |
| OI-206 | retire_worktree.dart's regenerable-ignored-paths allowlist is missing… | none | 2026-09-16, live read of… | [:4567](open_issues.md#L4567) |
| OI-207 | sot_registry.yaml: hold-weeks line_range citations (762-847, 890-915)… | none | 2026-09-16, live `Read` of… | [:4609](open_issues.md#L4609) |
| OI-208 | AuthNotifier._teardown() swallows internal failures with no signal to… | none | 2026-09-16, B-pass on the… | [:4653](open_issues.md#L4653) |
| OI-209 | check_sot_registry_parity.dart's line_range parser is blind to bare… | none | 2026-09-16, B-pass on the… | [:4686](open_issues.md#L4686) |
| OI-210 | future-prediction Edge Function has no live caller anywhere in the shipped… | founder decision (see below — surfaced… | 2026-09-16, B-pass on the… | [:4741](open_issues.md#L4741) |
| OI-211 | Custom exercise equipment field + [] to ['none'] backfill of existing rows… | founder batch scheduling | never | [:4794](open_issues.md#L4794) |
| OI-212 | Custom foods unsearchable from the main food search bar (search never… | founder product decision (separate Your… | never | [:4802](open_issues.md#L4802) |
| OI-213 | Razorpay auto-renew subscriptions (web): mandates, subscription.charged… | founder product decision on timing… | 2026-09-17 — claims traced from the… | [:4810](open_issues.md#L4810) |
| OI-214 | Diet plan Option A: curated Indian meal-template layer (recipe-first… | none | never | [:4831](open_issues.md#L4831) |
| OI-215 | Device verification expansion: Patrol flows for the UI-bug cluster,… | none | never | [:4838](open_issues.md#L4838) |
| OI-216 | snapshot-contract gate: per-entry slack mechanism for shift-sensitive… | none | never | [:4856](open_issues.md#L4856) |
| OI-217 | telemetry v2: aggregate plan-review findings by class… | none | never | [:4871](open_issues.md#L4871) |
| OI-218 | Cloud exlog tombstone residual — moved-out-date rows never tombstoned,… | none | never | [:4930](open_issues.md#L4930) |
| OI-219 | is_pr not rescanned across moveExerciseLogs — collision merge can drop a… | none | never | [:4954](open_issues.md#L4954) |
| OI-220 | Contract-sweep gate: pre-push targeted SoT contract testing | one clean batch under `--warn-only`… | 2026-09-19 — shipped on `gate-integrity`… | [:4887](open_issues.md#L4887) |
| OI-221 | tool_dispatcher defensive date-parse fallbacks can clobber the wrong date… | none | never | [:4973](open_issues.md#L4973) |
| OI-222 | Document versionCode-bump-via-merge CI gap in CLAUDE.md §4.9 | none | never | [:4991](open_issues.md#L4991) |
| OI-224 | alert_cron_function_dead threshold unreachable, cron_call_log pruned at 7… | none | 2026-09-20 — live on… | [:5059](open_issues.md#L5059) |
| OI-227 | Telegram coach connect is broken (no linking token, bot says no user… | none — UI removal is self-contained; the… | 2026-09-21 — founder tapped "Connect… | [:5115](open_issues.md#L5115) |
| OI-228 | AI coach shortenWorkout tool calls get stuck at status:queued with no… | none — Bug A is CLOSED; Bug B's "stuck… | 2026-09-22 (Batch B) — live-traced the… | [:5179](open_issues.md#L5179) |
| OI-229 | AI coach chat replies violate captain_manual.ts hard rules: 100-word cap… | none — both are prompt-adherence gaps in… | 2026-09-21 — both cited… | [:5322](open_issues.md#L5322) |
| OI-231 | AI coach addressed a promoted user by their OLD rank term (Recruit instead… | none — live verification DONE (Batch B,… | 2026-09-22 (Batch B) — settled via the… | [:5434](open_issues.md#L5434) |
| OI-233 | user_daily_snapshots' 4 cron/client writers are not atomic against each… | none — scope and fix shape are already… | 2026-09-21 — explicitly scoped out in | [:5554](open_issues.md#L5554) |
| OI-234 | alert_edge_function_health never fires — 401s write no cron_call_log row,… | none | never | [:5600](open_issues.md#L5600) |
| OI-235 | proactive_plateau_alert (~116s avg) and i-see-you-daily (~93s avg) run… | none | 2026-09-22, re-confirmed live by a… | [:5607](open_issues.md#L5607) |
| OI-236 | 12 of 14 Supabase advisor-flagged unused indexes (idx_scan=0) left… | none | never | [:5614](open_issues.md#L5614) |
| OI-237 | Extreme update:insert ratios on scheduled_workouts (34:1) and… | none | never | [:5621](open_issues.md#L5621) |
| OI-239 | Acknowledging an alert re-arms its dedup window instead of waiting out the… | none | never | [:5628](open_issues.md#L5628) |
| OI-240 | _getNextRankFromLadder's remaining/binding_constraint is inaccurate for 3… | none — bounded work, but a genuinely… | 2026-09-22 — every claim below re-read… | [:5655](open_issues.md#L5655) |
| OI-241 | Cross-worktree concurrency: no lock prevents multiple sessions running… | none | never | [:5730](open_issues.md#L5730) |
| OI-242 | realtime_pro_gate_behavioral_test.dart flakes on full-suite CI run with a… | nothing technical. Needs a… | 2026-09-22 — reproduced the CI failure… | [:5757](open_issues.md#L5757) |
