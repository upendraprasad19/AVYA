# Open Issues — index (auto-generated)

**71 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 12 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below… | 2026-08-05 — flag inventory, dependency… | [:242](open_issues.md#L242) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:279](open_issues.md#L279) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:287](open_issues.md#L287) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — visibility read live (`gh… | [:296](open_issues.md#L296) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — every PR's… | [:327](open_issues.md#L327) |
| OI-58 | Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a) | none — but see the correction below; the… | never (for the residual below; the… | [:361](open_issues.md#L361) |
| OI-60 | Flip `enable_hold_weeks` | 3 remaining flip-on blockers** in… | 2026-08-20 — the blocker list re-derived… | [:435](open_issues.md#L435) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:518](open_issues.md#L518) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:526](open_issues.md#L526) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52,… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:535](open_issues.md#L535) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:543](open_issues.md#L543) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — BLOCKER ONLY (the founder… | [:552](open_issues.md#L552) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:572](open_issues.md#L572) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:584](open_issues.md#L584) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:601](open_issues.md#L601) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:633](open_issues.md#L633) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent… | [:652](open_issues.md#L652) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5,… | [:84](open_issues.md#L84) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9,… | [:135](open_issues.md#L135) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the… | [:165](open_issues.md#L165) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already… | 2026-08-05 (telemetry-readiness… | [:686](open_issues.md#L686) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and… | 2026-08-03 (twice in one day, both times… | [:734](open_issues.md#L734) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED… | 2026-08-05 — record confirmed present by… | [:778](open_issues.md#L778) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now… | 2026-08-10 (`wc -l` = **800** on `main`… | [:834](open_issues.md#L834) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split… | 2026-08-04 (call-site counts below… | [:908](open_issues.md#L908) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and… | 2026-08-05 (found by measuring the… | [:950](open_issues.md#L950) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it… | 2026-08-05 — surfaced by the analyzer… | [:1010](open_issues.md#L1010) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT… | 2026-08-06 — found by the round-2… | [:1038](open_issues.md#L1038) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism… | 2026-08-07 — both definitions read… | [:1072](open_issues.md#L1072) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy… | 2026-08-07 — `_featureSubtitle`'s switch… | [:1125](open_issues.md#L1125) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own… | 2026-08-08 — B-pass on branch… | [:1325](open_issues.md#L1325) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is… | 2026-08-11 — round-2 context-blind… | [:1356](open_issues.md#L1356) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or… | 2026-08-11 — prior-art sweep + round-2… | [:1396](open_issues.md#L1396) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis,… | 2026-08-11 — round-2 review of… | [:1429](open_issues.md#L1429) |
| OI-104 | `check_hooks_installed.dart` detects hook PRESENCE, not staleness;… | nothing technical. | 2026-08-11 — `.git/hooks/pre-commit` and… | [:1450](open_issues.md#L1450) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a… | never — this is OI-102's unanswered… | [:1491](open_issues.md#L1491) |
| OI-107 | `build-apk.md`'s two inline `gh run list` copies should move onto… | nothing technical. It is deliberately… | 2026-08-12 — both call sites read… | [:1520](open_issues.md#L1520) |
| OI-108 | `safe_commit.sh` silently accepts a git FLAG as the commit message (P2) | nothing. The fix is a few lines; it is… | 2026-08-12 — hit live while committing… | [:1551](open_issues.md#L1551) |
| OI-109 | ForgotPasswordSheet's two-step code flow has no test | nothing — bounded work | 2026-08-07 (`grep -rln… | [:1219](open_issues.md#L1219) |
| OI-110 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate… | 2026-08-08 (`dart run… | [:1243](open_issues.md#L1243) |
| OI-111 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a… | 2026-08-07 (grep below run against… | [:1190](open_issues.md#L1190) |
| OI-113 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`,… | [:1280](open_issues.md#L1280) |
| OI-114 | `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only… | nothing | 2026-08-10 (read the file; confirmed the… | [:1299](open_issues.md#L1299) |
| OI-117 | a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2) | nothing. | 2026-08-13 — observed live. The… | [:1604](open_issues.md#L1604) |
| OI-119 | `git_safety_hook.dart` matches command TEXT, so it blocks commands that… | nothing, but it needs a false-positive… | 2026-08-13. ⚠ **The two detectors are… | [:1657](open_issues.md#L1657) |
| OI-120 | the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of… | nothing; needs the same measurement… | 2026-08-13 — both numbers read directly,… | [:1628](open_issues.md#L1628) |
| OI-122 | `check_regression_catalog.dart` runs `flutter test` with no concurrency… | nothing technical. Needs a measurement… | 2026-08-13 — read directly at… | [:1582](open_issues.md#L1582) |
| OI-123 | the test-suite UPSERT path is guarded only transitively, by file ordering… | nothing — scoped and understood; needs… | 2026-08-15 — Hermes lens (destructive-op… | [:1718](open_issues.md#L1718) |
| OI-124 | the device delete-account test hard-deletes `auth.users` with NO… | nothing technical. It is currently… | 2026-08-15 — Hermes lens (destructive-op… | [:1749](open_issues.md#L1749) |
| OI-125 | Selectable past hold weeks (FOB-6) — 6 named lifecycle traps | none technically — but it is a NEW… | 2026-08-13 — filed from… | [:1773](open_issues.md#L1773) |
| OI-126 | The `logged` / `custom_template` training-day predicate split (5 call… | none. Pickable, but it is a live… | 2026-08-13 — the 5 call sites and the… | [:1800](open_issues.md#L1800) |
| OI-127 | `plan_start` moving under a live hold week: is the streak identity still… | none. Route to the piece that already… | 2026-08-13 — the four `plan_start` write… | [:1829](open_issues.md#L1829) |
| OI-130 | concurrent sessions have no way to see what another is working on, so the… | nothing technical, but the cheap fixes… | 2026-08-16 — three measured instances,… | [:1879](open_issues.md#L1879) |
| OI-131 | the golden tests are excluded from every gate on every platform, so they… | nothing technical — but it needs a… | 2026-08-20 — measured while fixing… | [:1936](open_issues.md#L1936) |
| OI-134 | mutation-proving runs in the shared worktree, where §4.13's guarantee does… | nothing. Small and self-contained. | 2026-08-20 — observed live, twice, by… | [:1977](open_issues.md#L1977) |
| OI-135 | 60 of 125 migration-ledger hashes do not match their files, and nothing… | nothing technical. The fix shape is… | 2026-08-20 — measured, not estimated.… | [:2018](open_issues.md#L2018) |
| OI-136 | Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files… | nothing technical. Needs the same… | 2026-08-20 — measured, not inferred.… | [:2056](open_issues.md#L2056) |
| OI-137 | the migration-ledger gate checks that `hash:` EXISTS, never that it is a… | nothing technical. Same… | 2026-08-20 — reproduced, not inferred.… | [:2099](open_issues.md#L2099) |
| OI-138 | `retire_worktree` removes the worktree but leaves the BRANCH, silently… | none. Small, but see the trap below — it… | 2026-08-25 — read… | [:2137](open_issues.md#L2137) |
| OI-139 | the only tool that DELETES developer work is tiered `feature`; every tool… | FOUNDER. This is a governance decision,… | 2026-08-25 — `grep -n retire_worktree… | [:2173](open_issues.md#L2173) |
| OI-140 | nothing detects a duplicate diagnose `bug_id`, though the identical… | none. | 2026-08-25 — `ls docs/diagnoses/*.md \|… | [:2211](open_issues.md#L2211) |
| OI-141 | retire the notification-preferences snapshot fallback once APK +39 is… | APK +39 adoption — a founder release… | 2026-08-26 — filed as the tracked half… | [:1151](open_issues.md#L1151) |
| OI-142 | deploy-artifact commits are unenforced: prod runs Edge Function code whose… | none. | 2026-08-27 — the class was LIVE in the… | [:2286](open_issues.md#L2286) |
| OI-143 | nothing checks whether a multi-task BATCH is finished; the Stop hook only… | nothing technical. Needs a design call… | 2026-08-28 — observed live, repeatedly,… | [:2246](open_issues.md#L2246) |
| OI-145 | 34 licence-clean drawings depict bodyweight exercises the library does not… | nothing technical. It needs the… | 2026-08-29 — the 302-entry manifest of… | [:2329](open_issues.md#L2329) |
| OI-146 | three duplicate exercise rows, two of them dead, one skewing selection… | nothing. Needs a decision on whether the… | 2026-08-29 — name-normalised (case,… | [:2369](open_issues.md#L2369) |
| OI-147 | remove Donkey Calf Raise: a one-row deletion that touches the cloud seed,… | nothing technical. Needs the… | 2026-08-29 — every claim below… | [:2425](open_issues.md#L2425) |
| OI-148 | 23 equipment-variant exercises the plate mapping surfaced, blocked on a… | the selection-skew question below. Not… | 2026-08-29 — each named row checked… | [:2487](open_issues.md#L2487) |
| OI-149 | breathing_cue holds a bare number on 136 of 292 rows; the original text is… | the founder** — 136 replacement cues… | 2026-08-29 — counted, and the recovery… | [:2517](open_issues.md#L2517) |
| OI-151 | telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and… | nothing technical. It is a PRE-LAUNCH… | 2026-08-30 — measured live on… | [:2549](open_issues.md#L2549) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2601](open_issues.md#L2601) |
