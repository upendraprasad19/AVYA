---
branch: coach-chat-time-dup
scope: OI-502 (coach chat bubble shows the UTC hour; the daily count and coaching-notes "today" checks miss 00:00-05:30 IST) and OI-503 (one coach turn shows twice after a restore), plus the founder's removal of the Home coach tip (2026-11-13). Fix C gives each turn ONE shared key: the phone sends its Hive key as client_key, migration 178 stores it on ai_coach_interactions, ai-proxy and ai-media-proxy write it, the push looks it up first and never re-pushes cloud_restore rows, and the restore writes the cloud row back AT that key (kill switch configBox['disable_coach_client_key_restore'] keeps the old loop).
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
---

# Plan-review record: coach chat times, duplicate turns, Home tip removal

Plan: `docs/plans/2026-11-13-coach-chat-time-dup.md` (executed as rev 3.3). Every round used one fresh, context-blind
Sonnet reviewer with the agent brief preamble and an exhaustive read-only command list, verifying each claim against the
code. The coordinator re-checked every finding in the code before folding it in; plan sections 8 to 12 carry the
per-finding dispositions.

## Round 1 (rev 1, a text-and-time matcher for the restore)
17 findings, all taken or answered in plan section 8: the media row shapes (`[Photo]` locally vs `[Photo: <type>]` on
the server), the restore's 5-minute push window, the clear marker interaction, and the Home tip's "today" check (made
moot by the founder's removal).

## Round 2 (rev 2)
A P0: the matcher's rule order made the heal unreachable, and it trusted stamps the push wrote from a text guess.
Disposition (section 9): the founder chose a shared turn key over another round on the matcher; rev 2 was withdrawn and
the guessing mechanism removed.

## Round 3 (rev 3, the shared key)
No P0; 12 findings (section 10): all four request bodies (both transports), the key-occupied-by-another-turn case, the
echo skip in both input orders, a malformed key dropped instead of failing the insert, food rows carry no key, an
in-flight COUNTER (the 60 s dedup can hand two sends one key), the push's fresh-read stamp, `coach_memory` in the box,
the migration's lock behaviour.

## Round 4 (rev 3.1, the second review of the shared-key design)
No P0, no P1; six P2/P3 (section 11): the re-sent-failed-turn guard (k20), the exact in-flight begin/finally points,
the synchronous decision slice, the EF deploy as a hard prerequisite plus the deploy-from-branch diff check, the kill
switch's scope, `lock_timeout` / `IF NOT EXISTS`, and tests k21, k22, p8.

## Round 5 (rev 3.2, convergence)
Verdict converged: no P0, no P1. One reachable P2 taken: rows restored from the cloud are never pushed back (they were
the source of the 162 live `in_app_orphan` echoes, and with the kill switch on they would have become KEYED echoes);
test p9. Four P3s taken: the Retry branch opens its `try` at `beginInFlight`; `ownerChangedSince` is synchronous and the
slice ends at the `put(` call; `RESET lock_timeout`; `client_key` only for a key matching the CHECK regex.

Rounds 3, 4 and 5 found no P0; rounds 4 and 5 found no P1, and round 5 found no new mechanism class.
