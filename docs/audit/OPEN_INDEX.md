# Open Issues — index (auto-generated)

**23 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-44 | L26 CQRS violations: 10 query-named methods with side effects (P2) | none | 2026-07-29 | [:157](open_issues.md#L157) |
| OI-45 | L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1) | Unit 3c (`graduation_screen.dart` stale-`nextPhase`-across-`generateAndSchedule`-await | 2026-07-30 | [:195](open_issues.md#L195) |
| OI-48 | L31 cron efficiency: 3 functions are O(all users), recompute-everything… | none | 2026-07-29 | [:441](open_issues.md#L441) |
| OI-50 | L37 empty/null-shape readers: 23 risky accesses across 6 files (P2) | none | 2026-07-29 | [:491](open_issues.md#L491) |
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:587](open_issues.md#L587) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:596](open_issues.md#L596) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:604](open_issues.md#L604) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:611](open_issues.md#L611) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:620](open_issues.md#L620) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:631](open_issues.md#L631) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:677](open_issues.md#L677) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:691](open_issues.md#L691) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:698](open_issues.md#L698) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:705](open_issues.md#L705) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:712](open_issues.md#L712) |
| OI-65 | Qualification-Exam feature | none | never | [:721](open_issues.md#L721) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:730](open_issues.md#L730) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:811](open_issues.md#L811) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:828](open_issues.md#L828) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:860](open_issues.md#L860) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:879](open_issues.md#L879) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:890](open_issues.md#L890) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and | [:902](open_issues.md#L902) |
