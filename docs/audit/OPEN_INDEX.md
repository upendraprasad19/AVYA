# Open Issues — index (auto-generated)

**41 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 12 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below before treating this as one decision. | 2026-08-05 — flag inventory, dependency order and the data lag all re-derived from | [:904](open_issues.md#L904) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:941](open_issues.md#L941) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after OI-52" half is dead — OI-52 closed | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:949](open_issues.md#L949) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05: stay public until September 2026**, then | 2026-08-05 — visibility read live (`gh repo view` → **PUBLIC**); CI cost measured | [:958](open_issues.md#L958) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05: merge #16 only; the other six are | 2026-08-05 — every PR's `mergeStateStatus` + check rollup read live from the GitHub | [:989](open_issues.md#L989) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:1023](open_issues.md#L1023) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:1069](open_issues.md#L1069) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which closed 2026-07-27. Pickable now. | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:1083](open_issues.md#L1083) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency closed 2026-07-27. Unit A: F3 anytime, | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:1091](open_issues.md#L1091) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52, which closed 2026-07-27. Pickable now. | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:1100](open_issues.md#L1100) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:1108](open_issues.md#L1108) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05: pick this up in January 2027.** Nothing | 2026-08-05 — BLOCKER ONLY (the founder decision above was taken in-session). The | [:1117](open_issues.md#L1117) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:1137](open_issues.md#L1137) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:1218](open_issues.md#L1218) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:1235](open_issues.md#L1235) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:1267](open_issues.md#L1267) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and | [:1359](open_issues.md#L1359) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5, re-engagement-prefilter) — live | [:533](open_issues.md#L533) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9, `oi79-paged-cron-reads`) — measured, not inferred. | [:584](open_issues.md#L584) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the OI-79 sweep; NOT re-verified since. | [:614](open_issues.md#L614) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already refuted (below). The next attempt needs | 2026-08-05 (telemetry-readiness re-checked against live v11 + `pubspec.yaml` | [:1499](open_issues.md#L1499) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and was reproduced twice; scheduled work. | 2026-08-03 (twice in one day, both times the same tests passed standalone | [:1635](open_issues.md#L1635) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED 2026-08-05 — the session that did the work | 2026-08-05 — record confirmed present by direct read of its frontmatter, and CI is | [:1679](open_issues.md#L1679) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nothing external — but the split is now known to be **bigger than "move two | 2026-08-10 (`wc -l` = **800** on `main` @ `1e981c82`; | [:1735](open_issues.md#L1735) |
| OI-89 | the equipment tier is a SOFT preference: a "bodyweight" user is served gym… | nothing technical — it needs a PRODUCT decision first (see "Product question" | 2026-08-04 (root cause re-read directly in `exercise_selector.dart` + | [:1809](open_issues.md#L1809) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split below must be measured before a fix is | 2026-08-04 (call-site counts below produced by direct grep; the getter bodies and | [:1872](open_issues.md#L1872) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and was measured, not inferred. Building | 2026-08-05 (found by measuring the repo-vs-live delta of `log-client-error` during | [:2079](open_issues.md#L2079) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it needs a founder/dashboard step — see below. | 2026-08-05 — surfaced by the analyzer immediately after the supabase_flutter | [:2121](open_issues.md#L2121) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT decision on *where* an operator switch | 2026-08-06 — found by the round-2 reviewer of the `deps-board-equipment` batch and | [:2149](open_issues.md#L2149) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism owns promotion. The mechanism is understood | 2026-08-07 — both definitions read directly (the trigger from live `pg_proc`, the | [:2183](open_issues.md#L2183) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy work, so it wants the Wardroom brand soul | 2026-08-07 — `_featureSubtitle`'s switch read directly against every | [:2236](open_issues.md#L2236) |
| OI-98 | notification preferences are push-only: a reinstall overwrites the… | nothing technical. The mechanism is understood and read from code; what is NOT | 2026-08-07 — by grep across `lib/core/services/` and `lib/features/auth/`, while | [:2262](open_issues.md#L2262) |
| OI-99 | Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into… | nothing technical. Needs its own false-positive analysis before a fix, same | 2026-08-08 — B-pass on branch `oi91-claude-md-citations`, dispatched as part of | [:2308](open_issues.md#L2308) |
| OI-100 | `prior_art_checked:` needs to reference a VERIFIED artifact, not be free… | nothing technical. The design below is settled; it needs implementation plus the | 2026-08-11 — round-2 context-blind review of branch `safe-push-verifier`, plus | [:2339](open_issues.md#L2339) |
| OI-101 | Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points… | a founder scope decision — re-arm or retire. Two named options is precisely why | 2026-08-11 — prior-art sweep + round-2 review of `safe-push-verifier`; skip entries | [:2379](open_issues.md#L2379) |
| OI-103 | `safe_push.sh` reports OK from a detached HEAD when given an explicit… | nothing; needs its own small analysis, deliberately not bundled into | 2026-08-11 — round-2 review of `safe-push-verifier` corrected the earlier claim. | [:2453](open_issues.md#L2453) |
| OI-104 | `check_hooks_installed.dart` detects hook PRESENCE, not staleness;… | nothing technical. | 2026-08-11 — `.git/hooks/pre-commit` and `pre-push` both dated `Jul 29 10:28` | [:2474](open_issues.md#L2474) |
| OI-105 | the `Supabase Integration Tests` CI job has verified NOTHING since it was… | founder — this is not an agent-actionable item.** Adding an Actions secret | 2026-08-11 — queried the authoritative source, not inferred from behaviour: | [:2497](open_issues.md#L2497) |
| OI-106 | local `flutter test` runs ~3.9x slower per file than CI, cause unknown… | a contamination-free measurement on a quiet machine. Every candidate so far has | never — this is OI-102's unanswered half, carried forward unmeasured on 2026-08-11. | [:2538](open_issues.md#L2538) |
| OI-107 | cleanup() can DELETE from 12 PROD tables and its guard cannot refuse the… | nothing — the work is understood and scoped; it needs a design decision | 2026-08-13 — round-2 context-blind review, reproduced by direct read of | [:2568](open_issues.md#L2568) |
| OI-108 | the QA password is committed to git, and creating the account would put it… | founder — creating `qa@icanbefitter.com` and adding a `SUPABASE_TEST_PASSWORD` | 2026-08-13 — `git grep QA_Test_2024` across the whole worktree. | [:2606](open_issues.md#L2606) |
