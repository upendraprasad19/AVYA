# Design — OI-number allocator (reservation branches on the GitHub remote)

**Date:** 2026-09-12
**Branch:** `oi-allocator`
**Blast-radius:** `platform` — `scripts/check_oi_numbering_unique.dart`, `scripts/discipline_hook.dart`
and the new `scripts/mint_oi.sh` are review/blast-radius machinery, individually pinned `platform` in
`docs/blast_radius.yaml`.
**Review requirement:** FULL ×2 context-blind + `bpass: accepted`. Not ship-dark (no flag; the gate
change is live on every board-touching commit).
**Closes:** OI-176 (the vacuous-PASS hole). Supersedes nothing — OI-112 stays closed; this adds the half
it explicitly left open (*"two sessions on two branches each picking 'the next free number' still both
…"*, `docs/audit/closed_issues.md`, OI-112).

---

## 1. The problem, in ground truth

OI numbers are the board's permanent identifiers (`docs/audit/open_issues.md:9-11`, cited from
diagnose-docs, `closes-oi:` commit trailers, memory files, CLAUDE.md). They are minted **by eyeballing
the board's tail** — `scripts/build_oi_index.dart:110-111`: *"There is no allocator."* Every session
reads its local board, sees the max, and types max+1. Two sessions on two branches do that
independently, the additions land in different regions of one file, git merges them cleanly, and one
number names two issues.

What exists is a **detector**, `scripts/check_oi_numbering_unique.dart`, in three placements:
pre-commit (advisory), pre-merge-commit, CI. Two of the three are *late* — the number is already
committed and the repair is a renumber commit whose predecessors still cite the old number. The
early one is **vacuous in exactly the state where numbers get minted** (OI-176, filed 2026-09-08):
a fresh worktree with zero commits has `HEAD` = a merge commit on `main`, the gate dispatches on that
shape and compares `HEAD^1` vs `HEAD^2` — two ancestors of the branch point — and prints
`PASS … this is a checked answer, not a skipped one`. The staged board is never compared.

Collision history (board + `git log`): OI-100..105 (six at once, 2026-08-13), 106-108 → 125-127,
128 → 130, 167-169 (three-way, 2026-09-08), and 177/178 (`regen-wave-unit2` vs `main`, different
titles — found by hand and renumbered to 186/187 in `de52f1e8` on 2026-09-12, **the sixth manual
renumber**, while this spec was being written). During this design's own spike another session merged
`a50f260a` filing OI-185 while this session held "next free = 185" in context. Board max on `main` at
spec-commit time is **188**; the first mint will therefore be 189.

**The fix has to be an allocator, not a third detector.** Sequential integers require a single
allocation point; every tracker that has them (GitHub, Jira, Linear, Rust RFC = PR number) has one.
Every git-native tracker without one abandoned integers for hashes. This repo already did that for
diagnose-docs (6-hex ids) and for gates (rule 24: filename is identity). The OI board is the one
numbered registry still minting by hand, and its numbers are too widely cited to change scheme.

## 2. Decisions locked (2026-09-12, founder-approved)

| # | Decision | Why |
|---|---|---|
| Q1 | Sessions run on the laptop (worktrees sharing ONE `.git/`) **and** on claude.ai/code (cloud clone, own `.git/`). | A laptop-local ledger cannot see a cloud mint. The allocator must live on the one thing both share: the GitHub remote. |
| Q2 | git's own ref store IS the local layer. Sync = `git fetch`. Write = a server-side compare-and-swap. **Offline ⇒ minting refuses.** | Read-then-write across two machines is not atomic; only the remote CAS is. A local-only mint is a promise the remote has not seen. Everything else stays fail-open; only the mint is fail-closed. |
| Q3 | Design approved in principle; spikes authorised. | — |
| Q4 | Reservation namespace = **`refs/heads/oi/N`** (a branch), name EXACTLY `oi/N`. | Cloud credential: push to `refs/oi/*` → **HTTP 403 from GitHub**; push to `refs/heads/oi/spike-cloud` → `[new branch]`. Laptop `gh api POST /git/refs` of the same name → **422 Reference already exists** (cross-path CAS proven). A slug suffix would let two mints of N both succeed. |

