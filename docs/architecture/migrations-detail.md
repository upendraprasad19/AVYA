# Migrations — ledger hash integrity + number allocation (detail)

Moved out of `supabase/migrations/CLAUDE.md` on 2026-09-29 (OI-135 / OI-137 / OI-263) to keep that
**auto-loaded** file small — the rules stay there, condensed; this file holds the full mechanism,
the limits, and the history. Text below is the original wording, moved verbatim.

### Allocating a migration number — `scripts/mint_migration.sh` (OI-263, 2026-09-29)

Never read the next number off `ls supabase/migrations/`. On 2026-09-28 the day-swapper migration was renumbered 145 → 147 → 148 → 149 because 148 had been applied **live** from a branch that had not merged, so no file on any other branch showed it as taken. Reserve it instead:

```bash
sh scripts/mint_migration.sh --stub <slug>              # reserves mig/N on the remote, writes the four-tag header stub
sh scripts/mint_migration.sh --live snap.json --stub <slug>   # ...and also counts a fresh `list_migrations` snapshot
sh scripts/mint_migration.sh --next                     # read-only: NEXT=<n> and UNFILED=<n,n>
sh scripts/mint_migration.sh --reserve N <slug>         # adopt a number you already used (a pre-allocator branch)
sh scripts/mint_migration.sh --release N                # drop an UNFILED reservation
sh scripts/mint_migration.sh --prune                    # laptop/API only: delete mig/N once N is on origin/main
```

- **Same mechanism as `mint_oi.sh`**: `refs/heads/mig/N` created as a server-side compare-and-swap (`gh api` on the laptop, `git push --force-with-lease=<ref>:` in the cloud). Offline ⇒ the mint REFUSES (exit 2, nothing written). Its ref-create push is a documented exemption from the `safe_push.sh` rule, exactly like `mint_oi.sh`. The transport core is a COPY, pinned by `test/scripts/mint_migration_parity_test.dart`.
- **"Next free" = 1 + max over** top-level migration names at `origin/main`, local `main` and the working tree; ledger ids at `origin/main` and in the working tree; `--live` names; every `mig/*`. **Only 3-digit `NNN[x]_*.sql` top-level names count.** ⚠ The tree holds three timestamp-scheme files and a `041_chunks/` directory: a naive `[0-9]+` reads `20260331000001` as the ceiling, and a basename-only parser reads `041_chunks/041_01_rows.sql` as migration 041. Letter suffixes (`050b`) are not mintable — they are manual follow-ups that need their BASE number published or reserved.
- **Live names are NOT reliably number-prefixed** (76 of 145 live rows are prefixed, 69 are not; `050_` and `068_` each appear twice), so `--live` only ever adds prefixed numbers, and a live apply from an unmerged branch whose name has no prefix is **invisible to it**. The mint prints a stderr NOTE when live was not consulted.
- **The gate**: `scripts/check_migration_number_reserved.dart` (pre-commit + CI, auto-wired). Every ADDED top-level `NNN_*.sql` must have a `mig/N` reservation; a number already taken on `origin/main` by a DIFFERENT file fails; a letter-suffix follow-up needs its base published or reserved. Renames are read as add+delete (`--no-renames`). Files already on `origin/main` are exempt (the merge of `main` into a branch stages them as adds). Fails OPEN and says which check it skipped when offline.

⚠ **Limits of the reader side, stated plainly.** (1) "Filed" (what `--release` refuses and `--next` leaves out of `UNFILED`) is read from local branches AND remote-tracking branches — but remote-tracking refs are only as fresh as this clone's last fetch (`sync_refs` fetches `mig/*` and `main`, not every branch), so a branch pushed since then is still invisible; the gate and Gate 14 are the merge-time backstop. (2) `--reserve N` is unbounded on purpose (adopting a number already in use); `--reserve 900` moves next-free to 901 until `--release 900`. (3) `--prune` counts only UNSUFFIXED names as "published": a published `003b_` does not prune the reservation of an unmerged `003_`. (4) The gate trusts a LOCAL `mig/N` tracking ref as "existence as of the last sync" — a reservation another session released since is still honoured until the next fetch. (5) `--live` sees only prefixed live names (69 of 145 live rows are unprefixed), so a clean `--live` is partial coverage; the mint now says so instead of going quiet.

