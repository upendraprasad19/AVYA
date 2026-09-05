# Open Issues — index (auto-generated)

**84 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 8 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below… | 2026-08-05 — flag inventory, dependency… | [:242](open_issues.md#L242) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:312](open_issues.md#L312) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:320](open_issues.md#L320) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — visibility read live (`gh… | [:329](open_issues.md#L329) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — every PR's… | [:360](open_issues.md#L360) |
| OI-58 | Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a) | none — but see the correction below; the… | never (for the residual below; the… | [:394](open_issues.md#L394) |
| OI-60 | Flip `enable_hold_weeks` | 3 remaining flip-on blockers** in… | 2026-08-20 — the blocker list re-derived… | [:468](open_issues.md#L468) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:551](open_issues.md#L551) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:559](open_issues.md#L559) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52,… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:568](open_issues.md#L568) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:576](open_issues.md#L576) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — BLOCKER ONLY (the founder… | [:585](open_issues.md#L585) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:605](open_issues.md#L605) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:617](open_issues.md#L617) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:634](open_issues.md#L634) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:666](open_issues.md#L666) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent… | [:685](open_issues.md#L685) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5,… | [:84](open_issues.md#L84) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9,… | [:135](open_issues.md#L135) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the… | [:165](open_issues.md#L165) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already… | 2026-08-05 (telemetry-readiness… | [:719](open_issues.md#L719) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and… | 2026-08-03 (twice in one day, both times… | [:767](open_issues.md#L767) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED… | 2026-08-05 — record confirmed present by… | [:811](open_issues.md#L811) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now… | 2026-08-10 (`wc -l` = **800** on `main`… | [:867](open_issues.md#L867) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split… | 2026-08-04 (call-site counts below… | [:941](open_issues.md#L941) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and… | 2026-08-05 (found by measuring the… | [:983](open_issues.md#L983) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it… | 2026-08-05 — surfaced by the analyzer… | [:1043](open_issues.md#L1043) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT… | 2026-08-06 — found by the round-2… | [:1071](open_issues.md#L1071) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism… | 2026-08-07 — both definitions read… | [:1105](open_issues.md#L1105) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy… | 2026-08-07 — `_featureSubtitle`'s switch… | [:1158](open_issues.md#L1158) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own… | 2026-08-08 — B-pass on branch… | [:1358](open_issues.md#L1358) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is… | 2026-08-11 — round-2 context-blind… | [:1389](open_issues.md#L1389) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or… | 2026-08-11 — prior-art sweep + round-2… | [:1429](open_issues.md#L1429) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis,… | 2026-08-11 — round-2 review of… | [:1462](open_issues.md#L1462) |
| OI-104 | `check_hooks_installed.dart` detects hook PRESENCE, not staleness;… | nothing technical. | 2026-08-11 — `.git/hooks/pre-commit` and… | [:1483](open_issues.md#L1483) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a… | never — this is OI-102's unanswered… | [:1524](open_issues.md#L1524) |
| OI-107 | `build-apk.md`'s two inline `gh run list` copies should move onto… | nothing technical. It is deliberately… | 2026-08-12 — both call sites read… | [:1553](open_issues.md#L1553) |
| OI-108 | `safe_commit.sh` silently accepts a git FLAG as the commit message (P2) | nothing. The fix is a few lines; it is… | 2026-08-12 — hit live while committing… | [:1584](open_issues.md#L1584) |
| OI-109 | ForgotPasswordSheet's two-step code flow has no test | nothing — bounded work | 2026-08-07 (`grep -rln… | [:1252](open_issues.md#L1252) |
| OI-110 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate… | 2026-08-08 (`dart run… | [:1276](open_issues.md#L1276) |
| OI-111 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a… | 2026-08-07 (grep below run against… | [:1223](open_issues.md#L1223) |
| OI-113 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`,… | [:1313](open_issues.md#L1313) |
| OI-114 | `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only… | nothing | 2026-08-10 (read the file; confirmed the… | [:1332](open_issues.md#L1332) |
| OI-117 | a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2) | nothing. | 2026-08-13 — observed live. The… | [:1637](open_issues.md#L1637) |
| OI-119 | `git_safety_hook.dart` matches command TEXT, so it blocks commands that… | nothing, but it needs a false-positive… | 2026-08-13. ⚠ **The two detectors are… | [:1690](open_issues.md#L1690) |
| OI-120 | the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of… | nothing; needs the same measurement… | 2026-08-13 — both numbers read directly,… | [:1661](open_issues.md#L1661) |
| OI-122 | `check_regression_catalog.dart` runs `flutter test` with no concurrency… | nothing technical. Needs a measurement… | 2026-08-13 — read directly at… | [:1615](open_issues.md#L1615) |
| OI-123 | the test-suite UPSERT path is guarded only transitively, by file ordering… | nothing — scoped and understood; needs… | 2026-08-15 — Hermes lens (destructive-op… | [:1751](open_issues.md#L1751) |
| OI-124 | the device delete-account test hard-deletes `auth.users` with NO… | nothing technical. It is currently… | 2026-08-15 — Hermes lens (destructive-op… | [:1782](open_issues.md#L1782) |
| OI-125 | Selectable past hold weeks (FOB-6) — 6 named lifecycle traps | none technically — but it is a NEW… | 2026-08-13 — filed from… | [:1806](open_issues.md#L1806) |
| OI-126 | The `logged` / `custom_template` training-day predicate split (5 call… | none. Pickable, but it is a live… | 2026-08-13 — the 5 call sites and the… | [:1833](open_issues.md#L1833) |
| OI-127 | `plan_start` moving under a live hold week: is the streak identity still… | none. Route to the piece that already… | 2026-08-13 — the four `plan_start` write… | [:1862](open_issues.md#L1862) |
| OI-130 | concurrent sessions have no way to see what another is working on, so the… | nothing technical, but the cheap fixes… | 2026-08-16 — three measured instances,… | [:1912](open_issues.md#L1912) |
| OI-131 | the golden tests are excluded from every gate on every platform, so they… | nothing technical — but it needs a… | 2026-08-20 — measured while fixing… | [:1969](open_issues.md#L1969) |
| OI-134 | mutation-proving runs in the shared worktree, where §4.13's guarantee does… | nothing. Small and self-contained. | 2026-08-20 — observed live, twice, by… | [:2010](open_issues.md#L2010) |
| OI-135 | 60 of 125 migration-ledger hashes do not match their files, and nothing… | nothing technical. The fix shape is… | 2026-08-20 — measured, not estimated.… | [:2051](open_issues.md#L2051) |
| OI-136 | Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files… | nothing technical. Needs the same… | 2026-08-20 — measured, not inferred.… | [:2089](open_issues.md#L2089) |
| OI-137 | the migration-ledger gate checks that `hash:` EXISTS, never that it is a… | nothing technical. Same… | 2026-08-20 — reproduced, not inferred.… | [:2132](open_issues.md#L2132) |
| OI-138 | `retire_worktree` removes the worktree but leaves the BRANCH, silently… | none. Small, but see the trap below — it… | 2026-08-25 — read… | [:2170](open_issues.md#L2170) |
| OI-139 | the only tool that DELETES developer work is tiered `feature`; every tool… | FOUNDER. This is a governance decision,… | 2026-08-25 — `grep -n retire_worktree… | [:2206](open_issues.md#L2206) |
| OI-140 | nothing detects a duplicate diagnose `bug_id`, though the identical… | none. | 2026-08-25 — `ls docs/diagnoses/*.md \|… | [:2244](open_issues.md#L2244) |
| OI-141 | retire the notification-preferences snapshot fallback once APK +39 is… | APK +39 adoption — a founder release… | 2026-08-26 — filed as the tracked half… | [:1184](open_issues.md#L1184) |
| OI-142 | deploy-artifact commits are unenforced: prod runs Edge Function code whose… | none. | 2026-08-27 — the class was LIVE in the… | [:2319](open_issues.md#L2319) |
| OI-143 | nothing checks whether a multi-task BATCH is finished; the Stop hook only… | nothing technical. Needs a design call… | 2026-08-28 — observed live, repeatedly,… | [:2279](open_issues.md#L2279) |
| OI-145 | 34 licence-clean drawings depict bodyweight exercises the library does not… | nothing technical. It needs the… | 2026-08-29 — the 302-entry manifest of… | [:2362](open_issues.md#L2362) |
| OI-146 | three duplicate exercise rows, two of them dead, one skewing selection… | nothing. Needs a decision on whether the… | 2026-08-29 — name-normalised (case,… | [:2402](open_issues.md#L2402) |
| OI-147 | remove Donkey Calf Raise: a one-row deletion that touches the cloud seed,… | nothing technical. Needs the… | 2026-08-29 — every claim below… | [:2458](open_issues.md#L2458) |
| OI-148 | 23 equipment-variant exercises the plate mapping surfaced, blocked on a… | the selection-skew question below. Not… | 2026-08-29 — each named row checked… | [:2520](open_issues.md#L2520) |
| OI-149 | breathing_cue holds a bare number on 136 of 292 rows; the original text is… | the founder** — 136 replacement cues… | 2026-08-29 — counted, and the recovery… | [:2550](open_issues.md#L2550) |
| OI-151 | telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and… | nothing technical. It is a PRE-LAUNCH… | 2026-08-30 — measured live on… | [:2582](open_issues.md#L2582) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2634](open_issues.md#L2634) |
| OI-153 | PRO media caps read a `channel` value nothing writes (P1) | enumerate every `channel` reader first | 2026-09-03 — source + live prod | [:2676](open_issues.md#L2676) |
| OI-154 | a cleared profile field silently reverts on the next sign-in (P1) | needs a design spec (tombstone +… | 2026-09-03 — source, full chain traced | [:2796](open_issues.md#L2796) |
| OI-155 | six gates are wired to no runner, and Gate 33 cannot detect it (P1) | re-enumerate the skip block mechanically | 2026-09-03 — greps with positive control | [:2819](open_issues.md#L2819) |
| OI-156 | CLAUDE.md numeric claims drift because nothing re-derives them (P2) | nothing — mechanical | 2026-09-03 — each count re-measured | [:2843](open_issues.md#L2843) |
| OI-157 | no SAST and no SCA run anywhere in CI (P1) | founder call on Semgrep scope | 2026-09-03 — grep, 0 hits | [:2868](open_issues.md#L2868) |
| OI-158 | tests and gates that cannot fail (P2) | TEST-1 needs one device run to establish… | 2026-09-03 — source-verified | [:2888](open_issues.md#L2888) |
| OI-159 | sync and Edge Function correctness residue (P2) | nothing — but see OI-154 for the ARCH-1… | 2026-09-03 — source-verified | [:2911](open_issues.md#L2911) |
| OI-160 | dependency + build-toolchain hygiene (P2) | DEP-7 needs a founder unpin decision | 2026-09-03 — versions read from files | [:2931](open_issues.md#L2931) |
| OI-161 | two blind spots in our own observability and discipline gates (P3) | INFRA-13 is platform-tier, needs its own… | 2026-09-03 — live query + grep | [:2954](open_issues.md#L2954) |
| OI-162 | the delete-account rate limit is INERT in production; its counter has… | needs OI-153's channel-reader… | 2026-09-03 — schema + DDL + repo grep +… | [:2996](open_issues.md#L2996) |
| OI-163 | the four-tag migration header has NO gate, and two places claimed it did… | nothing — needs a gate written,… | 2026-09-05 — repo-wide grep + the live… | [:3065](open_issues.md#L3065) |
| OI-164 | the shared QA account caps CI at ~3 runs per IST day (P2) | a founder decision on test-account… | 2026-09-05 — live `usage_counters` + the… | [:3089](open_issues.md#L3089) |
| OI-165 | `check_onconflict_live_arbiter.dart` 403s, so every `test/sql/` live… | identifying which token the runner needs… | 2026-09-05 — ran it; and the harness… | [:3111](open_issues.md#L3111) |
