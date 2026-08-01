# Open Issues — index (auto-generated)

**26 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-44 | L26 CQRS violations: 10 query-named methods with side effects (P2) | none | 2026-07-29 | [:157](open_issues.md#L157) |
| OI-45 | L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1) | Unit 3c (`graduation_screen.dart` stale-`nextPhase`-across-`generateAndSchedule`-await | 2026-07-30 | [:195](open_issues.md#L195) |
| OI-50 | L37 empty/null-shape readers: 23 risky accesses across 6 files (P2) | none | 2026-07-29 | [:636](open_issues.md#L636) |
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:732](open_issues.md#L732) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:741](open_issues.md#L741) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:749](open_issues.md#L749) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:756](open_issues.md#L756) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:765](open_issues.md#L765) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:776](open_issues.md#L776) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:822](open_issues.md#L822) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:836](open_issues.md#L836) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:843](open_issues.md#L843) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:850](open_issues.md#L850) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:857](open_issues.md#L857) |
| OI-65 | Qualification-Exam feature | none | never | [:866](open_issues.md#L866) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:875](open_issues.md#L875) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:956](open_issues.md#L956) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:973](open_issues.md#L973) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:1005](open_issues.md#L1005) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:1024](open_issues.md#L1024) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:1035](open_issues.md#L1035) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and | [:1047](open_issues.md#L1047) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5, re-engagement-prefilter) — live | [:441](open_issues.md#L441) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9, `oi79-paged-cron-reads`) — measured, not inferred. | [:492](open_issues.md#L492) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the OI-79 sweep; NOT re-verified since. | [:520](open_issues.md#L520) |
| OI-82 | `promote-community-item` calls an RPC that does not exist on this project… | none | 2026-08-01 (Unit 9) — `community_votes_summary` is absent from `pg_proc` in EVERY | [:543](open_issues.md#L543) |