Spike artefacts were deleted; `refs/oi/*`, `refs/heads/oi/*`, `refs/heads/claude/oi/*` are all empty on
the remote as of this writing.

**Rejected, with the reason, so nobody re-explores:**
- Local `.git/oi_ledger` file (blind to cloud; second source of truth to keep in sync).
- Hex / draft IDs renumbered at merge (every `OI-\d+` regex, `closes-oi:` gate, memory and diagnose
  citations; draft numbers unstable for weeks on long-lived branches like `regen-wave-*`).
- GitHub Issues as allocator (issues + PRs share one sequence; repo max is **#23** — would collide with
  160+ existing OI numbers; an offset is a second numbering scheme).
- `refs/oi/*` bare refs (cloud 403).
- A pre-push hook skip path for reservation pushes, or a hook-bypass flag baked into the mint script.
  Not needed: the laptop writes through the API (no `git push`, no hook); the cloud has no hooks
  installed. `scripts/pre-push.sh:38-41` ("do not fix" the tag-only analyze) stays untouched.

## 3. Design

### 3.1 The reservation

A reservation for number N is the remote branch `oi/N` pointing at a **parentless commit whose tree is
`origin/main`'s tree** and whose message is the ledger line:

```
OI-186 | branch oi-allocator | 2026-09-12T11:58+05:30 | <title as given>
```

- Branch, not bare ref: the only namespace the cloud credential can write (Q4).
- Orphan commit, `origin/main`'s tree: zero object upload (the tree already exists on the server —
  avoids the open question of whether GitHub materialises the empty tree `4b825dc…`), yet the commit
  message carries *who/when/what*, readable with `git log -1 origin/oi/186`.
- The **board remains the single source of truth for content**; the branch is a name reservation plus
  a provenance line. Titles on the board may be edited freely; the ledger line is a snapshot.
- Reservations are pruned once their number is on `origin/main`'s board (§3.2 `--prune`); an orphan
  reservation (minted, never filed) burns one number — gaps are already tolerated (18→21, 21→23).

### 3.2 `scripts/mint_oi.sh` — the allocator

POSIX `sh` + `git` (+ `gh` when present). Deliberately not Dart: the cloud image is not guaranteed a
Dart SDK, and a mint must work anywhere the repo can be cloned.

```
sh scripts/mint_oi.sh "<title>"            # reserve next free N, append a board stub, print OI-N
sh scripts/mint_oi.sh --no-append "<title>" # reserve + print only
sh scripts/mint_oi.sh --reserve N "<title>" # claim EXACTLY N (migration of in-flight numbers); fails if taken
sh scripts/mint_oi.sh --prune               # delete oi/N branches whose N is on origin/main's boards (laptop only)
sh scripts/mint_oi.sh --release N           # delete an UNFILED reservation (an orphan) — never a filed one
sh scripts/mint_oi.sh --next                # read-only: print next free N after a sync (humans + cloud)
```

Algorithm (`<title>` form):
1. **Sync.** `git fetch --quiet origin '+refs/heads/oi/*:refs/remotes/origin/oi/*' --prune` and
   `git fetch --quiet origin main`, bounded by coreutils `timeout 30` where present. Failure ⇒ **exit 2
   "cannot reach origin — an OI number cannot be reserved offline; nothing was written."** No fallback.
2. **Candidate.** `N = 1 + max( highest origin/oi/* , highest OI on origin/main's open+closed boards ,
   highest OI on LOCAL main's boards when that ref exists (§4.13's merged-but-unpushed state) ,
   highest OI on the current working board )`. The board terms are the bootstrap (185 today) and the
   guard against any hand-typed number that landed before this shipped; once reservations are universal
   the branch term dominates.
