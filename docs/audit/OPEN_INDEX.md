# Open Issues — index (auto-generated)

**24 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-44 | L26 CQRS violations: 10 query-named methods with side effects (P2) | none | 2026-07-29 | [:157](open_issues.md#L157) |
| OI-45 | L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1) | Unit 3c (`graduation_screen.dart` stale-`nextPhase`-across-`generateAndSchedule`-await | 2026-07-30 | [:195](open_issues.md#L195) |
| OI-50 | L37 empty/null-shape readers: 23 risky accesses across 6 files (P2) | none | 2026-07-29 | [:531](open_issues.md#L531) |
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:627](open_issues.md#L627) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:636](open_issues.md#L636) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:644](open_issues.md#L644) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:651](open_issues.md#L651) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:660](open_issues.md#L660) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:671](open_issues.md#L671) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:717](open_issues.md#L717) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:731](open_issues.md#L731) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:738](open_issues.md#L738) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:745](open_issues.md#L745) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:752](open_issues.md#L752) |
| OI-65 | Qualification-Exam feature | none | never | [:761](open_issues.md#L761) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:770](open_issues.md#L770) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:851](open_issues.md#L851) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:868](open_issues.md#L868) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:900](open_issues.md#L900) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:919](open_issues.md#L919) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:930](open_issues.md#L930) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and | [:942](open_issues.md#L942) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5, re-engagement-prefilter) — live | [:441](open_issues.md#L441) |
| OI-79 | Un-ranged PostgREST reads silently truncate at db-max-rows (1000) in cron… | none | 2026-08-01 (Hermes L31, Unit 5 re-engagement-prefilter) — empirically confirmed | [:492](open_issues.md#L492) |
