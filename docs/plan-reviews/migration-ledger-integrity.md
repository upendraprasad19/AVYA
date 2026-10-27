---
branch: migration-ledger-integrity
date: 2026-09-29
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/migration-ledger-integrity-bpass.md
---

# Plan — migration ledger integrity + migration-number allocator (OI-263, OI-137 step 1, OI-135)

**Status: CONVERGED. Plan-review rounds 1-3 (22 + 16 findings, then round 3's D8 defects) done; D8 (apply-time preflight) CUT at founder direction — see "Round-3 outcome"; B-pass round (two reviewers, 18 findings, all terminal) done — see "Round 4". Frontmatter flipped 2026-09-29 only AFTER the final verification: `flutter analyze lib/` (0 warnings/errors, info-level only), the complete pre-commit gate loop run SERIALLY (`PRE_COMMIT_GATE_JOBS=1`, rc 0) and the full suite (`TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`, 7205 passed, 0 failed). Two default-parallel loop runs each failed a DIFFERENT gate (`check_ai_tool_dispatcher_coverage`, then `check_unbounded_cron_reads`) that pass when run alone, at a machine load average of ~7-9 from other sessions; the serial run is clean — a load-contention inference, not a proven mechanism.** Earlier note, kept for history:
it flips only after two context-blind rounds (CLAUDE.md §4.12 pts 1+3). Tier is a PATH-based guess
until the files exist (see §4.9 fail-open row): re-classify after writing, and expect `platform`
because root CLAUDE.md and `scripts/pre-commit.sh`-adjacent machinery are touched.

**Execution mode (§4.12.7): INLINE, sequential, one session.** Rejected subagent-per-unit because
two concurrent `flutter test` runs corrupt each other on this VPS (OI-86), and the units share
`supabase/migrations/CLAUDE.md`, both boards and root `CLAUDE.md` (single writer = me).

## Ground truth measured this session (not inherited from OI prose)

1. `backups/applied_migrations.json`: **159 entries**, last = 151. 2 have non-hash sentinels
   (`120b` `unverifiable:no-artifact`, `123b` `unverifiable:folded-into-123`). 157 carry
   `sha256:<64hex>`; every one resolves to exactly one `supabase/migrations/*.sql` (prefix, plus
   `slug` for the 145/146 pairs). Nothing hashes a missing file.
2. Recomputing sha256 of the file bytes at HEAD: **96 match raw**, **56 match only after LF→CRLF**
   (hashed on a Windows CRLF working copy; content identical), **5 match neither**: 057, 069, 070,
   108, 123. `.gitattributes` = `* text=auto eol=lf`, so every checkout here is LF
   (`git ls-files --eol`: 171 × `i/lf w/lf`).
3. Of the 5: **057, 069, 070** — the ledger hash EQUALS the CRLF form of the file at the commit that
   introduced it (`4f74ed14`, `35005b31`, `06afc810`), and `49c1b7cd` (OI-91, "repair 138 dead
   CLAUDE.md §N citations") later edited a COMMENT in each. So the ledger is truthful about
   as-applied and the FILE moved (an immutability violation, comment-only). **108, 123** — one
   commit each, matches no variant I tried (LF, trailing-newline strip/add, CRLF): edited after
   hashing and before the first commit. Unrecoverable.
4. `mcp list_migrations` (live, project `dedsavbjuwgarrhphgnl`, 2026-09-29): 175 rows,
   `{version: 14-digit, name}`. **Names are NOT reliably number-prefixed**: ~60 have no numeric
   prefix at all (`alert_sql_job_failures`, `log_table_retention`, `hermes_pass_fixes_138_139`,
   `usage_counters` …), prefixed ones sometimes duplicate a number (`050_` ×2, `068_` ×2), and
   `045`/`044` are out of order. So "is N taken live?" CANNOT be answered from live names alone;
   the ledger (`slug` + `cloud_version`) is the number→live bridge. The OI-263 text assumed
   prefixed names — this corrects it.
5. Reuse target: `scripts/mint_oi.sh` (408 lines) — `refs/heads/oi/N` compare-and-swap, `gh api`
   on the laptop / `git push --force-with-lease=<ref>:` in the cloud, offline ⇒ refuse (exit 2).
   Its e2e harness (`test/scripts/mint_oi_e2e_test.dart`, bare origin + clones, `gh` shim) is the
   template. `vercel.json` `ignoreCommand` skips `oi/*` builds — `mig/*` needs the same.
6. `scripts/migrate_applied_migrations_ledger.dart:88-90` (the ledger WRITER) hashes RAW bytes.

## Corrections to Ground truth after round 1 (verified by me, not taken from the reviewer)

- GT3 was WRONG that 057/069/070 are "comment-only". 069 and 070 edits are `--` comments, but
  057's edit changed the string literal of a `COMMENT ON INDEX ... IS '...per CLAUDE.md §11.'`
  (line 146) — a re-apply would write different `pg_description` text. All three remain
  content-drift-after-apply; the ledger hash is the honest as-applied value.
- GT4 (175 live rows / ~60 unprefixed) was measured by me from the MCP listing, and is a
  point-in-time count; the design no longer depends on the number, only on the shape (names are
  not reliably number-prefixed). Ledger fields: 65/159 entries carry `slug`, 24 carry
  `cloud_version`, so the ledger alone is a THIN number→live bridge (F8) — the preflight adds an
  unaccounted-live-version leg for that reason.
- `package:crypto` is NOT in `pubspec.yaml` (transitive only; only the one-shot
  `migrate_applied_migrations_ledger.dart` imports it) and a fresh worktree has no `.dart_tool`.
  Gate 39 runs on every commit, so the hash lib must be pure Dart (F12).
- Filenames: three top-level timestamp-scheme files (`20260328000001_…`) and a `041_chunks/`
  SUBDIRECTORY (11 tracked files) sit in `supabase/migrations/`; letter-suffix precedents
  `050b_`, `068b_` exist. Any number parser must anchor (F1).
- `new-worktree.sh:69,73` and the SessionStart sync fetch only `oi/*`; nothing fetches `mig/*` (F4).

## Round-1 disposition (every finding terminal in THIS batch — no deferrals, §4.2)

| F | Sev | Disposition |
|---|---|---|
| F1 | P1 | ADOPTED — single anchored grammar `^[0-9]{3}[a-z]?_[^/]*\.sql$`, TOP-LEVEL basenames only, N = leading 3 digits. Ledger ids `^[0-9]{3}[a-z]?$`. Live names parsed only with `^[0-9]{3}[a-z]?_`. Fixtures: the 3 timestamp files, `041_chunks/`, `hermes_pass_fixes_138_139`. |
| F2 | P1 | ADOPTED — D9 rule split plain vs letter-suffix (below). |
| F3 | P1 | ADOPTED — any added path that already exists at `origin/main` is exempt (published). |
| F4 | P1 | ADOPTED — D9 does local refs → one bounded `ls-remote refs/heads/mig/*` (10 s) → SKIP; `new-worktree.sh` fetch line gains `+refs/heads/mig/*:refs/remotes/origin/mig/*`; SessionStart fetch line likewise. |
| F5 | P1 | ADOPTED — `--no-renames --diff-filter=A` (a `git mv 148→149` is A+D). `check_migration_ledger_paired.dart:63` shares the weakness: noted in its header and fixed the same way if its test allows; otherwise recorded on its OI (see F21). |
| F6 | P1 | ADOPTED — reservation commit subject `MIG-N \| branch B \| ts \| slug`; gate compares branch (else slug); mismatch = FAIL "reserved by another branch"; unknown branch (detached HEAD) ⇒ existence check only. |
| F7 | P1 | ADOPTED — preflight is SELF-ATTESTED on the MCP path (said plainly in docs); HARD on the script path: `.claude/apply_migration_via_api.js` calls it. Preflight also requires the reservation. `.claude/apply_migration_via_api.js` never registers a `schema_migrations` row, so live-list is blind to those (OI-223 class) — only the ledger leg sees them. |
| F8 | P1 | ADOPTED — leg (b): a ledger entry numbered N whose resolved file is not THIS file (or, unslugged + ambiguous, any) = taken. Added leg (d) unaccounted-live-version. |
| F9 | P1 | ADOPTED — freshness floor: snapshot max `version` ≥ max 14-digit `cloud_version` in the ledger (union of working tree and `origin/main`); parser tolerant of prose / `live-apply-…` cloud_version values (ignored); accepts bare array or `{"migrations":[…]}`; anything else exit 2. `--allow-reapply` for D8(c). |
| F10 | P1 | ADOPTED — grandfather map is name → PINNED current LF-normalised sha; drift beyond the pin fails; a pin that starts matching the ledger = stale exemption = fail. `hash_as_applied` rejected (CI `fetch-depth: 1`). Convention conflict RESOLVED to **"ledger hash = as applied; a changed file fails the gate"** — migration 120's ledger note ("hash tracks the FILE… moves when comments move; that is the convention") is superseded in `supabase/migrations/CLAUDE.md` (the JSON note itself is not edited: it is an applied entry). Consequence stated: a sweep that edits applied migrations' comments (like `49c1b7cd`) now FAILS the gate, which is the point. |
| F11 | P1 | ADOPTED — `scripts/migration_ledger_hash.dart <NNN[x]\|path>` prints the entry-ready hash; gate failure prints the expected normalised hash; CLAUDE.md `cp`+`sha256sum` recipe rewritten to use it; the one-shot writer also moved onto the lib. |
| F12 | P2 | ADOPTED — pure-Dart SHA-256 in the lib, pinned by NIST vectors AND a test asserting equality with `sha256sum` on a real migration. No `package:crypto`. |
| F13 | P2 | ADOPTED — `mint_migration.sh` writes NO file by default; `--stub` opt-in; default prints the four-tag header. |
| F14 | P2 | ADOPTED — Gate 39 moves `grandfathered` → `mutation_proven` in `gate_test_ledger.yaml` (precedent: `check_ai_tool_dispatcher_coverage`), test asserts a red path and names the gate. |
| F15 | P2 | NOTED/ADOPTED — no wiring edits: `pre-commit.sh:325` / `test.yml:234` glob `check_*.dart`; stage regenerated `GATE_INDEX.md`. D9 is vacuous on push-to-main by design (origin/main == HEAD). |
| F16 | P2 | ADOPTED — `docs/blast_radius.yaml` pins `mint_migration.sh`, `check_migration_number_reserved.dart`, `migration_apply_preflight.dart` + libs, `migration_ledger_hash*` as platform (mint_oi precedent, lines 219-224). Tier reason corrected: platform comes from root + migrations CLAUDE.md, not `pre-commit.sh`. |
| F17 | P2 | ADOPTED — update `.claude/commands/add-migration.md` and `.opencode/command/add-migration.md`; root §4.3 exemption line for the `mig/N` ref-create push; run `check_context_artifact_budget.dart` (root is 152,740 B). |
| F18 | P2 | VERIFIED CLEAN — readers of `hash` in `test/` assert only `isNotNull`; `supabase/functions/` has no ledger reference; nothing breaks on re-stamp. |
| F19 | P2 | ADOPTED — fixture rules in Units; the CRLF mutation needs an explicit `\r\n` fixture; `--reserve` exercised via BOTH transports (gh shim + git). |
| F20 | P2 | ADOPTED — parity test: extract `cas_write`/`sync_refs`/`bounded`/`delete_reservation` from both scripts, normalise `oi→mig`, `OI→MIG`, assert equal. D5 stays (no refactor of a load-bearing script). |
| F21 | P2 | ADOPTED — commits are `feat`/`chore`, not `fix:`; mutation evidence lives in this record's "Mutation evidence" section and the gate ledger `evidence:`. A closure file `docs/audit/migration-ledger-integrity.closure.yaml` is written (≥4 units). `closes-oi:` for OI-135/137/263. New test files spawning `dart`/`sh` carry `@Timeout` + `library;` and are run once inside the FULL suite. |
| F22 | mech | ADOPTED — D4 tightened; day-one hard-fail risk: no sibling branch adds a migration file on this machine (reviewer + me), laptop-only branches recover via `--reserve N slug`. |

## Round-2 verdict and what I did with it

Round 2 returned **NOT CONVERGED for the plan as a whole**: U1 converged modulo findings 1/6/7/8/15;
U2 had 3 NEW P1s (leg (d) refuses every apply today; leg (e) kills apply-after-merge; the branch
match false-FAILs the documented common state) — i.e. round 1's corrections introduced defects, the
§4.12.1 split signal. The reviewer recommended splitting the preflight into its own plan. **I am
NOT splitting yet**, because the founder scoped this batch as "all 3" (OI-135, OI-137, OI-263) and
the three P1s each have a concrete, data-checked correction. Instead the corrections REMOVE surface
rather than add it (branch match → WARN-only; JS applier hook and new-worktree/SessionStart refspec
changes dropped; re-stamp of 56 replaced by dual-form acceptance) and a **round 3** is dispatched
on the result. **If round 3 still finds NEW material issues in U2, U2's preflight (D8) is cut and
OI-263 is closed narrowed to reservation + gate only, with the preflight carried on OI-263's
still-open remainder under a fresh ×2 — that is the §4.12.1 escalation, decided in advance.**

Verified by me before adopting: 24 `cloud_version` values, **21** are 14-digit, 3 are prose; ledger
ids outside the 3-digit grammar are exactly the 3 timestamp ones; `check_migration_ledger_paired.dart:71`
uses `(\d{3,})_.*\.sql$` and so matches `041_chunks/041_00_alter.sql` (confirmed by reading the
regex). Reviewer-measured, not re-measured by me: live snapshot = 145 rows (my earlier "175" was
wrong), 124 live versions absent from the ledger `cloud_version` set of which exactly two (150, 151)
are newer than the ledger max, 34 unaccounted rows all predating 20260905071759.

## Round-2 disposition (numbering = round-2 report)

| # | Sev | Disposition |
|---|---|---|
| 1 | P1 | ADOPTED — resolver ≠ number-space grammar. `verifyLedger` resolves ANY ledger id as top-level `<id>_*.sql` (+ `slug` disambiguation), which resolves all 157; D7/D9 keep the anchored 3-digit grammar and simply exclude the 3 timestamp ids. Fixture includes the 3 timestamp entries. |
| 2 | P1 | ADOPTED — leg (d) replaced (D8 below): only live versions ≥ the ledger's earliest 14-digit `cloud_version`; accounted if version ∈ `cloud_version` set, OR name (`N_slug` / bare `slug`) equals a ledger `slug`, OR its `N` equals a ledger id. Backfill `cloud_version` for 146(second), 150, 151 is NOT done (applied entries are not edited beyond the hash convention; the rule does not need it — 150/151 are accounted by slug). Prose `cloud_version` ignored. |
| 3 | P1 | ADOPTED — (e) = `mig/N` exists OR N is published (origin/main tree or ledger) with THIS file's resolved name. |
| 4 | P1 | ADOPTED — branch match demoted to a WARN on STAGED additions only, never the range; `HEAD`/`detached`/unknown ⇒ silent. Reservation subject remains informational. Residue stated: two branches sharing one reservation are not blocked pre-merge (status quo; Gate 14 catches at merge). |
| 5 | P2 | ADOPTED — ls-remote fallback proves EXISTENCE only; stated in the gate header. |
| 6 | P2 | MOOT — no re-stamp (see 7). |
| 7 | P2 | ADOPTED, supersedes D2's re-stamp — the verifier accepts the file's hash under EITHER line-ending form (LF or CRLF of the same content). Zero churn to 56 applied entries; mismatch set = exactly the 5. New entries are written in the LF form (canonical CLI). Removes the whole "byte-identical JSON rewrite" risk. |
| 8 | P2 | ADOPTED as documentation — the gate catches forgotten re-stamps, NOT a deliberate edit + re-stamp in one commit (120 was re-stamped twice); the docs say so. The `restamped:` field / origin/main-hash-differs WARN is NOT adopted: it would flag every legitimate unapplied-then-applied file. Mutation (a) fixture re-stamps a pinned entry to the current file. |
| 9 | P2 | ADOPTED — every path check anchors on the FULL path `^supabase/migrations/[0-9]{3}[a-z]?_[^/]*\.sql$` (never `.split('/').last`). `check_migration_ledger_paired.dart:71` gets the same anchor + a test (it currently mis-reads `041_chunks/`). Preflight on a chunk/timestamp file: prints a note and exits 0 (skip), not 1. |
| 10 | P2 | ADOPTED — letter-suffix files: FAIL when `origin/main` holds a different file with the same FULL token (text before first `_`), reusing `migration_collision_lib.dart` + its `{145,146}` grandfather set; plus base-N published-or-reserved. |
| 11 | P2 | ADOPTED — dropped the SessionStart and `new-worktree.sh` refspec changes (the gate's ls-remote fallback covers cross-machine). `mint_migration.sh` carries its own `+refs/heads/mig/*` refspec. |
| 12 | P2 | ADOPTED — parity test anchors normalisation to `oi/`→`mig/` and `OI-`→`MIG-`, compares only `cas_write`/`sync_refs`/`bounded`/`delete_reservation`; `do_prune`/`next_free` excluded (they legitimately differ). |
| 13 | P2 | ADOPTED as honesty — NO `apply_migration_via_api.js` hook. Preflight is SELF-ATTESTED on both apply paths and documented as such. (The JS applier could fetch `schema_migrations` via the Management API; not adopted: it would add a Node→Dart pipe and still not see raw applies.) |
| 14 | P2 | ADOPTED — a test pins that re-applying either 145 file is NOT "held by a different file" (imports `grandfatheredMigrationCollisionPrefixes`). |
| 15 | mech | ADOPTED — GT numbers corrected (145 live rows, 76 prefixed / 69 unprefixed, 21 of 24 14-digit); Gate 39 keeps its name in `check_gate_test_ledger.dart:37`'s grandfather set and only the `gate_test_ledger.yaml` entry is swapped (precedent: `check_ai_tool_dispatcher_coverage`); `.claude/skills/update-docs/SKILL.md:79` updated; `check_context_artifact_budget` run for `supabase/migrations/CLAUDE.md` as well as root. |
| 16 | – | Artifacts check: no Gate 33 / plan-record rejection expected; closure YAML kept. |

## Round-3 outcome (founder direction: cut the preflight)

Round 3 (context-blind) confirmed U1's dual-form hash verification and D7 against real data and
found NEW material defects only in D8: (2a) the 145/146 exemption was stated for leg (b) only, so
leg (a) still refused the 145/146 files even with `--allow-reapply`; (2b) leg (d) refuses whenever a
sibling branch has applied live but not merged (an undocumented serialisation); (2c) "N" is
undefined for letter-suffix files across legs (a)/(b)/(c)/(e). Third consecutive round in which the
previous round's corrections created defects in exactly this piece — the §4.12.1 split signal.
**Founder chose to CUT D8.** This is a §4.12.1 split-and-ship, decided at plan time (not a
mid-batch deferral): the preflight is removed from THIS batch's scope and given its own OI and its
own ×2 review. OI-263 is closed for what ships (mint, reservation gate, vercel ignore, docs); the
new OI carries the apply-time/live-reconciliation design, with round-3's 2a-2d and the "live list
is agent-supplied, half the live names are unprefixed" findings as its starting evidence.

Removed from scope: D8, `migration_apply_preflight.dart` + lib, mutations (h)-(m) and their
blast pins, and D8 references in D6/D9. Also dropped: the D9 branch-mismatch WARN (unobservable —
`pre-commit.sh` runs every `check_*.dart` with output to /dev/null and CI has no staged set).

Round-3 corrections adopted:
- **5a (P1):** `check_migration_ledger_paired.dart` — ledger-side extractor (`^(\d{3,})`, ~line 118)
  moves to the SAME grammar as the staged-path regex so `152b_x.sql` + ledger id `152b` pair.
- **5b (P2):** the pairing gate keeps `[0-9]{3,}[a-z]?` (timestamp-scheme adds still require a
  ledger entry); only the `[^/]*` full-path anchor is added. The 3-digit grammar is for number
  ALLOCATION (D7/D9), not for pairing.
- 5c: no test exists for that gate — the new test builds a scratch git repo and runs it with a
  temp cwd. 5d: Gate 39 reads the working tree, not staged blobs (OI-72 class) — documented limit.
- D2 text: pins are of the `\r\n`→`\n` normalised content; the stale-pin check compares the pin
  against BOTH the LF and CRLF sha of the ledger hash side.
- D9: optional hard-FAIL when the reservation subject's slug differs from the file slug is NOT
  adopted (slugs are renamed during review); documented instead. Documented residuals: the gate
  enforces "a reservation exists", not "this branch owns it" — collision prevention at merge stays
  with Gate 14 (`migration_collision_lib`); stale local `origin/main` can false-FAIL a file whose
  `mig/N` was pruned (unlikely; documented).
- D9 early-exits when no migration file was added (skips `ls-remote`, one Dart VM per commit).
- Closure YAML is created only when every item is terminal (§4.10). 3 OIs + new preflight OI:
  OI-135 / OI-137 / OI-263 closed_in_commit; the preflight OI is filed and OPEN — its terminal
  state in the closure file is `blocked_on_user` is NOT used; it is an independent OI, not a batch
  finding, so it does not appear in the closure YAML.

## Decisions (revised again — this is the authoritative text)

- **D1 — normalisation:** sha256 over the file content, pure-Dart. Two canonical forms: LF
  (`\r\n`→`\n`) and CRLF (LF form with `\n`→`\r\n`). **A ledger hash is valid iff it equals the
  file's LF form OR CRLF form.** New entries use the LF form.
- **D2 — NO re-stamp.** The 56 stay byte-for-byte as recorded (they are as-applied records and
  now verify). The 5 (057, 069, 070, 108, 123) are grandfathered as name → PINNED current LF sha
  (closed list, never add). Pin drift fails; a pin that starts matching the ledger = stale
  exemption = fail. Founder veto flagged at merge.
- **D3 — extend Gate 39** (thin caller of `migration_ledger_hash_lib.dart`); rule-24 ledger entry
  swapped to `mutation_proven`, name stays in the script's grandfather set.
- **D4 — hash grammar.** `^sha256:[0-9a-f]{64}$` verified against the resolved file (D1 dual form);
  or sentinel `^unverifiable:[a-z0-9-]+$` legal ONLY for a migration with no `.sql` of its own
  (`120b`, `123b`). Resolver: any id → top-level `<id>_*.sql`, `slug` disambiguates; real hash + no
  file = violation; several candidates and no slug = "ambiguous" violation; sentinel beside a file
  = violation.
- **D5 — sibling CAS core in `mint_migration.sh`, parity-tested (round-2 #12 scoping).**
- **D6 — number space:** `refs/heads/mig/N`, N a positive integer, printed `%03d`; letter suffixes
  not mintable.
- **D7 — next free = 1 + max(N)** over anchored top-level basenames (full-path grammar) at
  `origin/main`, local `main` (absent ⇒ empty), working tree; ledger ids matching
  `^[0-9]{3}[a-z]?$` (timestamp ids excluded) at `origin/main` and working tree; live names matching
  `^[0-9]{3}[a-z]?_` when `--live` supplied; every `refs/remotes/origin/mig/*`. stderr NOTE when live
  not consulted. Own refspec `+refs/heads/mig/*:refs/remotes/origin/mig/*`.
> **CUT — D8 and the D9 branch-mismatch WARN are NOT part of this batch** (see "Round-3 outcome";
> carried on OI-272). The D8 text below is retained only as OI-272's starting evidence.

- **D8 (CUT → OI-272) — `scripts/migration_apply_preflight.dart <file> --live <json> [--allow-reapply]`**
  (self-attested on every apply path; stated). Refuses when: (a) a live name `N_<slug'>` has slug' ≠
  the file's slug; (b) the ledger (working tree ∪ `origin/main`) holds N under a different resolved
  file (145/146 exempt via the imported set, pinned by a test); (c) the file's own slug is already
  live (unless `--allow-reapply`); (d) an UNACCOUNTED live row exists among versions ≥ the ledger's
  earliest 14-digit `cloud_version` — accounted = version ∈ `cloud_version` set OR name matches a
  ledger `slug` OR its `N` equals a ledger id (prose `cloud_version` ignored); (e) neither `mig/N`
  exists (local ref, else bounded ls-remote; unreachable ⇒ refuse) NOR N is published with this
  same file; (f) freshness floor: snapshot max `version` ≥ ledger max 14-digit `cloud_version`.
  Chunk/timestamp file ⇒ note + exit 0. Exit 0 ok / 1 refuse / 2 unusable input (missing or
  unparseable live file NEVER passes). Accepts a bare array or `{"migrations":[…]}`.
- **D9 — `scripts/check_migration_number_reserved.dart`** (new `check_*`, rule 24). Inputs: ADDED
  files (`--no-renames --diff-filter=A` over `origin/main...HEAD` ∪ staged), full-path grammar
  only. Skip paths already at `origin/main`. Plain-N: FAIL if `origin/main` holds a different file
  with the same full token (collision lib), else require `mig/N` (local ref → bounded ls-remote →
  SKIP; existence only). Letter-suffix: same-token collision FAIL + base N published or reserved.
  (Branch-mismatch WARN: CUT — unobservable at pre-commit.) Offline ⇒ SKIP naming which check. Hard-fail on
  day one (no baseline: only added files are inspected).
- **D10 — no default stub; `--stub` opt-in** (default prints the four-tag header).
- **D11 — Vercel `ignoreCommand`:** `oi/*|mig/*`.

## Units (inline; U1 first)

**U1 — hash verification (OI-137 step 1, OI-135).** `migration_ledger_hash_lib.dart` (pure
SHA-256, dual-form verify, grammar, grandfather map, resolver) + `migration_ledger_hash.dart` CLI;
Gate 39 delegates; one-shot writer delegates; NO ledger edits except nothing (0 lines);
`check_migration_ledger_paired.dart` full-path anchor + test; tests (NIST vectors, `sha256sum`
parity, CRLF fixture with explicit `\r\n`, the 3 timestamp ids, ambiguity, sentinel-beside-file,
stale exemption, pin drift) + gate e2e; docs (`supabase/migrations/CLAUDE.md` immutability +
convention resolution + the limit of the guarantee + restore recipe; `update-docs/SKILL.md`);
gate-ledger entry; OI-135/137 closed.

**U2 — allocator (OI-263).** `mint_migration.sh` (+ parity test), ~~preflight (+ lib)~~ (CUT → OI-272),
`check_migration_number_reserved.dart` (+ lib, ledger entry), `vercel.json`, blast pins,
`add-migration.md` ×2, `supabase/migrations/CLAUDE.md` section, root §4.3 exemption + §7 row,
OI-263 closed. Fixtures use REAL live names (unprefixed, duplicate `050_`). Test hygiene as before
(renamed seam env scrubbed, `.gitattributes *.sh text eol=lf` in seed, `@Timeout` + `library;`, full
suite run once).

## Mutation plan (rule 21 — RUN; counts go under "Mutation evidence")

Hash lib: (a) stale-exemption removed [fixture re-stamps a pinned entry], (b) sentinel accepted
beside a file, (c) CRLF-form acceptance removed [expect 56-entry fixture red], (d) LF-form
acceptance removed, (e) shape regex loosened, (f) pin compare removed, (g) resolver anchored to
3 digits [timestamp fixture red]. Preflight (h)-(m) [CUT → OI-272, none run]: ledger leg removed, missing live file → 0,
unaccounted-live leg removed, freshness floor removed, reservation-or-published requirement
removed, 145/146 exemption emptied. Gate: (n) published-skip removed, (o)
same-token collision removed, (p) offline → FAIL, (q) `--no-renames` dropped, (r) full-path anchor
loosened to basename [chunk fixture red]. Mint: (s) CAS → plain push, (t) `--release` published
guard removed, (u) grammar unanchored `[0-9]+` [timestamp file makes `--next` wrong]. Each: confirm
APPLIED (`grep -c`), still compiles, failure message READ.

## Mutation evidence

Every mutation was APPLIED (token confirmed by grep), the tree restored from a backup copy (never
`git checkout`, which rewrites CRLF/LF), and each red READ — none was a compile error. Counts are
tests red across the batch's test files.

| Leg | Mutation | Red |
|---|---|---|
| Gate 39 a | stale-exemption check removed | 2 |
| b | sentinel accepted beside an existing file | 2 |
| c | CRLF-form acceptance removed | 5 |
| d | LF-form acceptance removed | 12 |
| e | shape regex loosened to `sha256:.+` | 7 |
| f | grandfather pin compare removed | 2 |
| g | resolver anchored to 3 digits | 5 |
| h | gate `main()` not calling `verifyLedgerHashes` | 5 |
| i | grandfather map emptied at the call site | 6 |
| paired j | chunk anchor loosened to `.*` | 1 |
| k | letter suffix dropped from the staged regex | 1 |
| l | ledger extractor dropping the suffix | 1 |
| reserved m1 | published-skip removed | 2 |
| m2 | same-token collision removed | 3 |
| m3 | 145/146 grandfather set emptied | 1 |
| m4 | letter-suffix base-published leg removed | 3 |
| m5 | `--no-renames` dropped | 1 |
| m6 | offline treated as violation | 2 |
| m7 | chunk-dir anchor loosened | 3 |
| m8 | ls-remote fallback removed | 6 |
| m9 | staged adds ignored | 7 |
| m10 | committed range ignored | 1 |
| mint m11 | CAS lease (`--force-with-lease`) dropped | **2, parity test ONLY** — every behavioural e2e stays green, because a non-fast-forward reject is also classified as "taken". The parity test is the sole guard; stated plainly rather than papered over. |
| m12 | `--release` published guard removed | 1 |
| m13 | mint grammar unanchored (`[0-9]+`) | 16 |
| m14 | `pid $$` removed from the reservation commit message | 1 |
| m15 | `--reserve` published check removed | 1 |
| B-pass m16 | `all_branch_numbers` reads local heads only (old) | 1 |
| m17 | `--prune` uses the suffix-inclusive published set (old) | 1 |
| m18 | failed committed-range diff silently ignored (old empty-set PASS) | 1 |
| m19 | `--live` partial-coverage NOTE removed | 1 |
| B-pass round 2 n1 | `write_stub` no-clobber guard off | 1 |
| n2 | `contains_line` exact-line `-x` off (`--release 15` beside a `150` file) | 1 |
| n3 | 999 exhaustion guard off | 1 |
| n4 | give-up after MAX_ATTEMPTS off (hook is counter-bounded, so a mutant fails an assertion instead of hanging) | 1 |
| n5 | mid-retry `sync_refs` failure ignored | 1 |
| n6 | explicit local tracking-ref update off (narrow-refspec clone) | 1 |
| n7 | API-transport post-mint prune off | 1 |
| n8 | `--next` working-tree ledger leg off | 1 |
| n9 | `--next` origin/main tree leg off | 1 |
| g1 | gate: `--no-renames` dropped from the RANGE diff | 1 |
| g2 | gate: three-dot -> two-dot | 2 (F2 test + orphan-branch test) |
| g3 | gate: local reservation refs ignored (always ls-remote) | 1 |
| l1 | hash lib: grandfather pin compared on RAW bytes | 1 |
| l2 | hash lib: resolver drops the `.sql` filter | 1 |
| l3 | hash lib: non-String `hash` classified real | 3 |
| l4 | reservation lib: `mig/N` regexp loses its end anchor | 1 |
| l5 | reservation lib: base-published ignores origin/main FILES | 1 |
| c1 | CLI hashes RAW bytes | 1 |
| c2 | CLI: ambiguous id no longer refused | 1 |

Test counts, run individually after the second B-pass round: hash lib 51, hash CLI 4, Gate 39 e2e 9,
paired e2e 7, mint e2e 34, parity 7, reservation lib 21, reservation e2e 17 (150 in the eight files;
baseline green immediately before the round-2 mutation run, restored files byte-identical after).

## Round 4 — B-pass (two context-blind reviewers; every finding terminal in THIS batch, §4.2)

Reviewer A (read-only lenses 1-5, 7, 10 + hash/SHA/mint semantics): 10 findings. Reviewer B (mutation
lenses 6 and 8, isolated worktree, ~70 mutations): 8 findings. I verified each against the code before
acting; both reports' claims about the hash core, paired gate, collision/grammar guards and the real
ledger/tree data reproduced exactly (159 entries = 157 real + 2 sentinels; 96 LF-only, 56 CRLF-only,
5 neither; the 5 pins each equal the current LF sha).

| Finding | Sev | Disposition |
|---|---|---|
| A1 remote-only branch looked unfiled (`--release`/`--next`) | P2 | FIXED — `all_branch_numbers` reads remote-tracking branches too; e2e + m16. Residual (clone's last fetch bounds it) documented. |
| A2 platform tier's `feature_flag` unmet; paired gate unpinned | P2/P3 | DEVIATION STATED (Residual risks) for founder veto; paired + ledger-writer script pinned platform. |
| A3 closure count 21 vs 20; lease claim pointed at a section that did not exist; evidence placeholder | P2 | FIXED — counts re-derived by running; this section written. |
| A4 failed range diff read as "no adds" PASS | P3 | FIXED — SKIP naming the unchecked leg; m18. |
| A5 stale local tracking ref trusted | P3 | ACCEPTED as the contract (existence at last sync), documented in the gate header + migrations CLAUDE.md; Gate 14 is the merge-time backstop. |
| A6 `--reserve` unbounded | P3 | ACCEPTED, documented (header + CLAUDE.md); `--release` undoes it. |
| A7 `--prune` treated `003b` as publishing `003` | P3 | FIXED — `published_base_numbers`; m17. |
| A8 mixed line endings tolerated by the dual form | P3 | ACCEPTED, documented (migrations CLAUDE.md). |
| A9 plan record still specified cut D8 material | P3 | FIXED — marked CUT in place. |
| A10 `--live` reads as full coverage; §4.9 `ls` recipe; `new-worktree.sh` lacks `mig/*` | P3 | FIXED all three (the `new-worktree.sh` edit was claimed in round 1's F4 and never landed). |
| B1 committed `git mv` dodges the RANGE `--no-renames` | P2 | FIXED — test g1. |
| B2 three-dot -> two-dot undetected | P3 | FIXED — test g2. |
| B3 `write_stub` no-clobber untested (the test never reached it) | P2 | FIXED — adoption test n1; misleading tail comment corrected. |
| B4 `contains_line -x` untested | P3 | FIXED — n2. |
| B5 nine untested mint guards (give-up, 999, mid-retry, tracking-ref, API prune, `--next` legs) | P3 | FIXED — n3-n9 each mutation-proven. The CAS lease stays PARITY-ONLY (see m11) — accepted and stated; the parity test also pins the literal `--force-with-lease="refs/heads/mig/$1:"` independently of `mint_oi.sh`. |
| B6 pin compared on raw bytes / resolver `.sql` filter / null hash untested | P3 | FIXED — l1, l2, l3. A5/A6b are lib-only by design (accepted). `all_*` exclusion is defence-in-depth for a contrived id (accepted). |
| B7 `mig/4x` regexp, base-from-files leg, local-first path untested | P3 | FIXED — l4, l5, g3. |
| B8 stale `61 of 147`; record not flipped; paired/migrate unpinned; CLI never run by a test | P3 | FIXED — denominators corrected to 61 of 157 real hashes, both scripts pinned, new `migration_ledger_hash_cli_test.dart` (c1, c2). Frontmatter flip below. Not verifiable by B without live access: the "69 of 145 live rows unprefixed" figure — it is my own `list_migrations` measurement from earlier this session, stated as measured, not re-derived here. |


## Residual risks stated plainly

- **Platform tier's `requires: feature_flag` is NOT satisfied by a switch — a deliberate, stated
  deviation (B-pass F2), flagged for founder veto at merge.** Nothing enforces that requirement
  mechanically (`check_blast_radius_coverage.dart` does not read the list). The two gates are
  ADDITIVE checks that fail OPEN on any uncertainty (offline, no `origin/main`, git failure => SKIP
  naming what was not checked), Gate 39's new hard-fail rests on 159 real ledger rows that all
  verify today, and the rollback is a revert of this branch. A marker-file kill switch was
  considered and not added: a switch on an integrity gate is exactly the lever that lets the
  original defect back in silently, and the hook-bypass flag already exists behind a founder-approval
  requirement (§4.3). `--warn-only` is a debugging aid, not a rollback path — pre-commit and CI
  never pass it.

- Preflight and `--live` are agent-supplied ⇒ self-attested on both apply paths; raw applies
  (OI-223 class) are invisible to the live legs, visible only to the ledger legs.
- The hash gate catches a FORGOTTEN re-stamp, not a deliberate edit + re-stamp.
- D9 day-one hard-fail could hit a laptop-only unpushed branch; recovery `--reserve N <slug>`.
- Two branches sharing one reservation are not blocked pre-merge (status quo).
- Founder veto pending on D2 (5 grandfathered by pinned name).