⚠ **What a reservation proves and does not.** It proves the author looked at the allocator: a `mig/N` ref EXISTS. It does **not** prove this branch owns N, it does **not** stop two branches sharing one reservation (Gate 14's same-number check at merge still catches that, as before), and it cannot see a raw apply that never registered a `schema_migrations` row (OI-223). Do not describe it as collision-free. The apply-time "refuse a number already live" check was cut from this batch after three plan-review rounds kept finding defects in it (live names are unprefixed, the ledger is a thin bridge, a live list is agent-supplied) and is **OI-272**.

## Ledger hash verification — Gate 39 (detail of the "IMMUTABLE" section)

**Since 2026-09-29 (OI-135 + OI-137) Gate 39 (`scripts/check_applied_migrations_ledger.dart`)
VERIFIES the hash** instead of only checking the key exists: shape must be `sha256:<64 hex>`
(or an `unverifiable:<reason>` sentinel, legal only for a migration with no `.sql` of its own,
e.g. `120b`, `123b`), and a real hash must equal the sha256 of the file under its **LF form OR
its CRLF form** (same content, either line ending — 56 old entries were hashed on a Windows
CRLF working copy and stay exactly as recorded). Logic: `scripts/migration_ledger_hash_lib.dart`
(pure Dart, no `package:crypto` — Gate 39 runs on every commit and a fresh worktree has no
`.dart_tool`).

**Write a ledger hash with `dart run scripts/migration_ledger_hash.dart <NNN|path>`, never a
raw `sha256sum`** — it hashes the LF form, so the answer is identical on every machine. Gate 39's
failure message prints the expected hash.

⚠ **What the gate does NOT catch, stated plainly:** an edit to an applied migration PLUS a
re-stamp of its hash in the SAME commit (migration 120 was re-stamped twice this way). It
catches the FORGOTTEN re-stamp, not the deliberate one. It also reads the WORKING TREE, not the
staged blobs, so with partial staging it can verify bytes that are not what gets committed (CI
verifies the committed tree). The rule above remains the guard against the deliberate case. The
dual-form test is also slightly WIDER than "same content, either ending": a file with MIXED endings
(e.g. `a\r\r\nb`) is accepted against the hash of the pure-LF applied file, because `toLf` collapses
only the final `\r\n`. Line-ending-only drift is the class Gate 39 tolerates by design; a lone `\r`,
an empty file and a missing trailing newline are handled exactly (a trailing-newline difference is
NOT accepted).

**Five historical drifts are grandfathered BY NAME with a pinned sha**
(`grandfatheredLedgerHashDrift` in the lib — closed list, never add): 057, 069, 070, 108, 123.
057/069/070's ledger hash is the honest as-applied value (it equals the CRLF form of the file at
the commit that introduced it) and the FILE moved afterwards — OI-91 (`49c1b7cd`) edited a
comment in each, and in 057 a `COMMENT ON INDEX` string literal, so a re-apply would write
different `pg_description` text. 108/123's as-applied bytes are unrecoverable (edited after
hashing, before their first commit). A pin makes any FURTHER edit fail; a pin that starts
matching the ledger fails as a stale exemption, so the list can only shrink.

⚠ **Convention conflict resolved.** Migration 120's ledger note says "The hash tracks the FILE,
so it moves when comments move; that is the convention." That is superseded: the hash is of the
file **as applied**, and a changed file must not be re-stamped to match. (The JSON note itself
is not edited — it belongs to an applied entry.)
