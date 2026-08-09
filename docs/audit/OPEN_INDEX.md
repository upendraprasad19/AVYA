# Open Issues — index (auto-generated)

**38 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the remaining 12 workout-generator ship-dark flags (was 13;… | FOUNDER — but read the shape below before treating this as one decision. | 2026-08-05 — flag inventory, dependency order and the data lag all re-derived from | [:902](open_issues.md#L902) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:939](open_issues.md#L939) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in. (The "sequenced after OI-52" half is dead — OI-52 closed | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:947](open_issues.md#L947) |
| OI-56 | Revert repo to private | FOUNDER — **dated decision 2026-08-05: stay public until September 2026**, then | 2026-08-05 — visibility read live (`gh repo view` → **PUBLIC**); CI cost measured | [:956](open_issues.md#L956) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER — **dated decision 2026-08-05: merge #16 only; the other six are | 2026-08-05 — every PR's `mergeStateStatus` + check rollup read live from the GitHub | [:987](open_issues.md#L987) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:1021](open_issues.md#L1021) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:1067](open_issues.md#L1067) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | none — its only blocker was OI-52, which closed 2026-07-27. Pickable now. | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:1081](open_issues.md#L1081) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 is unblocked — its OI-52 dependency closed 2026-07-27. Unit A: F3 anytime, | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:1089](open_issues.md#L1089) |
| OI-63 | Restore C2: 137-policy RLS initplan | none — it was sequenced after OI-52, which closed 2026-07-27. Pickable now. | 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`, | [:1098](open_issues.md#L1098) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:1106](open_issues.md#L1106) |
| OI-65 | Qualification-Exam feature | FOUNDER — **dated decision 2026-08-05: pick this up in January 2027.** Nothing | 2026-08-05 — BLOCKER ONLY (the founder decision above was taken in-session). The | [:1115](open_issues.md#L1115) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:1135](open_issues.md#L1135) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:1216](open_issues.md#L1216) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:1233](open_issues.md#L1233) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:1265](open_issues.md#L1265) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and | [:1357](open_issues.md#L1357) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5, re-engagement-prefilter) — live | [:533](open_issues.md#L533) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9, `oi79-paged-cron-reads`) — measured, not inferred. | [:584](open_issues.md#L584) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the OI-79 sweep; NOT re-verified since. | [:612](open_issues.md#L612) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already refuted (below). The next attempt needs | 2026-08-05 (telemetry-readiness re-checked against live v11 + `pubspec.yaml` | [:1497](open_issues.md#L1497) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and was reproduced twice; scheduled work. | 2026-08-03 (twice in one day, both times the same tests passed standalone | [:1633](open_issues.md#L1633) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none. The concrete instance RESOLVED 2026-08-05 — the session that did the work | 2026-08-05 — record confirmed present by direct read of its frontmatter, and CI is | [:1677](open_issues.md#L1677) |
| OI-88 | `restoring_screen.dart` split owed (allow-list entry now removed) (P3) | nobody yet — no session has picked up the split. The Gate 43 *exemption* half is | 2026-08-05 (`wc -l` = 791 on `repo-gate-pattern-sweep`; allow-list entry removed in | [:1733](open_issues.md#L1733) |
| OI-89 | the equipment tier is a SOFT preference: a "bodyweight" user is served gym… | nothing technical — it needs a PRODUCT decision first (see "Product question" | 2026-08-04 (root cause re-read directly in `exercise_selector.dart` + | [:1773](open_issues.md#L1773) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split below must be measured before a fix is | 2026-08-04 (call-site counts below produced by direct grep; the getter bodies and | [:1836](open_issues.md#L1836) |
| OI-91 | 138 dead `CLAUDE.md §N` citations remain in live code/test/script comments… | nothing — mechanical, but large enough that it wants its own batch rather than | 2026-08-05 (count re-derived by grep at filing time; see the exact command below) | [:1878](open_issues.md#L1878) |
| OI-93 | a deployed Edge Function can lag the repo indefinitely; the parity test… | nothing. The mechanism is understood and was measured, not inferred. Building | 2026-08-05 (found by measuring the repo-vs-live delta of `log-client-error` during | [:2014](open_issues.md#L2014) |
| OI-94 | `anonKey` is deprecated; production still passes it to… | nothing technical to *start*, but it needs a founder/dashboard step — see below. | 2026-08-05 — surfaced by the analyzer immediately after the supabase_flutter | [:2074](open_issues.md#L2074) |
| OI-95 | a kill-switch is only reachable in DEBUG builds, so no flag can be… | nothing technical. It needs a PRODUCT decision on *where* an operator switch | 2026-08-06 — found by the round-2 reviewer of the `deps-board-equipment` batch and | [:2102](open_issues.md#L2102) |
| OI-96 | community promotion has TWO mechanisms and the trigger may starve the… | a PRODUCT decision — which mechanism owns promotion. The mechanism is understood | 2026-08-07 — both definitions read directly (the trigger from live `pg_proc`, the | [:2136](open_issues.md#L2136) |
| OI-97 | five PaywallSheet labels fall through to generic copy (P3) | nothing — mechanical, but it is copy work, so it wants the Wardroom brand soul | 2026-08-07 — `_featureSubtitle`'s switch read directly against every | [:2189](open_issues.md#L2189) |
| OI-98 | notification preferences are push-only: a reinstall overwrites the… | nothing technical. The mechanism is understood and read from code; what is NOT | 2026-08-07 — by grep across `lib/core/services/` and `lib/features/auth/`, while | [:2215](open_issues.md#L2215) |
| OI-100 | ForgotPasswordSheet's two-step code flow has no test | nothing — bounded work | 2026-08-07 (`grep -rln "ForgotPasswordSheet" test/` → no matches) | [:2290](open_issues.md#L2290) |
| OI-101 | ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist | nothing — bounded, mechanical work. Gate 44 already prevents new instances. | 2026-08-08 (`dart run scripts/check_sot_registry_citations.dart` reports the | [:2314](open_issues.md#L2314) |
| OI-102 | the stale-`userId` sink guard covers the nutrition fan-out only; ~26… | nothing — this is bounded work, not a decision | 2026-08-07 (grep below run against `post38-auth-fixes`) | [:2261](open_issues.md#L2261) |
| OI-103 | OI numbering collides across concurrent sessions and nothing detects it | nothing — a small gate, but it needs a decision on where it runs (see below) | 2026-08-09 (two live collisions in one day: OI-96/97/98, then OI-99) | [:2351](open_issues.md#L2351) |
| OI-104 | the anon telemetry lane's daily budget is a non-atomic count-then-insert | nothing | 2026-08-09 (B-pass on `d4a8de00`, reviewer read the deployed function source) | [:2376](open_issues.md#L2376) |
