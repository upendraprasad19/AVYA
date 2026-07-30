# Open Issues — index (auto-generated)

**23 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-25 | Coach-media consent UI flow (client follow-up) | none | 2026-07-26 | [:78](open_issues.md#L78) |
| OI-44 | L26 CQRS violations: 10 query-named methods with side effects (P2) | none | 2026-07-29 | [:120](open_issues.md#L120) |
| OI-45 | L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1) | none | 2026-07-29 | [:158](open_issues.md#L158) |
| OI-48 | L31 cron efficiency: 3 functions are O(all users), recompute-everything… | none | 2026-07-29 | [:281](open_issues.md#L281) |
| OI-50 | L37 empty/null-shape readers: 23 risky accesses across 6 files (P2) | none | 2026-07-29 | [:331](open_issues.md#L331) |
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:427](open_issues.md#L427) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:436](open_issues.md#L436) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:444](open_issues.md#L444) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:451](open_issues.md#L451) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:460](open_issues.md#L460) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:471](open_issues.md#L471) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:517](open_issues.md#L517) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:531](open_issues.md#L531) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:538](open_issues.md#L538) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:545](open_issues.md#L545) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:552](open_issues.md#L552) |
| OI-65 | Qualification-Exam feature | none | never | [:561](open_issues.md#L561) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:570](open_issues.md#L570) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:651](open_issues.md#L651) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:668](open_issues.md#L668) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:700](open_issues.md#L700) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:719](open_issues.md#L719) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:730](open_issues.md#L730) |
