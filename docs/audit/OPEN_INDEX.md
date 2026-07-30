# Open Issues — index (auto-generated)

**23 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-25 | Coach-media consent UI flow (client follow-up) | none | 2026-07-26 | [:78](open_issues.md#L78) |
| OI-44 | L26 CQRS violations: 10 query-named methods with side effects (P2) | none | 2026-07-29 | [:120](open_issues.md#L120) |
| OI-45 | L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1) | Unit 3b (cross-device optimistic-lock RPC wiring for the progress map — not yet | 2026-07-30 | [:158](open_issues.md#L158) |
| OI-48 | L31 cron efficiency: 3 functions are O(all users), recompute-everything… | none | 2026-07-29 | [:372](open_issues.md#L372) |
| OI-50 | L37 empty/null-shape readers: 23 risky accesses across 6 files (P2) | none | 2026-07-29 | [:422](open_issues.md#L422) |
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:518](open_issues.md#L518) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:527](open_issues.md#L527) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:535](open_issues.md#L535) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:542](open_issues.md#L542) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:551](open_issues.md#L551) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:562](open_issues.md#L562) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:608](open_issues.md#L608) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:622](open_issues.md#L622) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:629](open_issues.md#L629) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:636](open_issues.md#L636) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:643](open_issues.md#L643) |
| OI-65 | Qualification-Exam feature | none | never | [:652](open_issues.md#L652) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:661](open_issues.md#L661) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:742](open_issues.md#L742) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:759](open_issues.md#L759) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:791](open_issues.md#L791) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:810](open_issues.md#L810) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:821](open_issues.md#L821) |
