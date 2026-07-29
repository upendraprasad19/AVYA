# Open Issues — index (auto-generated)

**24 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-25 | Coach-media consent UI flow (client follow-up) | none | 2026-07-26 | [:78](open_issues.md#L78) |
| OI-44 | L26 CQRS violations: 10 query-named methods with side effects (P2) | none | 2026-07-26 | [:120](open_issues.md#L120) |
| OI-45 | L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1) | none | 2026-07-26 | [:137](open_issues.md#L137) |
| OI-46 | L28 service-invariant gaps: 3 client-side-only rules (P1) | none | 2026-07-26 | [:152](open_issues.md#L152) |
| OI-48 | L31 cron efficiency: 3 functions are O(all users), recompute-everything… | none | 2026-07-26 | [:167](open_issues.md#L167) |
| OI-50 | L37 empty/null-shape readers: 23 risky accesses across 6 files (P2) | none | 2026-07-26 | [:197](open_issues.md#L197) |
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:268](open_issues.md#L268) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:277](open_issues.md#L277) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:285](open_issues.md#L285) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:292](open_issues.md#L292) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:301](open_issues.md#L301) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:312](open_issues.md#L312) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:358](open_issues.md#L358) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:372](open_issues.md#L372) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:379](open_issues.md#L379) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:386](open_issues.md#L386) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:393](open_issues.md#L393) |
| OI-65 | Qualification-Exam feature | none | never | [:402](open_issues.md#L402) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:411](open_issues.md#L411) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:492](open_issues.md#L492) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:509](open_issues.md#L509) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:541](open_issues.md#L541) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:560](open_issues.md#L560) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:571](open_issues.md#L571) |
