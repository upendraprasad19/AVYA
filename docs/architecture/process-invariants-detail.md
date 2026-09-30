# Process invariants — full original text

> Moved VERBATIM out of root `CLAUDE.md` (context-lean batch, 2026-09-29). Root keeps the rule statement plus a one-line why for each of these sections; the complete wording, incident narratives and measured figures live here. Section numbers are the ones root headings carry (§4.3, §4.4, §4.10, §4.12, §4.13). Figures are point-in-time prose; re-derive rather than trust.

## Full text — 4.3 Build / commit / push gates

- Never commit or push unless explicitly asked ("commit", "push", "ship" count; "continue" does NOT).
- Never build APK unless explicitly asked. Use `/build-apk` skill, NOT raw `flutter build`. APK builds on this machine can hang silently without the skill's pre-flight cleanup.
- APK builds from `main` ONLY. Feature branch → merge `--no-ff` to main → `/build-apk` from main.
- For new git worktrees, copy `.env` from main first (it's gitignored, doesn't carry over). Without it `SUPABASE_URL` compiles empty and auth crashes.
- **Batch commits; push once per logical batch.** Don't commit→push→commit→push — each push re-runs the tiered pre-push + a fresh CI run on the same code. Group related commits and push them together (lean-workflow batch 2026-06-01).
- **Sequential slices of ONE feature that have no independent user-facing value on their own
  consolidate into ONE push/CI/APK-gate cycle** — this is the above rule made concrete after the
  discipline-overhead audit (2026-07-18/19) found it wasn't happening in practice: Batch 5
  (equipment) shipped 6 separate pushes for one feature (crash-fix → vocab → filter → UI →
  activation), each paying the full local full-suite + CI + APK-gate cost for a slice with no
  standalone value. Only split into separate pushes when a review round finds a genuinely
  separable defect or infeasibility requiring redesign of one piece, or an explicit founder
  product-scope decision to ship one piece now — not as a default splitting reflex.
