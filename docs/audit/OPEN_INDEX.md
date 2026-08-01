# Open Issues — index (auto-generated)

**27 open.** One line each; full detail in [`open_issues.md`](open_issues.md) at the cited line, so a single entry can be read with `Read(open_issues.md, offset: <line>, limit: 60)` instead of loading the file. Closed history: [`closed_issues.md`](closed_issues.md).

`Blocked on` answers "what can I pick up right now". `Verified` is when the entry was last checked against reality — `never` means the text has not been re-confirmed since it was filed and should be treated as a claim, not a fact. OI-47 read as authoritative for a day while being wrong; that is what this column exists to make visible.

Re-run: `dart run scripts/build_oi_index.dart`

| OI | Title | Blocked on | Verified | ↦ |
|---|---|---|---|---|
| OI-44 | L26 CQRS violations: 10 query-named methods with side effects (P2) | none | 2026-07-29 | [:157](open_issues.md#L157) |
| OI-50 | L37 empty/null-shape readers: 23 risky accesses across 6 files (P2) | none | 2026-07-29 | [:679](open_issues.md#L679) |
| OI-53 | Flip the 13 workout-generator ship-dark flags | FOUNDER | never | [:775](open_issues.md#L775) |
| OI-54 | Confirm `/admin` access | FOUNDER (must load `/admin` signed-in) | never | [:784](open_issues.md#L784) |
| OI-55 | Live `amar` re-verify (Unit 0) | FOUNDER sign-in; sequenced after OI-52 | never | [:792](open_issues.md#L792) |
| OI-56 | Revert repo to private | FOUNDER (after billing is fixed) | never | [:799](open_issues.md#L799) |
| OI-57 | Decide the 7 open Dependabot PRs | FOUNDER | never | [:808](open_issues.md#L808) |
| OI-58 | Keystone gate: single-parent + subject-spoof bypass | none | never | [:819](open_issues.md#L819) |
| OI-60 | Flip `enable_hold_weeks` | 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in | never | [:865](open_issues.md#L865) |
| OI-61 | Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup | OI-52 | never | [:879](open_issues.md#L879) |
| OI-62 | Coach-reliability: FC6 + Unit A | FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated. | never | [:886](open_issues.md#L886) |
| OI-63 | Restore C2: 137-policy RLS initplan | sequenced after OI-52 | never | [:893](open_issues.md#L893) |
| OI-64 | Discipline-overhead: the three unbuilt gates | none | never | [:900](open_issues.md#L900) |
| OI-65 | Qualification-Exam feature | none | never | [:909](open_issues.md#L909) |
| OI-66 | Prove or remove the CI gradle cache | none | never | [:918](open_issues.md#L918) |
| OI-69 | Nothing detects this backlog going stale AGAIN | none | never | [:999](open_issues.md#L999) |
| OI-73 | ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate | none | never | [:1016](open_issues.md#L1016) |
| OI-74 | Notification-prefs helper fetches whole snapshot_json history, unbounded | none | never | [:1048](open_issues.md#L1048) |
| OI-75 | notification_preferences has no SoT registry entry | none | never | [:1067](open_issues.md#L1067) |
| OI-76 | Notification count includes PRO-locked rows a free user cannot disable | none | never | [:1078](open_issues.md#L1078) |
| OI-77 | AI-coach chat photo references never round-trip through cloud sync/restore | none | 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and | [:1090](open_issues.md#L1090) |
| OI-78 | 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated… | none | 2026-07-31 (round-1 review of Unit 5, re-engagement-prefilter) — live | [:484](open_issues.md#L484) |
| OI-80 | check_snapshot_contract silently skips one reader citation while counting… | none | 2026-08-01 (Unit 9, `oi79-paged-cron-reads`) — measured, not inferred. | [:535](open_issues.md#L535) |
| OI-81 | 10 per-user reads still destructure `data` without `error` in 4 cron… | none | 2026-08-01 (Unit 9) — counted during the OI-79 sweep; NOT re-verified since. | [:563](open_issues.md#L563) |
| OI-82 | `promote-community-item` calls an RPC that does not exist on this project… | none | 2026-08-01 (Unit 9) — `community_votes_summary` is absent from `pg_proc` in EVERY | [:586](open_issues.md#L586) |
| OI-83 | cloud→Hive `progress` restore merges bypass every monotonic guard, and can… | none — needs a scoping decision (below) before a fix shape can be chosen. | 2026-08-01 (round-1 review of Unit 3c, `c8f3d1`, by direct read of all 7 writers) | [:1124](open_issues.md#L1124) |
| OI-84 | `graduation_screen.dart` added to the Gate 43 allow-list; split owed (P3) | none — this is scheduled work, not a blocked investigation. | 2026-08-01 (Gate 43 run: `ALLOW … (892 lines)`) | [:1168](open_issues.md#L1168) |