3. **Ledger commit.** `git commit-tree "$(git rev-parse origin/main^{tree})" -m "OI-N | branch … | …"`
   (local object; pushed only on the git transport).
4. **CAS write**, transport chosen by `command -v gh`:
   - **API (laptop):** `gh api POST /repos/:o/:r/git/commits {message, tree, parents: []}` then
     `gh api POST /repos/:o/:r/git/refs {ref: refs/heads/oi/N, sha}`. 422 on the ref ⇒ taken.
   - **git (cloud, or laptop without gh):** `git push --force-with-lease=refs/heads/oi/N: origin
     <sha>:refs/heads/oi/N`. Empty `<expect>` = *"must not exist"*; receive-pack enforces old-sha = 0
     under the ref lock. Rejection ⇒ taken. (Laptop note: this transport runs `pre-push.sh` — analyze,
     possibly the suite; that is why the API is preferred there, and the script says so when it falls
     back.)
5. **Taken ⇒ re-sync, N+1, retry** — at most 10 attempts, then exit 3 with the last error verbatim.
6. **Success ⇒** make the reservation visible locally so sibling laptop worktrees see it without their
   own fetch: git transport → `git update-ref refs/remotes/origin/oi/N <sha>` (the object is local);
   API transport → `git fetch --quiet origin +refs/heads/oi/N:refs/remotes/origin/oi/N` (the commit was
   created server-side and does NOT exist locally — `update-ref` would refuse an unknown object). Both
   are BEST-EFFORT: the reservation already exists on the remote, so a transient ref-lock must not abort
   before the stub — that is exactly how an orphan is made. Then append the stub unless `--no-append`,
   print `OI-N`, then best-effort `--prune` when `gh` is present (never affects the exit code).

Board parsing inside the script is `grep -oE '^## OI-[0-9]+'` over `git show origin/main:<board>` for
both boards — the ASCII prefix only, which is immune to the em-dash mis-decoding that once blanked the
Dart gate (`check_oi_numbering_unique.dart:53-60`). The script never needs a title, so it never parses
one. Author identity for the ledger commit is pinned (`GIT_AUTHOR_NAME=mint_oi`, same for committer) so
a clone without `user.name` configured still mints; provenance is in the message, not the author.

**Test seam:** `MINT_OI_TEST_HOOK_BEFORE_PUSH` — when set, its value is run with `sh -c` between the
sync and the CAS write, and nowhere else. A no-op unless set; exists so a test can create `oi/N` on the
remote *inside* the window and prove the retry, which no sequential test can otherwise reach.

Board stub (every field `build_oi_index.dart:39` requires, so the index gate stays green):
```
## OI-N — <title>

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: <YYYY-MM-DD> · filed via mint_oi.sh from branch <branch>
```
Appended at the end of the file; the board already follows an append-only-at-the-bottom rule
(`open_issues.md:9`).