- **Commits and pushes go through `scripts/safe_commit.sh` / `scripts/safe_push.sh`, never raw
  `git commit` / `git push`.** A PreToolUse hook (`scripts/git_safety_hook.dart`) blocks the raw
  form outright. Reason: 6 documented incidents (2026-06-05 → the workout-generator batch,
  `feedback_git_landing_verification.md`) where a backgrounded or piped commit reported success
  while the pre-commit hook had actually failed (a pipe's exit code is the last stage's, not
  git's), or a push died SIGPIPE after the pre-push suite idled the SSH channel with no error at
  all. The wrapper redirects output to a log file (never a pipe) and verifies HEAD/status/
  ls-remote after, so "it reported success" and "it actually landed" can't silently diverge.
  Escape hatch for a case the hook mis-detects: `ALLOW_RAW_GIT=1`. `--no-verify` has NO such
  hatch — it requires explicit founder approval in chat first, then `FOUNDER_APPROVED_NO_VERIFY=1`
  for that one invocation. One documented exemption: the ref-CREATE push inside
  `scripts/mint_oi.sh` (OI allocator row in `docs/architecture/hooks.md`) — it creates a ref that must not exist, so its
  exit code is the verification and there is no range to gate.
- **What `safe_push.sh` CANNOT tell you, and what now does.** It proves the push LANDED; CI runs
  asynchronously *after* it returns, so its verdict says nothing about whether the build went green.
  On a landed push it therefore arms a reconcile entry (`scripts/arm_ci_reconcile.sh` →
  `.claude/.ci_reconcile_pending.jsonl`, gitignored), and the `SessionStart` hook
  `scripts/reconcile_ci.dart` looks the run up later and warns on a **failing** run, or on a run
  that never happened where one was due (`main`/`develop` — elsewhere no run is the expected
  outcome per ADR-0018, so it stays silent rather than firing on every `claude/*` push). Warn-only
  by construction: no gate calls it, no exit code is consumed, every error path exits 0. The arm is
  `|| true`-wrapped — a failure to record can never turn a landed push into a reported failure.
  **`safe_push.sh` has THREE outcomes, not two** (documented at its own `:12-21`, and previously
  absent from this file): `0` LANDED, `1` FAILED, **`2` UNVERIFIED** — git reported success but the
  remote was unreachable on BOTH probes, so whether it landed is genuinely unknown. A caller that
  treats non-zero as "failed" misreports a possibly-landed push; a caller that treats it as success
  misreports the opposite. Kill switch for the reconciler: `.claude/.reconcile_ci.disabled`
  (gitignored) — its presence makes `reconcile_ci.dart` return before reading any file or calling
  `gh` at all.
- **Which of those three outcomes happened is now RECORDED (OI-172, 2026-09-10).** Until this,
  nothing recorded it: the only in-flight evidence was the lock's `holder` file, and
  `_git_lock.sh:174-189` `rm -rf`s the lock on a `trap … EXIT HUP INT TERM`, so on any normal exit
  that file is **gone**. The lock answers *"is a push running right now"* and structurally cannot
  answer *"what happened"* — which is what a reaped, interrupted, or closed-terminal push leaves you
  asking. `safe_push.sh` now writes
  **`$(git rev-parse --absolute-git-dir)/.safe_push_result`**: `STARTED` + pid before the push, then
  one of `LANDED` / `FAILED` / `UNVERIFIED` at each of its four terminal exits (its other four exits
  precede any push attempt and stay silent — writing FAILED there would claim a push failed when
  none was attempted; `:63`, a lock-acquire refusal, is the sharpest case, since "another push is
  already running" and "this push failed" are opposite facts sharing exit code 1).
  ⚠ **READ IT THROUGH `scripts/push_result_lib.dart`, never by eyeballing the file.** The rules are
  not guessable and each one wrong yields a confident wrong answer: **absent or unparseable ⇒
  UNVERIFIED, NEVER failed** (reading absent as failed re-creates the very inversion the record
  exists to kill); a record applies only when **BOTH `ref` AND `local_sha`** match what you are
  asking about (**not the sha alone** — two refs legitimately share a tip after a fast-forward merge
  or on a freshly-cut branch, so a sha-only check lets one ref's verdict be read as proof about
  another); `STARTED` is not a verdict, pair it with `kill -0 <pid>`; and `LANDED` still never means
  CI-green. The contract lives in that lib as CODE rather than as prose here **because the first
  draft made it prose and its test had to invent its own reader, which made the test circular** —
  same pure-lib/own-test split as `ci_reconcile_state_lib.dart`. Location is load-bearing twice:
  inside `.git` so it cannot make a worktree unretirable (the class in §5 that has fired three
  times), and `--absolute-git-dir` because plain `--git-dir` is **relative** in the primary
  worktree. Published with `mv -T`, never plain `mv` — with a directory at the destination plain
  `mv` exits **0** and moves the record *inside* it, landing it where no reader looks while the push
  reports success. Every write is `|| true`-guarded, and a write failure cannot fail the push.
  ⚠ **Two residues, stated because neither is fixed:** a `kill -9` still leaves no record (same
  limit the lock's trap has — which is exactly why absent must read as UNVERIFIED), and a **tag**
  passed where a branch is expected gets a durably WRONG `FAILED`, because `probe_remote_sha()`
  hardcodes `refs/heads/$BRANCH`; the record now carries `verified_ref` so a reader can SEE the
  probe looked in the wrong namespace, but the verdict itself is still wrong. Zero call sites pass
  `--tags` today. Kill switch: `touch "$(git rev-parse --absolute-git-dir)/.safe_push_result.disabled"`
  — deliberately beside the record rather than in `.claude/`, where the two existing
  kill switches live, because neither of those is in `retire_worktree_lib.dart`'s
  `regenerableIgnoredPaths` and a worktree holding one is unretirable.
  Tests: `push_result_lib_test.dart` (pure, 21) +
  `safe_push_terminal_result_record_writer_to_reader_test.dart` (12, the
  shell-writer/Dart-reader key contract both ways) + `safe_push_test.dart`
  (12 new, real repos) = **51**, mutation-proven on 15 legs.
- **Don't manually re-run the full `flutter test`** when the hooks/CI will run it anyway — run targeted tests during dev; pre-push (≥account) + CI are the full-suite gates. CI is the full-suite source-of-truth.
- APK build from a CI-green, already-pushed `main` may use `/build-apk --from-green` to skip the redundant gate re-run (keeps the clean build + size + on-main/versionCode/.env gates).
- **≥account code-review is SELF-INITIATED, before the merge.** For any batch whose blast-radius is ≥`account` and that touches code / schema / Edge Functions, run `/code-review` (B-pass) BEFORE the `--no-ff` merge to `main` — do NOT wait to be asked. The pre-commit echo (§0) is a reminder, not the gate; the discipline is the agent's. (Docs/process-only ≥account changes — e.g. CLAUDE.md edits — take a self-consistency review of the wording instead of an adversarial bug-hunt.) Codified 2026-06-07 after a ≥account alert batch merged to local `main` un-reviewed and a P0 (alert blind to `event`-coded failures) survived until a founder-prompted push-time review caught it.
- **Live prod apply needs its own explicit go.** Applying a migration (`apply_migration`) or deploying an Edge Function to the prod project requires explicit per-action authorization EVEN WHEN the batch plan was approved — plan approval ≠ deploy approval. A classifier block on a live apply is CORRECT; get the explicit ok, never work around it.
- Refs: `feedback_apk_build_explicit_approval.md`, `feedback_main_is_source_of_truth.md`, `feedback_use_build_apk_skill.md`, `feedback_mistake_review_not_self_triggered.md`.

## Full text — 4.4 The coding rules (24 — NON-NEGOTIABLE)

1. **Hive-first for ALL reads/writes.** Never block UI on Supabase response. Supabase writes are background/async.
2. **Riverpod only** for state management. No `setState` for shared state.
3. **Hive boxes:** Register ALL adapters in `main.dart`. Open ALL boxes before `runApp()`.
4. **Repository pattern** for all data access. Never call Supabase or Hive directly from widgets.
5. **subscription.gate()** for ALL PRO features. Never use inline `isPro` checks in widgets.
6. **Phase 1 is ALWAYS free.** Never gate it.
7. **PaywallSheet** is the ONLY paywall UI.
8. **Plan generator = local Dart.** Queries Hive exerciseBox. Never calls any API.
9. **Never expose API keys client-side.** All AI calls go through Supabase Edge Functions. **EF auth contract (e8a1c3, 2026-06-13):** an Edge Function authenticates the caller via `createClient(SUPABASE_URL, SERVICE_ROLE).auth.getUser(token)` — NEVER pass the user JWT as the supabaseKey (`createClient(url, authHeader…)` 401s every valid token). Verify a `verify_jwt=true` EF with a REAL user token, not just anon boot (deploy-rollback skill, bug-class 6.7). Client authed `functions.invoke` calls route through `SupabaseService.callFunction` / `ensureFreshToken()` first (stale web token → 401). Gates: `check_edge_function_auth_pattern.dart` + `check_authed_invoke_fresh_token.dart` (auto-wired; debugging skill bug-classes 2.35 / 2.31).
10. **DM Sans font everywhere.** No system fonts. Use `GoogleFonts.getFont('DM Sans', ...)`.
11. **Wardroom palette** (Campaign Gold `#D4B270`) — not Electric Cyan, not the old green `#00e5a0`. See `lib/shared/widgets/wardroom/CLAUDE.md` for the JSX source of truth.
12. **Dark theme only.** Background hierarchy: `#02070F` (bg) > `#06101F` (card) > `#0E1E30` (input).
13. **All screens must handle:** loading state (skeleton), error state (retry), empty state.
14. **Never modify `plan_generator.dart`** without explicit instruction.
15. **Import paths:** relative within features; `package:` for shared/ and core/.
16. **Edge Function SSRF:** never fetch arbitrary user-supplied URLs server-side. Allowlist Supabase Storage prefix + user-scope assertion on path (OI-28).
17. **Release error handling:** `kDebugMode` guard — detailed errors only in debug, generic message in release.
18. **Edge Function input limits:** enforce message (5K) + snapshot (10K) limits server-side on ALL AI endpoints.
19. **Server-side subscription verification:** high-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`) MUST call `verifyFromServer()` in `gate()`.
20. **No deferred test failures.** Failing tests on `main` are P0 blockers. The label "pre-existing failure" is banned. **Where this is enforced changed 2026-08-11** (cost split, §0): pre-commit no longer runs `flutter test` at all, so the blocking gate is now the *push* — `scripts/pre-push.sh` at ≥`account` tier, and CI on the push to `main`. The POLICY is unchanged and is deliberately not weakened by the move: never `--no-verify` around either gate, never "ship something else first", and a red `main` is still a P0. Want the old commit-time gate back for a run? `PRE_COMMIT_FULL=1` (analyze + full suite) or `PRE_COMMIT_LEGACY=1` (analyze + `test/contracts/`).
21. **Regression test required for every fix.** Test that FAILS without the fix and PASSES with it. Cite test path in commit message. Source-grep tests under `test/contracts/` count for PRESENCE only — every SoT registry entry MUST ALSO have a `behavioral_test_path:` (Hive-write → Hive-read assertion, or fakeAsync race harness, or end-to-end flow) that fails when the runtime path is broken even if the source text remains intact. Gate 42 (`scripts/check_sot_behavioral_test_paths.dart`) is **STRICT by default**, BLOCKS the commit, and — since OI-195 (2026-09-19, diagnose `c7d2e4`) — **RESOLVES every cited path on disk**: each `behavioral_test_path(_*)` value (comment-stripped) and every repo-shaped path inside `presence_only` prose / `presence_only_reason` blocks must exist (file OR directory), or the gate fails naming the path. Until then it validated the value's SHAPE only, so a concept could cite a test that was never written and the gate printed PASS (the OI-153 B-pass shape). A new entry needs a real `behavioral_test_path:`, or `presence_only: true` documenting why a behavioral test is not feasible (17 concepts carry `presence_only: true`, 10 of which also cite a behavioral path — `grep -cE '^\s+presence_only:\s*true' docs/sot_registry.yaml`; this line said "6 entries" from 2026-08-07 to 2026-09-19 while the gate's own tally printed "7", both counting only the presence-only-WITHOUT-behavioral subset). **There is no `behavioral_test_required: true` backlog** — that escape hatch was removed when the gate flipped strict, and the marker is now itself a hard blocker. `--warn-only` exists for in-branch debugging and must never reach main. Corrected 2026-08-07: this rule previously described the pre-strict WARN behaviour, and a session planning OI-75 read it as licence to add a bare registry entry. (The `feedback_source_grep_false_confidence.md` this rule has always cited is NOT in the repo — it lives only in the harness-local memory directory, a trap `memory/MEMORY.md:8` documents for the whole `feedback_*` family. Only two `feedback_*.md` are actually committed. Left cited rather than deleted because the name is load-bearing vocabulary across the board, but flagged here so nobody burns a search on it.)
    **MUTATE IT AND RUN IT — a fix whose only NEW protection is a test WRITTEN
    OR EXTENDED BY THIS BATCH must be mutated once before that test is
    believed, and the diagnose-doc must say what was mutated and how many
    tests reddened (2026-08-30).** ⚠ **Behavioral and e2e tests are covered,
    not just source-greps** — corrected by plan-review round 2 the same day,
    which caught that the clause originally said "source-grep test" while
    EVERY example justifying it is a behavioral one: Gate 42's stale
    `behavioral_test_path:`, the `return first;` retry case, and this batch's
    own `safe_merge.sh` precheck, whose three failing tests were real
    subprocess-driven e2e tests. Scoped to source-greps, the clause would have
    exempted precisely the class its own case study indicts — an author with a
    "real" test reads themselves as exempt and skips the one step that would
    have caught it. Round 2 then found three more live gaps in exactly those
    "exempt" e2e files. Not a
    new ledger: the diagnose-doc already exists per rule 22, and rule 24's
    `mutation_proven:` ledger stays scoped to `check_*.dart` gates. **Why this
    is not covered by the rules above, stated precisely, because it looks like
    it should be:** Gate 42 was GREEN for `user_full_name` throughout the
    `profile-phase-fixes` batch — satisfied by a PRE-EXISTING
    `behavioral_test_path:` that never executes the new
    `_fetchUsersRowForRestore` at all. A concept-level behavioral test says
    nothing about code added to that concept later, so rule 21's own protection
    can be green about a line it does not run. That gap let TWO CONSECUTIVE
    tests ship without testing their fix: mutating `return retried;` →
    `return first;` (the exact pre-fix defect) left all 7 green, and the test
    written to close THAT left the retry's entry guard unpinned — `if (false)
    return first;` left all 8 green. Both were found by review, by mutation,
    not by reading. **A test written by whoever wrote the fix inherits its
    blind spot; the only cheap way out is to break the fix and watch.**
    ⚠ **Confirm the mutation actually APPLIED** (`grep -c` the removed token,
    or run the broken form once) — a regex that silently matched nothing makes
    a green run read as proof when it is proof of nothing, which this repo has
    already recorded twice. ⚠ **AND A COMPILE ERROR IS NOT A
    MUTATION PROOF** (2026-09-04, OI-162 slice 1's gate). Two mutations there
    reddened the run by making the file **fail to compile** — removing a null
    check broke Dart's null promotion in the following `else if`, so the runner
    reported `loading … [E]` and "Some tests failed". That is red for the WRONG
    REASON: it proves the file is now invalid, not that any assertion detects
    the defect. Read the failure, do not just count it. **A valid mutation
    leaves the code compiling and semantically wrong**; if yours does not,
    pick a different one — mutating the ALLOWLIST rather than the branch that
    reads it worked here, and was a better proof anyway because it showed which
    of the two was doing the work.
    ⚠ **AND A MUTATION THAT REDDENS *NOTHING* IS NOT PROOF THE CASE IS
    ALREADY COVERED** (2026-09-06, Unit B, diagnose `c5a8f3`). The third
    member of this family and the quietest: a guard sitting inside a method
    whose `catch (_) { return null; }` converts the resulting error into the
    SAME value the test asserts. Deleting the `waves.length < 4` guard, the
    `is! Map` guard and the `stamped`-shape guard each reddened **ZERO of
    twelve** assertions — the RangeError / NoSuchMethodError was swallowed
    and the tests, which asserted `null`, stayed green. FOUR of them were
    testing the exception handler rather than the guard. A zero-red mutation
    has exactly two explanations — the case is covered elsewhere, or
    **something absorbed it** — and they are indistinguishable from the run
    alone, so go find out which. The fix is structural: **extract the guards
    into a pure function with no `catch` above it**, so every returned value
    has exactly one source. Same shape as the compile-error trap above (red
    for the wrong reason), inverted: green for the wrong reason.
    ⚠ **And confirm the FIXTURE reproduces a state the
    real workflow actually produces**, because a mutation run against a
    fictional fixture proves nothing either. That is not hypothetical: the
    `safe_merge.sh` precheck shipped in this same batch was mutation-"proven"
    in good faith and was a total no-op in production, because its fixture
    committed a plan-review record onto `main` when the real workflow only ever
    commits it on the feature branch. One command settled it
    (`git cat-file -e <merge>^1:<path>` → absent). Check the fixture against
    HISTORY, not against the code under test.
    ⚠ **SELF-ATTESTED, exactly like rule 24's ledger and `presence_only:` — no
    gate enforces it.** `validate_diagnose_doc.dart` has zero references to
    mutation (grep it). Said plainly rather than left to be assumed, because
    this clause sits one breath away from Gate 42, which IS mechanical, and a
    reader skimming the rule could reasonably credit it with comparable teeth.
    It has none; it is read by the §4.12 ×2 review. Do not mistake it for a
    solved problem.
22. **Bug fixes require a diagnose-doc.** Every commit on `main` matching `^(fix|bug|regression)(\([^)]*\))?:` MUST reference `docs/diagnoses/<date>-<slug>-<id>.md` via `closes-diagnose: <bug-id>` in the commit body. Doc must pass `dart run scripts/validate_diagnose_doc.dart <path>`. Subagents dispatched for investigation MUST receive `docs/agent_brief_preamble.md` as prefix. Pre-commit hook + `/build-apk` Gate 10 enforce this.
    **S-tier fixes (§4.12.6) use the slim diagnose template:** symptom, writer+reader by
    file:line, fix, test path; `touched_layers_checked` collapses to the UI + client-code rows
    (validator still satisfied — non-empty + one verified/fixed row); frontmatter carries
    `tier: s_fix` (batch telemetry counts S-fixes by that stamp — an unstamped S-fix is
    invisible to it). Recurrence-class bugs take the FULL template at ANY tier.
23. **No stopping mid-batch.** Multi-task instructions ("fix everything", "address each and everything") run through to completion. Valid stops only on: whole batch done / BLOCKED on user-only action / new interrupting instruction. Banned: "context tight", "responsible handoff", "fresh session pickup". Documentation per rule 22 + memory file update for any NEW pattern + CLAUDE.md update for any NEW invariant — always. <!-- deu-quote: rule 23 enumerating the banned stopping excuses -->
24. **Every NEW `check_*.dart` gate ships mutation-proven.** The same commit adds a test that FAILS when the gate's protection is deliberately neutered — not merely a happy-path test — plus a `mutation_proven: true` entry in `docs/audit/gate_test_ledger.yaml` carrying `test_path:` (a LIST — the closest precedent, `retire_worktree`, is proven across two files) and `evidence:` naming what was neutered and how many tests reddened. `scripts/check_gate_test_ledger.dart` requires every `check_*.dart` to hold **exactly one** ledger state, and a `mutation_proven` claim to name a test that EXISTS, REFERENCES the gate, and CONTAINS a red-path assertion drawn from a **closed literal list** of accepted forms (bare `isNotEmpty` is deliberately rejected — it appears in hundreds of unrelated assertions and would make the check pass for almost any file). **What this proves and what it does not:** a script cannot prove a mutation was RUN. It CAN prove the test exists, names the gate, and asserts a failing path — which makes the Gate-44 class ("its own test never invoked `main()`") mechanically impossible. The residue is self-attested and read by the §4.12 ×2 review — the same trust model as rule 21's `presence_only:` and §4.12.4's `tier: ship_dark_build`. Say so plainly; do not mistake it for a solved problem. **The 84 gates predating 2026-08-10 are enumerated BY NAME** in that script as `grandfathered:`. Membership is by name, not by date — a date-equality check closes nothing, since any future gate could write `grandfathered: 2026-08-10` and pass, and both gates born in that batch carry that very date. An enumerated exemption is terminal, NOT a deferral (§4.2); "backfill later" would be. **A new gate takes NO number.** The filename is the identity — it is what `pre-commit.sh`, `test.yml` and Gate 33 all key on. A number is an optional alias that only a `/build-apk` section needs; if one does, it takes the next free number, which `build_gate_index.dart` prints on every run. Registry: `docs/audit/GATE_INDEX.md` (generated — see the §7 pointer row).

## Full text — 4.10 Tech-debt audit cadence (NEW — tech-debt audit 2026-05-20)

- Run the 6-category tech-debt audit (Code / Architecture / Test / Dependency / Documentation / Infrastructure) at minimum once per quarter AND after any 3+-batch landing.
- Audit produces closure YAML at `docs/audit/<YYYY_MM_DD>_audit_closures.yaml`. Every finding gets exactly one terminal state: `closed_in_commit:`, `upstream_blocked:`, **`blocked_on_user:`**, or `verified_clean:`. The schema has NO `deferred:` key. Validator: `scripts/validate_audit_closure.dart`. ⚠ **`blocked_on_user` was missing from this line until 2026-09-03** (audit 2026-09-02 finding DOC-19) — `validate_audit_closure.dart:57-62` has always accepted four states, and §4.2's own structural-invariant paragraph lists all four, so this row contradicted both the code and its own neighbour. It is the state for an item needing FOUNDER action (a Play Console setting, a device run, a live-deploy authorization); without it such an item gets mis-filed as `upstream_blocked`, whose `reopen_when:` semantics are different. Required fields per state, drafted from the VALIDATOR not from prose: `closed_in_commit` → `commit:` + (`verification:`|`notes:`) · `upstream_blocked` → `blocker:` + `reopen_when:` · `blocked_on_user` → `reason:` · `verified_clean` → `evidence:`|`notes:`. ⚠ Note the ledger is validated on EVERY commit repo-wide, so do not create it until every finding is terminal — a half-filled ledger blocks a concurrent session's commits too.
- Closure YAML entries MUST carry `terminal_state:` on the entry itself; stale `# NOT YET CLOSED` / `# IN PROGRESS` / `# PARTIAL` / `# SCHEDULED FOR` comments are insufficient. Gate 40 emits warnings (or `--strict` fails) when a finding has only a stale-pattern comment. Per `feedback_closure_yaml_per_finding_discipline.md` (codified B5/D1 2026-05-21 after discovering 13 findings had been closed in commits but their YAML entries retained stale comments).
- `closed_count:` is a derived tally — recompute from per-entry data, never increment without simultaneously updating the corresponding entries.
- Quarterly cadence enforced via `/schedule`: first scheduled fire 2026-08-03 (first Monday of Q3), then quarterly.
- See `feedback_no_deferrals_tech_debt_class.md` + `feedback_audit_closure_yaml_required.md` + `feedback_closure_yaml_per_finding_discipline.md` + `feedback_operational_observability_first.md`.

## Full text — 4.12 Plan review ×2 + discipline-before-skill (NEW — founder directive 2026-06-13)

Two standing invariants, codified after a 4-round pre-implementation review of the test2 fix-batch caught two *wrong* fixes BEFORE a line was written (a referral "auth" bug that was really an RLS-context bug; a "broad-blast calc" that was already half-shipped with a silent overwrite + a fabricated body-fat default):

1. **Every implementation plan is independently reviewed TWICE before execution.** Dispatch context-blind reviewers (assume loopholes; verify every claim against code + live state, never subagent prose). **Review #2 runs on the POST-review-#1 (hardened) plan** — the corrections themselves can introduce new defects (they did: a SECURITY-DEFINER RPC that would have re-created the anon-executable bug; a `body_fat ?? 18.0` default feeding a fabricated value into every skip-user's calc). When successive reviews keep surfacing *new* material issues, that is the signal the unit is too large — **split it and ship the smallest converged piece**, don't review the large thing a fifth time. Ref: `feedback_plan_review_twice.md`.
2. **Discipline is enforced BEFORE every skill invocation.** Before any Skill call, load + apply the relevant invariants first (CLAUDE.md §4; the Wardroom brand soul for copy work; the bugfix/observation workflow for fixes) — never fire a skill blind. Ref: `feedback_discipline_before_skill.md`.

3. **A plan-review RECORD makes #1+#2 a *forcing function* (P1.A — discipline overhaul 2026-06-18).** The ×2 review + the ground-truth audit PRODUCE `docs/plan-reviews/<branch>.md` (`review_rounds: ≥2`, `ground_truth_verified: true`, `verdict: converged`; `bpass: accepted` ≥platform; `hermes: accepted` catastrophic). The keystone gate `scripts/check_plan_review_record_exists.dart` enforces it at the **merge-to-main commit, in CI** — the only structurally-gateable point (a local pre-commit `MERGE_HEAD` check is `--no-verify`-bypassable; a `--no-ff` merge skips the local hook entirely; CI is per-push). The dedicated CI job uses `actions/checkout` `fetch-depth: 0` so `HEAD^1..HEAD^2` (the merged branch diff → blast-radius) is reachable. A ≥account merged branch with no converged record fails the build. The record is keyed on the **branch name** (recoverable at both author-time and the merge commit's `Merge branch 'X'` subject) — NOT a staged-diff hash, which is empty at a merge commit.

4. **Ship-dark review tiering (discipline-overhead batch, 2026-07-19).** A platform/account-tier
   change that is (a) gated behind a kill-switch, (b) default OFF, and (c) has a passing
   behavioral test proving byte-identical output when OFF gets **1 independent review round**
   (not ×2) at build time — the plan-review record for that commit self-declares `tier:
   ship_dark_build` and `review_rounds: 1`. Only the *review-round count* drops; `bpass:
   accepted` is STILL required at ≥platform exactly as before (it's the cheap, self-driven pass —
   the expensive part being lightened is the second independent context-blind round, not the
   self-review). The full ×2 review is REQUIRED again, no exceptions, on the commit that flips
   the flag's default or removes the kill-switch — that is the moment real user risk starts,
   regardless of how lightly the build step was reviewed. Every
   flag shipped under the lighter build-tier review is logged in
   `docs/ship_dark_pending_review.yaml` (flag, branch, build-commit sha, date) and only removed
   once its flip-on commit's plan-review record shows the full ×2 + `bpass: accepted` — the
   guardrail against a flag quietly going live, or sitting forgotten, having only ever had 1
   review round. `scripts/check_plan_review_record_exists.dart` accepts `review_rounds: 1` ONLY
   paired with a self-declared `tier: ship_dark_build`; every other ≥account merge still requires
   `review_rounds: >= 2` exactly as before — this is a minimal, self-attested opt-in (same trust
   model as the rest of that gate), not automatic ship-dark detection from the diff. Automatically
   *verifying* a commit's flag really is default-OFF and byte-identical from a script is real,
   separate engineering — deliberately deferred as its own follow-up per §4.11 (gate before
   refactor), not bundled in here. Born from the workout-generator-overhaul discipline-overhead
   audit 2026-07-18/19: of the 29 `workout-*` branch merges that shipped the overhaul, at least 14
   were explicitly tagged `ship-dark` in their own merge subject (a floor — several more were
   ship-dark in substance without the literal tag), yet every one paid the full ×2-review weight
   at build time regardless of the zero live risk until flip-on.

5. **Run the local gate loop BEFORE dispatching any review round that has a
   draft diff to gate (2026-08-30).** The scoping clause is load-bearing: point
   1 reviews a PLAN, and a prose plan with no code drafted yet has nothing for
   `sh scripts/pre-commit.sh` to run against — do not read this as a
   requirement to gate an empty tree. It binds from the first round where a
   diff exists, which in practice is every B-pass and every review of a drafted
   implementation.
   Reviewer attention is the scarcest thing in this process and the easiest to
   waste on work a script already does. Measured on the `profile-phase-fixes`
   batch: of **17** findings across a B-pass and two plan-review rounds, roughly
   **half** were mechanical — stale `line_range`s, a wrong blast-radius
   attribution, a call-site count that was 3 when it is 4, a missing SoT entry.
   `check_sot_registry_parity.dart` then caught three of those citation errors
   **at commit time, after** two review rounds had already hand-audited
   citations. That ordering is backwards and it is free to fix: run the gates,
   fix what they find, THEN dispatch. Reviews are for mechanism — the C3
   unreachable-retry path and the `mergeCloudProgress` race in that same batch
   are what a context-blind reader is uniquely good at, and both nearly got
   crowded out.
   ⚠ **The gate loop is 76+ scripts; a hand-picked subset is not it.** That
   batch ran 8 gates by hand, called it verified, and the commit then failed on
   two that had not been picked. Run `sh scripts/pre-commit.sh`'s loop (or just
   attempt the commit) rather than choosing gates by relevance — "which gates
   are relevant" is exactly the judgement the loop exists to remove.

6. **S/M/L fix tiering (discipline-overhead v2, 2026-09-17; boundary corrected by plan-review R1 2026-09-18).** Three fix classes:
   **S** = diff touches ONLY `lib/features/{home,train,nutrition,profile}/**` — this four-dir list is a
   HARD filter, evaluated literally; a classifier feature-tier verdict is NECESSARY but NOT sufficient
   (the classifier's feature tier also covers `lib/shared/**`, `test/**`, `docs/**`, `scripts/**`, none
   of which are S-eligible), and auth/ai_coach UI is account-tier ⇒ M. Plus: ≤2 PRODUCT-code files
   (tests + diagnose doc are excluded from the count — a rule-21/22-compliant fix is minimum 3 files
   total), diff <100 lines (WHOLE diff — tests included), not a recurrence-class bug ⇒ NO ×2 plan review, B-pass SKIPPED; analyze
   `lib/` + targeted tests + slim diagnose doc (frontmatter `tier: s_fix` — the telemetry reader
   depends on that stamp) only. **M** = everything not S/L ⇒ current pipeline + compile-gate
   (`flutter analyze lib/` in the worktree BEFORE every reviewer dispatch; reviewer briefs declare
   compile-class findings out of scope). **L** = payment/auth/sync/schema/EF/plan-engine/CLAUDE.md ⇒
   current pipeline UNCHANGED. **Trust model, stated plainly:** S-eligibility is SELF-ATTESTED at
   commit time — no gate computes it; the mechanical backstop is the merge seam (any ≥account
   classification still demands the plan-review record) plus auto-escalation (any gate failure, seam
   symbol, or diff growth mid-fix ⇒ M), and the escape ledger is the feedback loop: S-tier escapes go
   in `docs/audit/s_tier_escapes.yaml` and any P0/P2 escaping an S-fix triggers ONE evidence-based
   tightening, not reflex ceremony. Convergence shortcut: a plan-review round whose findings are ALL
   mechanical/citation-class closes the record with `mechanical_only: true` (self-attested, same
   trust model as §4.12.4); §4.12.5 split-and-ship stays the escalation for material findings.
   S-class APK builds accumulate on main — the founder initiates builds, never per-fix by default.

7. **Execution mode is decided at batch START and written into the plan (OI-220 rider 2,
   2026-09-19).** Subagent-driven (one isolated worktree per unit, no git by the units beyond
   their own branch, the coordinator integrates by cherry-pick and is the single writer of every
   shared file) or inline — chosen once, before the first implementation step, never switched
   mid-batch. A mid-batch switch is how two sessions end up editing one file, and the
   `gate-integrity` batch measured the alternative: four units with zero file overlap built in
   parallel, integrated in one pass, with the coordinator re-verifying one mutation per unit by
   hand (§4.4 rule 21) rather than trusting the units' self-reported reds.

8. **Full gate loop before review dispatch (NON-NEGOTIABLE — adopted from ICANBEFITTER, 2026-09-23).**
   Before dispatching ANY review round that has a diff to look at, run the COMPLETE gate suite:
   ```bash
   flutter analyze lib/
   flutter test
   dart run scripts/pre-commit.sh   # or attempt git commit to trigger the loop
   ```
   NOT a hand-picked subset. Hand-picked subsets miss gates. A review that only runs "the relevant ones" is choosing which gates the next reviewer does NOT see. The measure: a `profile-phase-fixes` batch ran 8 gates by hand, skipped 2, and the commit failed on one of the skipped ones. That gap did not exist in the review because nothing in the review ran that gate. Run the full loop — the loop exists to remove the judgment about which gates are relevant.

These bind the planning / `/code-review` / `/hermes-pass` / brainstorming flows.

## Full text — 4.13 One worktree per session (NON-NEGOTIABLE — codified 2026-07-07 after 2 cross-session mixing incidents)

Multiple Claude sessions running in the SHARED main folder (`C:/Upendra/Claude Code/Fitness App`)
share ONE git index (`.git/index`). A `git add` from either session stages into that same index, so
a commit from one can silently MIX in the other's staged files (2 incidents 2026-07-07). A git
**worktree** has its OWN index, so working in a dedicated worktree makes the mixing impossible.

1. **EVERY session that will edit/stage/commit MUST work in its OWN worktree.** Create it with
   `sh scripts/new-worktree.sh <slug>` (copies `.env`), then
   `cd .claude/worktrees/<slug>` and do ALL edits/commits there.
   **The base is NOT simply "the latest `main`"** — `new-worktree.sh:65-91` compares local `main`
   and `origin/main` with `git merge-base --is-ancestor` and picks whichever is ahead, preferring
   LOCAL `main` in the merged-but-unpushed case (§4.13's own merge-locally-then-push workflow makes
   that the common state). On genuine divergence it WARNS to stderr and proceeds on local `main`
   rather than failing — deliberately not a ship-stop. Its header records that "prefer origin/main
   unconditionally" was the old behaviour and caused a real conflict on 2026-08-10.
2. **The shared main folder is INTEGRATION-ONLY:** reads, merging a branch into main, `git push`,
   `/build-apk`, and worktree **retirement** (point 6 — `retire_worktree.dart` refuses to run from
   a linked worktree, so the primary is the only place it CAN run). Never `git add`/commit feature
   work there. **Prefer
   `sh scripts/safe_merge.sh <branch>` over a raw `git merge --no-ff <branch>`** for the merge step
   (Unit 3c, discipline-tooling-hardening, 2026-08-03) — it refuses to merge onto a local `main`
   that is behind `origin/main`, and shares the same concurrency lock as `safe_commit.sh` /
   `safe_push.sh`. Not yet enforced by `git_safety_hook.dart` (that hook currently has no clause
   for `git merge` at all — a raw merge still runs unguarded); wiring a hard block is a separate,
   explicitly-deferred decision, not assumed here.
3. **Enforced** by `scripts/check_commit_from_worktree.dart` (pre-commit): a non-integration commit made
   in the PRIMARY worktree is BLOCKED (primary detected via `git rev-parse --git-dir` == `--git-common-dir`,
   both resolved absolute). Exempt: integration ops into main (merge/cherry-pick/revert — their
   `*_HEAD` ref present), linked worktrees, CI (`GITHUB_ACTIONS`), nothing-staged, and the documented
   `ALLOW_MAIN_COMMIT=1` escape hatch. Never `--no-verify` around it.
4. **SessionStart warning:** `scripts/discipline_hook.dart` warns whenever a session starts in the
   shared main worktree.
5. Even a solo session should use a worktree — it is always safe, and "is another session active?" is
   not reliably knowable. Ref: `memory/feedback_worktree_per_session.md`, diagnose `f0c2d5`.

6. **RETIREMENT — the other half of the lifecycle (added 2026-08-09).** This rule mandated
   *creation* and defined no end of life: `new-worktree.sh` created, nothing retired. The count
   reached **106 directories / 17 GB**, reclaimed to **1.4 GB** (`du -sh .claude/worktrees`,
   observed 2026-08-09 — point-in-time measurements, not re-derivable after the fact; re-measure
   rather than citing these). That is not neglect, it is an unclosed loop in the rule itself, so
   it regrows on its own unless the rule closes it.
   - **Retire a worktree once its branch is merged, clean (tracked AND ignored) and carries
     nothing unpushed:** `dart run scripts/retire_worktree.dart --execute [<slug>]` — run from the PRIMARY worktree
     (it refuses from a linked one; removing the tree you stand in is undefined). **Dry-run is the
     DEFAULT**; `--execute` is opt-in.
   - **WHEN — the trigger, without which this is just prose.** The §5 per-batch checklist carries
     a retirement row, so it is walked at every batch end alongside the diagnose-doc and index
     regens. This is deliberate: §4.13 points 1–5 are backed by a pre-commit gate, and point 6 is
     NOT (see below), so without a checklist row it would decay exactly the way
     `docs/audit/open_issues.md` did — 70 days unread because "nothing referenced it, everything
     with a gate holds, everything on intention decays". A §7 pointer row is not a trigger.
   - **The predicate is FOUR-legged and every leg is load-bearing:** (1) merged into `main`,
     (2) no tracked changes, (3) no NON-REGENERABLE ignored files, (4) no unpushed commits — or no
     upstream configured at all, in which case leg 1 already guarantees the commits are reachable
     from `main`. Anything failing any leg is reported and LEFT ALONE — never `--force`.
     **"Merged" alone is NOT sufficient and this is measured, not theoretical:** on 2026-08-09 five
     worktrees held 21 uncommitted files between them while classifying as merged by branch tip. A
     merge-only sweep destroys all of it. Merge status describes a branch; it says nothing about
     the working tree on top of it. **Leg 3 is separate from leg 2 because
     `git status --porcelain` — the obvious spelling of "clean" — EXCLUDES ignored files entirely**
     (see below), so naming it as the clean check would name the blind spot as the guard.
   - **Orphaned directories** (present on disk, absent from `git worktree list`) are a SEPARATE,
     stricter category: `git worktree remove` cannot see them, and an orphan is by definition one
     git has lost track of — so "git says it is safe" carries no information. Only a genuinely
     empty directory is auto-removed; anything holding even one file is reported for human review.
   - **Deliberately NOT a blocking gate — an explicit, named exception to §4's "Pre-commit hook
     gates them. Violations are P0." default.** A commit must never be blocked because unrelated
     old worktrees exist; that would be a ship-stop for a hygiene problem, the same error class as
     the 2026-07-25/26 required-status-checks incident. The §5 checklist row above is what carries
     it instead. (§4.11's gate-before-refactor rule does not apply here: retirement is neither a
     refactor nor gate-shaped.)
   - The harness may ALSO auto-clean unchanged worktrees on its own, so the count dropping without
     anyone acting is expected rather than alarming. It appears to apply the same
     leave-dirty-trees-alone rule; this was observed, not documented by the vendor, so do not rely
     on it as the cleanup mechanism.
   - **Leg 2 must see IGNORED files too.** `git status --porcelain` EXCLUDES them and
     `git worktree remove` does NOT refuse on them — verified 2026-08-09: a merged worktree holding
     an ignored `secrets/.env` classified "merged + clean + pushed", removed with exit 0, file
     gone. The tool reads `--ignored=matching` and keeps the worktree unless every ignored path is
     regenerable (`.env`, `build/`, `.dart_tool/`, …). Regenerables are excluded deliberately:
     point 1 copies `.env` into EVERY worktree, so counting them would make nothing retirable.
   - Tooling: `scripts/retire_worktree.dart` + pure `scripts/retire_worktree_lib.dart`; tests
     `test/scripts/retire_worktree_lib_test.dart` (predicate) and
     `test/scripts/retire_worktree_e2e_test.dart` (real linked worktrees). **Mutation-proven on
     BOTH protective legs** — neutering the dirty check reddens 7 tests (5 unit + 2 e2e), the ignored check 4
     (2 + 2), and reverting the exact-path match to prefix matching 4. A gate whose test never fails is the Gate-44 lesson.

7. **`core.worktree` must never be set (added 2026-08-09, diagnose `a4f7c2`).** Point 1's guarantee
   — "a worktree has its OWN index, so mixing is structurally impossible" — holds only while
   nothing overrides per-worktree resolution. On 2026-08-09 the SHARED `.git/config` carried
   `core.worktree = .../worktrees/post38-auth-fixes`, so every git command in all 102 worktrees
   resolved against that one branch's files. `check_commit_from_worktree.dart` passed cleanly
   throughout: it compares `--git-dir` to `--git-common-dir`, and those stay correct. Gated now by
   `scripts/check_worktree_config_integrity.dart` on every commit (fails OPEN when git cannot
   answer, so an environment quirk cannot wedge all work).

8. **Retirement is AUTONOMOUS once the pipeline lands (founder directive 2026-09-29).** Point 6's
   prose was written for a plain-shell `cd`-based session and never anticipated a harness that
   scopes a worktree as its OWN session with its own exit gate (Claude Code's `EnterWorktree`/
   `ExitWorktree` tool pair — `ExitWorktree`'s own instructions say "do NOT call this proactively
   — only when the user asks"). That created a real gap: an agent working per point 1 (own
   worktree) structurally could not also satisfy point 6 (retire from primary after merge)
   without either overriding the tool's own gate on its own initiative, or leaving it as a manual
   ask — which is what happened twice (`reps-secs-invalidation-fixes`, 2026-09-28;
   `schedule-status-single-writer`, 2026-09-29). The founder closed the gap explicitly: **once
   the FULL pipeline for THIS session's own branch has landed — committed, pushed, merged to
   `main`, CI confirmed green — retire that worktree immediately and report it DONE, never as a
   request for the founder to run manually.** This is a standing, forward-looking authorization
   (it satisfies `ExitWorktree`'s "only when the user asks" condition once, durably, rather than
   per-instance) and is scoped tightly: it authorizes retiring THE WORKTREE THIS SESSION JUST
   FINISHED, nothing else — never a sweep of other worktrees found lying around (`KEEP`/`ORPHAN`
   entries belonging to other branches or sessions are still reported and LEFT ALONE, exactly per
   point 6's own rule). If the four-legged predicate itself fails (genuinely dirty, unmerged, or
   unpushed), that is still a real stop-and-report case — the automation removes the ASKING for
   the already-safe case, never the safety check itself.
   Sequence: `ExitWorktree({action: "keep"})` (never `"remove"` — that skips this repo's own
   ignored-file/orphan checks) → from primary, `dart run scripts/retire_worktree.dart <slug>`
   (dry-run) → if it reports `[branch not merged]` despite a confirmed merge, check primary's
   local `main` for staleness first (see the §4.9 pitfall row below) before assuming anything is
   actually wrong → `--execute` once the dry-run shows `[merged + clean + pushed]`. (See also the
   main-sync `SessionStart` warning, §7 `discipline_hook.dart` row — that one covers the same
   local-vs-`origin/main` drift class at session-boundary time; this point covers it at the
   different, mid-session, post-`ExitWorktree` moment retirement actually needs it.)

