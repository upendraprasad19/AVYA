# Open Issues — index (auto-generated)

**81 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 9 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below… | 2026-08-05 — flag inventory, dependency… | [:242](open_issues.md#L242) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:309](open_issues.md#L309) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:317](open_issues.md#L317) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — visibility read live (`gh… | [:326](open_issues.md#L326) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — every PR's… | [:357](open_issues.md#L357) |
| OI-58 | Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a) | none — but see the correction below; the… | never (for the residual below; the… | [:391](open_issues.md#L391) |
| OI-60 | Flip `enable_hold_weeks` | 3 remaining flip-on blockers** in… | 2026-08-20 — the blocker list re-derived… | [:465](open_issues.md#L465) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:548](open_issues.md#L548) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:556](open_issues.md#L556) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52,… | 2026-08-05 — BLOCKER ONLY (OI-52… | [:565](open_issues.md#L565) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:573](open_issues.md#L573) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05:… | 2026-08-05 — BLOCKER ONLY (the founder… | [:582](open_issues.md#L582) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:602](open_issues.md#L602) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:614](open_issues.md#L614) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:631](open_issues.md#L631) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:663](open_issues.md#L663) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent… | [:682](open_issues.md#L682) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5,… | [:84](open_issues.md#L84) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9,… | [:135](open_issues.md#L135) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the… | [:165](open_issues.md#L165) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already… | 2026-08-05 (telemetry-readiness… | [:716](open_issues.md#L716) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and… | 2026-08-03 (twice in one day, both times… | [:764](open_issues.md#L764) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED… | 2026-08-05 — record confirmed present by… | [:808](open_issues.md#L808) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now… | 2026-08-10 (`wc -l` = **800** on `main`… | [:864](open_issues.md#L864) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split… | 2026-08-04 (call-site counts below… | [:938](open_issues.md#L938) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and… | 2026-08-05 (found by measuring the… | [:980](open_issues.md#L980) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it… | 2026-08-05 — surfaced by the analyzer… | [:1040](open_issues.md#L1040) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT… | 2026-08-06 — found by the round-2… | [:1068](open_issues.md#L1068) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism… | 2026-08-07 — both definitions read… | [:1102](open_issues.md#L1102) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy… | 2026-08-07 — `_featureSubtitle`'s switch… | [:1155](open_issues.md#L1155) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own… | 2026-08-08 — B-pass on branch… | [:1355](open_issues.md#L1355) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is… | 2026-08-11 — round-2 context-blind… | [:1386](open_issues.md#L1386) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or… | 2026-08-11 — prior-art sweep + round-2… | [:1426](open_issues.md#L1426) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis,… | 2026-08-11 — round-2 review of… | [:1459](open_issues.md#L1459) |
| OI-104 | `check_hooks_installed.dart` detects hook PRESENCE, not staleness;… | nothing technical. | 2026-08-11 — `.git/hooks/pre-commit` and… | [:1480](open_issues.md#L1480) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a… | never — this is OI-102's unanswered… | [:1521](open_issues.md#L1521) |
| OI-107 | `build-apk.md`'s two inline `gh run list` copies should move onto… | nothing technical. It is deliberately… | 2026-08-12 — both call sites read… | [:1550](open_issues.md#L1550) |
| OI-108 | `safe_commit.sh` silently accepts a git FLAG as the commit message (P2) | nothing. The fix is a few lines; it is… | 2026-08-12 — hit live while committing… | [:1581](open_issues.md#L1581) |
| OI-109 | ForgotPasswordSheet's two-step code flow has no test | nothing — bounded work | 2026-08-07 (`grep -rln… | [:1249](open_issues.md#L1249) |
| OI-110 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate… | 2026-08-08 (`dart run… | [:1273](open_issues.md#L1273) |
| OI-111 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a… | 2026-08-07 (grep below run against… | [:1220](open_issues.md#L1220) |
| OI-113 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`,… | [:1310](open_issues.md#L1310) |
| OI-114 | `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only… | nothing | 2026-08-10 (read the file; confirmed the… | [:1329](open_issues.md#L1329) |
| OI-117 | a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2) | nothing. | 2026-08-13 — observed live. The… | [:1634](open_issues.md#L1634) |
| OI-119 | `git_safety_hook.dart` matches command TEXT, so it blocks commands that… | nothing, but it needs a false-positive… | 2026-08-13. ⚠ **The two detectors are… | [:1687](open_issues.md#L1687) |
| OI-120 | the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of… | nothing; needs the same measurement… | 2026-08-13 — both numbers read directly,… | [:1658](open_issues.md#L1658) |
| OI-122 | `check_regression_catalog.dart` runs `flutter test` with no concurrency… | nothing technical. Needs a measurement… | 2026-08-13 — read directly at… | [:1612](open_issues.md#L1612) |
| OI-123 | the test-suite UPSERT path is guarded only transitively, by file ordering… | nothing — scoped and understood; needs… | 2026-08-15 — Hermes lens (destructive-op… | [:1748](open_issues.md#L1748) |
| OI-124 | the device delete-account test hard-deletes `auth.users` with NO… | nothing technical. It is currently… | 2026-08-15 — Hermes lens (destructive-op… | [:1779](open_issues.md#L1779) |
| OI-125 | Selectable past hold weeks (FOB-6) — 6 named lifecycle traps | none technically — but it is a NEW… | 2026-08-13 — filed from… | [:1803](open_issues.md#L1803) |
| OI-126 | The `logged` / `custom_template` training-day predicate split (5 call… | none. Pickable, but it is a live… | 2026-08-13 — the 5 call sites and the… | [:1830](open_issues.md#L1830) |
| OI-127 | `plan_start` moving under a live hold week: is the streak identity still… | none. Route to the piece that already… | 2026-08-13 — the four `plan_start` write… | [:1859](open_issues.md#L1859) |
| OI-130 | concurrent sessions have no way to see what another is working on, so the… | nothing technical, but the cheap fixes… | 2026-08-16 — three measured instances,… | [:1909](open_issues.md#L1909) |
| OI-131 | the golden tests are excluded from every gate on every platform, so they… | nothing technical — but it needs a… | 2026-08-20 — measured while fixing… | [:1966](open_issues.md#L1966) |
| OI-134 | mutation-proving runs in the shared worktree, where §4.13's guarantee does… | nothing. Small and self-contained. | 2026-08-20 — observed live, twice, by… | [:2007](open_issues.md#L2007) |
| OI-135 | 60 of 125 migration-ledger hashes do not match their files, and nothing… | nothing technical. The fix shape is… | 2026-08-20 — measured, not estimated.… | [:2048](open_issues.md#L2048) |
| OI-136 | Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files… | nothing technical. Needs the same… | 2026-08-20 — measured, not inferred.… | [:2086](open_issues.md#L2086) |
| OI-137 | the migration-ledger gate checks that `hash:` EXISTS, never that it is a… | nothing technical. Same… | 2026-08-20 — reproduced, not inferred.… | [:2129](open_issues.md#L2129) |
| OI-138 | `retire_worktree` removes the worktree but leaves the BRANCH, silently… | none. Small, but see the trap below — it… | 2026-08-25 — read… | [:2167](open_issues.md#L2167) |
| OI-139 | the only tool that DELETES developer work is tiered `feature`; every tool… | FOUNDER. This is a governance decision,… | 2026-08-25 — `grep -n retire_worktree… | [:2203](open_issues.md#L2203) |
| OI-140 | nothing detects a duplicate diagnose `bug_id`, though the identical… | none. | 2026-08-25 — `ls docs/diagnoses/*.md \|… | [:2241](open_issues.md#L2241) |
| OI-141 | retire the notification-preferences snapshot fallback once APK +39 is… | APK +39 adoption — a founder release… | 2026-08-26 — filed as the tracked half… | [:1181](open_issues.md#L1181) |
| OI-142 | deploy-artifact commits are unenforced: prod runs Edge Function code whose… | none. | 2026-08-27 — the class was LIVE in the… | [:2316](open_issues.md#L2316) |
| OI-143 | nothing checks whether a multi-task BATCH is finished; the Stop hook only… | nothing technical. Needs a design call… | 2026-08-28 — observed live, repeatedly,… | [:2276](open_issues.md#L2276) |
| OI-145 | 34 licence-clean drawings depict bodyweight exercises the library does not… | nothing technical. It needs the… | 2026-08-29 — the 302-entry manifest of… | [:2359](open_issues.md#L2359) |
| OI-146 | three duplicate exercise rows, two of them dead, one skewing selection… | nothing. Needs a decision on whether the… | 2026-08-29 — name-normalised (case,… | [:2399](open_issues.md#L2399) |
| OI-147 | remove Donkey Calf Raise: a one-row deletion that touches the cloud seed,… | nothing technical. Needs the… | 2026-08-29 — every claim below… | [:2455](open_issues.md#L2455) |
| OI-148 | 23 equipment-variant exercises the plate mapping surfaced, blocked on a… | the selection-skew question below. Not… | 2026-08-29 — each named row checked… | [:2517](open_issues.md#L2517) |
| OI-149 | breathing_cue holds a bare number on 136 of 292 rows; the original text is… | the founder** — 136 replacement cues… | 2026-08-29 — counted, and the recovery… | [:2547](open_issues.md#L2547) |
| OI-151 | telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and… | nothing technical. It is a PRE-LAUNCH… | 2026-08-30 — measured live on… | [:2579](open_issues.md#L2579) |
| OI-152 | six-plus call sites fire `syncX()` and `pushSnapshot()` back to back,… | nothing technical. Bounded, mechanical… | 2026-08-30 — every call site below read… | [:2631](open_issues.md#L2631) |
| OI-153 | PRO media caps read a `channel` value nothing writes (P1) | enumerate every `channel` reader first | 2026-09-03 — source + live prod | [:2673](open_issues.md#L2673) |
| OI-154 | a cleared profile field silently reverts on the next sign-in (P1) | needs a design spec (tombstone +… | 2026-09-03 — source, full chain traced | [:2793](open_issues.md#L2793) |
| OI-155 | six gates are wired to no runner, and Gate 33 cannot detect it (P1) | re-enumerate the skip block mechanically | 2026-09-03 — greps with positive control | [:2816](open_issues.md#L2816) |
| OI-156 | CLAUDE.md numeric claims drift because nothing re-derives them (P2) | nothing — mechanical | 2026-09-03 — each count re-measured | [:2840](open_issues.md#L2840) |
| OI-157 | no SAST and no SCA run anywhere in CI (P1) | founder call on Semgrep scope | 2026-09-03 — grep, 0 hits | [:2865](open_issues.md#L2865) |
| OI-158 | tests and gates that cannot fail (P2) | TEST-1 needs one device run to establish… | 2026-09-03 — source-verified | [:2885](open_issues.md#L2885) |
| OI-159 | sync and Edge Function correctness residue (P2) | nothing — but see OI-154 for the ARCH-1… | 2026-09-03 — source-verified | [:2908](open_issues.md#L2908) |
| OI-160 | dependency + build-toolchain hygiene (P2) | DEP-7 needs a founder unpin decision | 2026-09-03 — versions read from files | [:2928](open_issues.md#L2928) |
| OI-161 | two blind spots in our own observability and discipline gates (P3) | INFRA-13 is platform-tier, needs its own… | 2026-09-03 — live query + grep | [:2951](open_issues.md#L2951) |
| OI-162 | the delete-account rate limit is INERT in production; its counter has… | needs OI-153's channel-reader… | 2026-09-03 — schema + DDL + repo grep +… | [:2993](open_issues.md#L2993) |