`--prune` is laptop-only by construction (API delete; the git transport would pay the pre-push hook per
branch). It deletes `oi/N` iff N appears as a `## OI-N` heading on `origin/main`'s open **or** closed
board (the sh equivalent of the Dart lib's `mergeBoards`) — never on a local board, never by age. It is idempotent and safe by construction: a number on `main`'s
board is permanent.

### 3.3 Gate changes — `scripts/check_oi_numbering_unique.dart`

Two additions; existing merge-shape arms and Check A untouched.

**Check B′ — the working-tree arm (closes OI-176).** When the working-tree open board differs from
`HEAD:docs/audit/open_issues.md`, run the SAME three-point predicate (`findCollisions`) with
`head := working-tree boards`, `base := merge-base(HEAD, origin/main)` boards, `mainline :=
origin/main` boards. Dispatch on *"is the board being changed"*, not on `HEAD`'s shape. This is the
proposed repair in OI-176's own entry. Runs in addition to (not instead of) the HEAD-shape arm, so the
pre-merge-commit and CI placements keep their current behaviour.

**Check C — every minted number is reserved.** `mintedHere = other-side keys − base keys`, where the
other side is the working tree in the working-tree/branch arms and the merged-in branch in the merge
arms. **Where it is meaningful, per shape (review round 1):** pre-commit (working-tree and branch
arms — the mint moment), `pre-merge-commit` (mid-merge arm — the backstop for every cloud branch,
which has no hooks), and CI on a **PR** (`origin/main` ≠ the PR head). At CI on a push to **main** it
is VACUOUS by construction: `origin/main` == `HEAD`, so every number is "published" and exempt
(below). That is correct — after publication `--prune` may already have deleted the reservation, so
checking there would produce false reds. For each n not already on origin/main's current boards:
1. local `refs/remotes/origin/oi/n` present ⇒ reserved;
2. else, **only if some minted number lacks a local ref**, ONE `git ls-remote --refs origin
   'refs/heads/oi/*'` for the whole namespace (no `--exit-code` — with it an empty namespace is
   indistinguishable from a failure), bounded at 10 s (a bare `ls-remote` over this SSH remote measures
   2.9–3.2 s; a cold handshake crossing 5 s would skip the one check no later placement repeats) ⇒
   reserved / not reserved;
3. network failure or timeout ⇒ **UNDETERMINED → SKIPPED (reservation check)**, exit 0, never PASS —
   and the message says plainly that NOTHING re-checks this number once it is published (the exemption
   makes every later placement vacuous), so the repair is `--reserve N` now. At CI on a PR,
   `actions/checkout` with `fetch-depth: 0` (`test.yml:219`) fetches every branch, so step 1 answers
   without network there.

When the check cannot complete, the final line says **`SKIPPED (reservation check)`** and states that
the collision check ran — the two facts are tracked separately, and the vacuous collision `PASS` line
is suppressed whenever a reservation FAIL or SKIP is the verdict of the run, so no run prints `PASS`
and `SKIPPED` together.

Not reserved ⇒ **FAIL** with the repair spelled out:
```
OI-186 is on this board but has no reservation (no origin/oi/186).
  Numbers are allocated, not eyeballed: sh scripts/mint_oi.sh --reserve 186 "<title>"
  If that reports TAKEN, someone else holds 186 — renumber with: sh scripts/mint_oi.sh "<title>"
```
Ownership (the ledger's `branch …` field) is **reported, not enforced** — see §7 residue 1. Adopting an
ORPHAN reservation by hand-typing `## OI-N` passes — the gate bans unreserved numbers, not hand-typing.
The collision FIX text no longer says "next free is OI-N" (an eyeballed number); it prescribes
`mint_oi.sh`.

Ledger: `docs/audit/gate_test_ledger.yaml:434` entry gets its `evidence:` extended with the new
mutations (§6); no new gate file, so rule 24's "new gate" clause does not apply, but rule 21's
mutate-and-run clause does.

### 3.4 SessionStart line — `scripts/discipline_hook.dart:105-118`

On every SessionStart source, best-effort and fail-open (any error ⇒ silent), computed **in Dart from
LOCAL refs only** — `refs/remotes/origin/oi/*`, `refs/remotes/origin/main`'s boards, the working board —
via the shared `oi_numbering_lib.dart`. **No fetch.** §7.4 below set the rule at 2 s; review round 1
measured a bare `ls-remote` over the SSH remote at 2.9–3.2 s, on every SessionStart source including
`compact`, so the rule fired before the code was written. (Not `sh scripts/mint_oi.sh --next` either:
`sh` is not guaranteed on the PATH of a Dart process the harness starts on Windows; `--next` stays in
the script for humans and the cloud.) The line:

```
OI board: next free number is at least 186 (as of the last sync; mint_oi.sh re-syncs before reserving).
Reserved-but-unfiled: none.
File new OIs ONLY with:  sh scripts/mint_oi.sh "<title>"  — an UNRESERVED number fails the commit.
```
"Reserved-but-unfiled" lists `oi/N` branches whose N is on neither `origin/main` board nor the local
working board — informational, so a dead session's burnt number is visible rather than mysterious,
with the two ways out (adopt by hand, or `--release N`). Silent when `refs/remotes/origin/main` cannot
be resolved. The hook performs **no remote reads or writes**; every mint, `sync_refs`, and any plain
`git fetch origin` (default refspec covers `oi/*`) refreshes what it reads.

### 3.5 Documents touched

- `docs/audit/open_issues.md:9-11` "How this file is used": the filing rule becomes *"run
  `mint_oi.sh`; never type a number"*; OI-176 → CLOSED (`closes-oi: OI-176`).
- `CLAUDE.md` §7 "OI number uniqueness across branches" row: from *"there is NO allocator"* to the
  allocator + the three-transport table; §4.9 gains no row (no new pitfall class — the pitfall was the
  absence of this).
- `docs/diagnoses/2026-09-12-oi-gate-vacuous-pass-<id>.md` for the OI-176 fix (rule 22).
- `docs/handbook/` process page: one paragraph, since this is a durable working rule.
- `.claude/skills/debugging/SKILL.md`: **no change.** The "sequential numbers minted by eyeballing"
  class is OI-167's (the skill's own section numbering); this batch resolves the OI-board instance,
  not the skill-numbering one, and a pointer from a skill to a board entry it does not fix would mislead.
- `CLAUDE.md` §4.3: one clause cross-referencing the §7 row's exemption for the ref-CREATE push inside
  `mint_oi.sh` (a §4.3 reader never reaches §7).
- `scripts/build_oi_index.dart:110-111`, `scripts/oi_numbering_lib.dart:7-8`: the "There is no
  allocator" comments become "until 2026-09-12 there was none; mint_oi.sh now allocates".
- `vercel.json`: `ignoreCommand` skipping `oi/*` (see §7.3). `scripts/new-worktree.sh`: fetch
  `oi/*` alongside `main` (same round trip).

## 4. Data flow — the six scenarios

1. **Laptop mint.** Session in worktree `foo` runs `mint_oi.sh "…"` → fetch → N=186 → API commit +
   ref → 201 → local `origin/oi/186` updated → stub appended → every other laptop worktree already sees
   `origin/oi/186` in the shared `.git/`. Next commit touching the board: Check C step 1 ⇒ reserved.
2. **Cloud mint.** Cloud clone runs the same script → no `gh` → git transport → `[new branch]` → stub.
   Its later commits are checked in CI (it has no hooks); Check C step 1 answers from the full checkout.
3. **Race.** Laptop and cloud both compute 186 within seconds. One ref create wins; the other gets
   422 / `[rejected]`, re-syncs, takes 187. No renumber, no human.
4. **Hand-typed number.** A session types `## OI-190` without minting. Pre-commit Check C: no
   `origin/oi/190` locally → one `ls-remote` → absent → **FAIL** with the `--reserve` line. Cloud
   session (no hooks) → caught at `pre-merge-commit` on the laptop when its branch is merged, or in CI
   on a PR. NOT caught by CI on a push straight to `main` (Check C is vacuous there — §3.3); that path
   is a process residue (§7.5), not a live one: merges happen on the laptop via `safe_merge.sh`.
5. **Offline laptop.** `mint_oi.sh` exits 2 and writes nothing. The gate on an unrelated commit stays
   fail-open; the gate on a board-touching commit with an unreserved number says SKIPPED, and CI fails it.
6. **In-flight branches at rollout.** `regen-wave-unit2` holds 177/178 (real collisions) → renumber via
   two fresh mints. Any other unmerged branch holding a *legitimately unique* unreserved number runs
   `--reserve N` once; if that reports TAKEN, it was never unique.

## 5. Fail-open vs fail-closed — stated so nobody has to infer it

| Step | On failure | Why |
|---|---|---|
| `mint_oi.sh` sync / write | **fail closed** (exit 2/3, nothing written) | the only step where proceeding creates the defect |
| Check B′ / C, network unavailable | fail open → **SKIPPED**, never PASS | existing convention; CI is authoritative |
| Check C, reservation provably absent | **FAIL** | a checked answer, with the repair in the message |
| SessionStart line (local read, no fetch) | silent | a session must never fail to start over a hygiene line; no network ⇒ no 3 s stall |
| `--prune` after a mint | silent, exit code unaffected | hygiene, not correctness |

## 6. Testing and mutation plan

All new/extended files under `test/scripts/` carry `@Timeout(Duration(minutes: 6))` + `library;`
(§4.9 subprocess row) and a teardown that never throws.

- **`test/scripts/mint_oi_e2e_test.dart`** — real repos: `git init --bare` as `origin`, two clones,
  `MINT_OI_TRANSPORT=git` to force the git path (no network in tests).
  1. two clones mint → distinct consecutive numbers, both `oi/N` present on origin, both ledger lines parse;
  2. pre-created `oi/186` on origin → mint yields 187;
  3. `--reserve 186` when free → succeeds; when taken → exit 3, no board change;
  4. origin unreachable (path renamed) → exit 2, board byte-identical (hash before/after);
  5. `--prune` with 186 on origin main's board and 187 not → deletes only `oi/186`;
  6. stub contains every `build_oi_index.dart:39` field, and `build_oi_index.dart` exits 0 on the result;
  7. **API transport via a `gh` shim** on `PATH` (a POSIX script backed by a temp dir: `POST git/refs`
     writes a file or returns 422 if it exists) → same assertions as 1–3 through the API branch of the
     script.
  8. **the race, made reachable:** clone B mints with `MINT_OI_TEST_HOOK_BEFORE_PUSH` set to a command
     that creates `oi/186` on origin from clone A *inside* B's fetch→push window → B's first push is
     rejected, B retries and reports **187**, and `oi/186` still points at A's ledger commit.
  **Mutations (each confirmed applied by `grep -c` before the run):** replace `--force-with-lease=…:`
  with `--force` → test 8 reddens (B overwrites A and reports 186) and test 3 reddens (a taken
  `--reserve` succeeds); drop the shim's 422 → test 7 reddens; drop the working-board term from the max
  → a test seeding a hand-typed 190 on the working board reddens. ⚠ Tests 1–2 do NOT redden under the
  `--force` mutation — they mint sequentially with a fetch in between, so they never exercise the CAS.
  Said here so nobody cites them as proof of it.
- **`test/scripts/oi_numbering_gate_e2e_test.dart`** (new; the lib test stays pure):
  1. **OI-176 shape**: worktree cut from a merge commit, zero commits, staged board with `## OI-186`
     colliding with origin/main's 186 under a different title → **FAIL** (today: PASS);
  2. minted-here 186 with `refs/remotes/origin/oi/186` present → PASS;
  3. minted-here 186, no local ref, origin unreachable → exit 0 AND stderr contains `UNDETERMINED`
     AND stdout does not contain `PASS`;
  4. minted-here 186, origin reachable, no `oi/186` → FAIL with the `--reserve 186` line;
  5. title-only edit of an existing OI on the branch → PASS (the base leg still protects against false
     positives).
  **Mutations:** revert B′ dispatch to HEAD-shape → test 1 reddens; make Check C treat a failed
  `ls-remote` as reserved → test 3 (offline) reddens — NOT test 4, whose remote is reachable; drop
  `failures.add` → tests 4 and the mid-merge test redden; empty the base boards → test 5 reddens
  (and the lib file's own title-edit test, `:348`, with it).
- **Fixture-vs-history check** (rule 21): test 1's fixture is produced by `sh scripts/new-worktree.sh`
  semantics (branch cut from `main` whose tip is a merge), verified against `git log --merges -1 main`
  in the real repo — the shape the founder's sessions actually start in.
- **Full-suite run once** before believing any of it (§4.9: a targeted run cannot create contention).

## 7. Residues — stated, not fixed

1. **Ownership is reported, not enforced.** Check C proves a number was *allocated*, not that *this
   branch* allocated it. The coincidence case — A hand-types exactly the number B just reserved —
   passes Check C and is caught by the existing merge-time arm, as today. Enforcing ownership needs a
   stable identity (branch names change; worktrees are recreated) and an override, which is hatch creep.
   Revisit if the coincidence case ever fires.
2. **A cloud session has no pre-commit hooks**, so for it the mint script is the prevention and CI is
   the backstop. A cloud session that hand-types a number learns in CI, not at commit.
3. **Branch-list growth**: +1 head per OI until pruned; 41 heads today. Prune runs after every laptop
   mint, so steady state is "in-flight OIs plus orphans". CI does not trigger on `oi/*` (`test.yml:5-7`).
   **Vercel DOES build every pushed branch** (a preview for `regen-wave-unit2` exists; `vercel.json`
   had no `ignoreCommand`), and a reservation is a new commit carrying main's full tree — so without the
   `ignoreCommand` added in this batch every mint would cost a full Flutter-web build. Confirmed after
   the first real mint.
4. **The SessionStart line reads LOCAL refs only** — this residue's original text ("adds one
   `git fetch`; if it exceeds 2 s median it becomes read-local-only") resolved itself in review round
   1: 2.9–3.2 s measured, so the fetch was never built. The cost is that a reservation made elsewhere
   is invisible to the line until the next sync; the line says "at least N" and the mint re-syncs.
5. **Check C is vacuous at CI on a push straight to `main`** (§3.3). A hookless environment pushing
   directly to `main` is checked for collisions but not for reservations. Not a live path: the cloud
   pushes `claude/*` branches and every merge to `main` runs on the laptop through `safe_merge.sh`,
   whose `pre-merge-commit` hook runs Check C.
6. **Orphan reservations** (a session died between the CAS and the stub) are never auto-deleted —
   `--prune` touches only PUBLISHED numbers, by design. They are listed at every SessionStart with
   the two ways out: adopt by filing `## OI-N` by hand, or `sh scripts/mint_oi.sh --release N`.
   ⚠ **From worktree B, sibling worktree A's in-flight number looks exactly like an orphan** (review
   round 2). Both the SessionStart list and `--release` therefore exclude any number filed on ANY
   local branch, and `--release` prints the ledger line (branch + time) before deleting. What remains
   invisible to a laptop clone is a CLOUD branch's in-flight number: the ledger line names the branch,
   and the operator reads it before releasing. The cloud never prunes (no `gh`).
7. **`POST /git/commits` without `parents` creating a ROOT commit** is documented by GitHub but was
   not proven live (the spike proved the refs 422 and the cloud 403). The first real laptop mint
   proves it; the fallback is an explicit `"parents": []` JSON body.

## 8. Rollout

1. Merge this batch (gate + script + hook + docs) via `safe_merge.sh`, push.
2. From the laptop: `sh scripts/mint_oi.sh --next` → expect `1 + max(origin/main board)` (189 at
   spec-commit time; re-derive, do not trust this number); no reservations yet.
3. No in-flight collision is known at spec time (177/178 were renumbered before this landed). Every
   unmerged branch holding board additions: `--reserve N` per number, at its next board-touching commit
   — Check C makes this self-enforcing, with the exact command in the failure text.
4. The harness memory `project_regen_alignment_brainstorm_inflight.md` still says "Board:
   OI-166/177/178/179"; correct it to 186/187 when that memory is next touched.
5. `MEMORY.md`: retire the in-flight line; write `project_oi_allocator_shipped_<ship-date>.md`.
