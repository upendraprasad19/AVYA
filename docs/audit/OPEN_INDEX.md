# Open Issues — index (auto-generated)

**29 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:866](open_issues.md#L866) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:875](open_issues.md#L875) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:883](open_issues.md#L883) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:890](open_issues.md#L890) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:899](open_issues.md#L899) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:910](open_issues.md#L910) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:956](open_issues.md#L956) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:970](open_issues.md#L970) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:977](open_issues.md#L977) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:984](open_issues.md#L984) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:991](open_issues.md#L991) |
| OI-65 | Qualification-Exam feature | none | never | [:1000](open_issues.md#L1000) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:1009](open_issues.md#L1009) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:1090](open_issues.md#L1090) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:1107](open_issues.md#L1107) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:1139](open_issues.md#L1139) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:1158](open_issues.md#L1158) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:1169](open_issues.md#L1169) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and | [:1181](open_issues.md#L1181) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5, re-engagement-prefilter) — live | [:533](open_issues.md#L533) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9, `oi79-paged-cron-reads`) — measured, not inferred. | [:584](open_issues.md#L584) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the OI-79 sweep; NOT re-verified since. | [:612](open_issues.md#L612) |
| OI-82 | `promote-community-item` calls an RPC that does not exist on this project… | none | 2026-08-01 (Unit 9) — `community_votes_summary` is absent from `pg_proc` in EVERY | [:635](open_issues.md#L635) |
| OI-85 | repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2) | none — but three mechanisms are already refuted (below). The next attempt needs | 2026-08-03 (Unit A, diagnose `d1f6b3` — both refutations reproduced from code) | [:1321](open_issues.md#L1321) |
| OI-86 | two concurrent `flutter test` runs on this machine corrupt each other's… | none — the mechanism is understood and was reproduced twice; scheduled work. | 2026-08-03 (twice in one day, both times the same tests passed standalone | [:1446](open_issues.md#L1446) |
| OI-87 | one session's non-compliant merge into local `main` blocks every other… | none for the ANALYSIS; the concrete instance below needs a plan-review record | 2026-08-03 (reproduced by the blocked push described below; both worktrees and | [:1490](open_issues.md#L1490) |
| OI-88 | `restoring_screen.dart` added to the Gate 43 allow-list; split owed (P3) | nobody yet — no session has picked up the split. | never | [:1543](open_issues.md#L1543) |
| OI-89 | the equipment tier is a SOFT preference: a "bodyweight" user is served gym… | nothing technical — it needs a PRODUCT decision first (see "Product question" | 2026-08-04 (root cause re-read directly in `exercise_selector.dart` + | [:1571](open_issues.md#L1571) |
| OI-90 | `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain… | nothing — but the reader-vs-writer split below must be measured before a fix is | 2026-08-04 (call-site counts below produced by direct grep; the getter bodies and | [:1622](open_issues.md#L1622) |
