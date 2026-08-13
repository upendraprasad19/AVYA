- 2026-06-26 · strategic-compact · trigger: batch ship (4 units merged to main: recovery/D/E/AI-chat) + phase boundary (docs phase F next) + deep marathon context · founder: ACCEPTED (ran /compact)
- 2026-07-28 · strategic-compact · trigger: explicit founder invocation at session open, ahead of backlog triage — no batch had shipped yet, so the preserve list was thin (branch + open-OI set only) · founder: ACCEPTED (ran /compact)
- 2026-07-28 · strategic-compact · trigger: batch ship (gate-input-family `0bd234c7` + oi58-version-bump-lines `dd966f55` both merged to main; 16 Edge Functions deployed) + follow-up continuing in-session + heavy context pressure · founder: ACCEPTED (ran /compact)

> **Trigger-tuning note (2026-07-28).** Of three invocations to date, two fired on
> "batch ship + work continues" and one on explicit ask. The batch-ship trigger is
> carrying the skill; the "parallel subagent dispatch returned" condition has never
> fired once. Worth watching whether it ever does before treating it as a real
> trigger rather than an aspirational one.

- 2026-08-01 ~09:15 IST — trigger: **batch ship** (Unit 5 merged `d229c012`, CI green,
  follow-up units continuing in-session) + long session. Founder ACCEPTED (ran /compact).
  Note: the skill's own step-6 logging was blocked that round because plan mode was active
  and only the plan file was writable — this line is the retroactive entry.
- 2026-08-01 ~11:40 IST — trigger: **explicit** (`/strategic-compact`) + context pressure,
  mid-batch with **nothing committed**. Distinct from every prior invocation: previous ones
  fired at a clean boundary where git history WAS the durable record. Here `HEAD` is
  unchanged and the batch lives only as 24 staged files in a worktree + a failure log in
  /tmp, so the preserve-list is load-bearing rather than a convenience. Founder decision:
  pending at time of writing.
  → Tuning signal: the skill's trigger list assumes a *clean* boundary ("last commit landed",
    "batch has shipped"). It has no entry for "context exhausted mid-batch with a red suite",
    which is the riskiest moment to compact and the one most needing a curated preserve-list.
    Worth adding as an explicit trigger.

- 2026-08-01 — /strategic-compact — trigger: batch shipped (Unit 9 / OI-79 complete end-to-end:
  merge `0545f0a5`, CI green on that SHA, 16 Edge Functions deployed + version-verified) plus
  context pressure. A genuinely clean boundary, unlike the same day's earlier invocation where
  nothing was committed. **Founder ACCEPTED** (ran `/compact` after the list was surfaced in chat).
  → Tuning signal (SECOND occurrence): the skill was invoked while **plan mode was active**, which
    forbids writes — so step 6's own logging step could not run, exactly as it could not run
    earlier the same day. Both times it had to be back-filled afterwards. The skill should either
    state that its log entry is deferred under plan mode, or the log-append should not be step 6
    of a skill that is frequently invoked from a read-only context.
  → Process error worth recording: under plan mode I ended the turn with `ExitPlanMode`, treating
    the preserve/drop list as an implementation plan needing approval. It is not — ExitPlanMode's
    own guidance excludes non-code/research tasks. Founder rejected it. The skill's step 4 wants a
    plain chat message and an explicit go-ahead, nothing more. If this skill is invoked in plan
    mode again: surface the list in chat, do not route it through ExitPlanMode.

- 2026-08-02 — /strategic-compact — trigger: **batch ship** at a genuinely clean boundary (Unit 3c +
  task #41 merged `87ddfd0a`, CI green on that SHA, **OI-45 closed**; Units 7 and 6 still to come
  in-session). **Founder ACCEPTED** (ran `/compact`), then immediately chained
  `/consolidate-memory`.
  → Tuning signal RESOLVED — the plan-mode one logged twice above. Plan mode was NOT active this
    round, so step 6 ran inline instead of being back-filled, and step 4 went to plain chat with no
    ExitPlanMode temptation. Both prior occurrences were plan-mode artifacts, **not** a defect in
    where step 6 sits. Leaving step 6 where it is; the fix that actually worked was "don't invoke
    this skill from plan mode."
  → New tuning signal: the highest-value preserve-list entries were NOT the git facts — `main`, the
    SHA, and CI state are all durable in git and in the retrospective, so preserving them is nearly
    free. What genuinely only existed in conversation were the **founder decisions** (the Gate 43
    allow-list call; the Edge Function deploy authorization) and the two open OIs with their
    *scoping questions* (OI-83's "is a restore allowed to lower the phase?" is a product call that
    no artifact records). Worth promoting "founder decisions made this session, and the reasoning
    behind them" from an implicit sub-bullet of step 2 to its own named preserve category — it is
    the one category with no durable home outside the transcript.
  → Follow-on: `/consolidate-memory` ran straight after and took `MEMORY.md` 18,408 → 17,130 bytes.
    Pairing the two at a batch boundary works well — compaction decides what conversation state
    survives, consolidation decides what cross-session state survives, and both want the same
    "what's actually still open?" answer. Retrospective:
    `memory/project_memory_consolidation_2026_08_02.md`.

- 2026-08-02 — /strategic-compact — trigger: **batch ship** (Unit 7 / OI-50 merged `4a994071`,
  CI green on that SHA, board at 25 open) with follow-up work (Unit 6) continuing in-session ·
  founder: **ACCEPTED** (ran `/compact`).
  → Preserve list led with the *owed* item rather than the shipped one: Unit 7's §5 per-batch
    maintenance (retrospective + `MEMORY.md` line) had NOT been written, and compaction would have
    discarded exactly the material that memory file is made of. Surfacing "what this compaction
    would destroy that has no durable home yet" ahead of "what shipped" is the more useful ordering
    — the shipped facts are already in git. Recommended writing the retrospective first; founder
    compacted immediately instead, so the preserve list carried it and it was written on the first
    writeable turn after.
  → Durable-lesson category earned its keep again: the highest-value preserve item was a **process
    hazard**, not a fact — a round-2 reviewer ran its own gate negative control by injecting a
    violation into `week_selector.dart` and "reverting" it, which restored the file to git HEAD and
    silently wiped that batch's edit. Nothing in git records that, because the recovery landed
    before the commit. Now in `memory/project_unit7_exlog_aggregate_read_2026_08_02.md`.
  → **Third** invocation in a row where plan mode blocked this skill's own step 6 (append to this
    file). The skill's logging step is unreachable from the mode the skill is most often invoked
    in. Not a one-off any more — worth changing the skill to log on the first writeable turn *by
    design* rather than treating it as a deferred exception each time.

- 2026-08-03 — /strategic-compact — trigger: **batch ship** (Unit A / OI-83 merged `ca4ef2c3`,
  OI-85 opened, board at 25) with Unit B continuing in-session · founder: **ACCEPTED** (ran
  `/compact`).
  → **The single most valuable thing this invocation did was disprove its own headline.** Step 2
    says preserve "last commit SHA" + CI state. While gathering that, checking CI with the FULL
    40-char SHA returned `conclusion: "failure"` — `main` was red, on a plan-review-record job
    failing against the *earlier* merge `b8e9bf3b`, whose embedded `bpass_review:` pointer is
    stale at that commit. A preserve list written from the assumed-good state would have said
    "shipped, CI green" and compaction would have made that the durable record of a red `main`.
    **Tuning: step 2 must VERIFY the git/CI facts at gather time, not transcribe them from
    earlier in the session.** They are the entries most likely to be assumed rather than checked
    precisely because they feel free to preserve (the 2026-08-02 entry above says exactly that —
    "nearly free" — and this is its counter-example).
  → Same root cause as two other misses this session, now three instances of one class: **a green
    check is only as wide as its input set.** A `| head -20` completeness grep, a staged-scoped
    gate run on a clean tree, and here a local `check_plan_review_record_exists.dart` run over
    `HEAD^1..HEAD` while CI walks the whole pushed range. All three passed vacuously.
  → **Fourth** consecutive plan-mode block of step 6 — but logged on the first writeable turn *by
    design* this time, per the previous entry's own recommendation, rather than as a deferred
    exception. Treating that as the resolution: the skill's step 6 stays where it is, and
    "unreachable in plan mode → log on first writeable turn" is now the expected path, not a miss.
  → Also carried: founder's scope decision on Unit B (hoist + extract the phase-2 preview card,
    not the OI-84-literal hoist alone) and the arithmetic behind it — OI-84's own "~770 lines"
    estimate went stale when Unit A grew the file to 909. A board item's numbers age; re-measure
    before planning against them.

- 2026-08-05 — /strategic-compact — trigger: **batch ship at a verified-clean boundary** (Units A
  and B on `origin/main` `d825c0b5`, CI green, nothing unpushed, pending-list just re-verified) ·
  founder: **ACCEPTED**.
  → **The 2026-08-03 tuning note was applied and it paid off immediately.** That entry said step 2
    must VERIFY the git/CI facts at gather time rather than transcribe them from earlier in the
    session. Doing so this round turned up two things a transcribed list would have gotten wrong:
    the six commits I last knew as "blocked, unpushed" had in fact all landed, and the blocker
    (`docs/plan-reviews/onboarding-oauth-session-fix.md`) now exists — so the preserve list said
    "shipped and green" because it was checked, not because it was assumed.
  → Second application of the same rule, one layer down: while verifying the one remaining
    blocking item I grepped the live Edge Function rather than the repo, and found version 10
    still missing all three of Unit A's op-types. A repo-only check would have reported the
    deploy as done. **Preserve lists should carry the EVIDENCE for a blocking item, not just its
    name** — "log-client-error undeployed" is forgettable; "live v10's list ends at
    `streak_freeze_lapse_reset`, and OI-85's decision depends on that signal" is actionable after
    a compaction.
  → Also caught with the same reflex: my own first grep for those op-types searched a name that
    was never in the list (`phase_unlock_preempted_before_generate`) and would have had me report
    "2 of 3". Diffing the actual commit gave the true answer. Sixth instance this week of
    `feedback_green_check_input_set_width` — the check was narrower than the claim it tested.
  → Step 6 logged on the approving turn, not deferred: the line records whether the founder
    accepted, so it CANNOT be written before the answer arrives. That resolves the "log on the
    first writeable turn" ambiguity from the previous four entries — the constraint was never
    plan mode, it is that the outcome is an input to the record.
  → Written from a worktree, not the shared main folder. An uncommitted file in shared `main` is
    the exact cross-session hazard filed as OI-87 this week (another session's `git add -A` sweeps
    it into their commit). Cheap to avoid; embarrassing to hit two days after filing it.
- 2026-08-05 — /strategic-compact — trigger: **phase boundary** (Unit 2's review phase closed —
  ×2 context-blind rounds + self-initiated B-pass all complete, diagnose-doc + closure YAML +
  plan-review record + B-pass record written and validating) **+ heavy context pressure** after a
  long multi-unit session (Unit 1 replay/merge/push, OI-89/90 filed, Unit 2 reviewed).
  Boundary is real but NOT a ship: Unit 2's 17 files are still uncommitted, so the preserve list
  had to carry live uncommitted state rather than just a merged SHA. · founder: ACCEPTED (ran /compact)
  → Preserve list led with the three environment rules that cost the most time today, because
    each was a *false signal* rather than a bug: a background task reporting "exit code 0" for a
    commit the gate had refused; `ALLOW_RAW_GIT` exported around a test run leaking into
    `git_safety_hook_integration_test.dart`'s subprocess and failing 3 tests that assert the hook
    denies raw git; and `git checkout <file>` used to undo a scratch edit, which reverts to HEAD
    and silently discarded an uncommitted fix (use a byte-copy).
  → Also carried, as the batch's durable lesson: a completeness claim must cite **the command and
    its input set**, not prose. Unit 2's citation-sweep count was wrong THREE times (2 → 3 → 8 →
    20) because each correction added the site it was handed instead of re-deriving. And the
    filter itself ("citations outside §0-§7") is structurally blind to the **wrong-but-live**
    class — a citation resolving to a real but incorrect section — which is the class the batch
    argued is worse than a dead pointer. Two were found only by reading, never by grepping.
  → Third carry: bounds-checking is strictly weaker than correctness. The comment trim invalidated
    three `restoring_screen.dart` `line_range:` entries in `docs/sot_registry.yaml`, and BOTH
    registry gates passed, because they only assert `end <= lineCount` and the stale ranges stayed
    in bounds. Same branch simultaneously repointed the writer-reader-drift-detector agent AT that
    registry.
- 2026-08-05 (2nd invocation of the day) — /strategic-compact — trigger: **batch ship at a
  clean boundary** (log-client-error v11 deploy + board sweep merged as `d548e698`, CI green,
  tree clean) after a session that ran four distinct phases (deploy → board sweep → ranked
  triage → verification sweep) · founder: **ACCEPTED**.
  → **The gather-time-verification rule paid off a third time, on a smaller scale.** Re-reading
    state instead of transcribing it caught `MEMORY.md` at 20,706 B when I had said 20,261 B
    earlier in the SAME session — it had grown between the two statements. Trivial in isolation,
    but it confirms the rule holds even for facts measured minutes ago, not just facts inherited
    from before a compaction.
  → **Refinement to what a preserve list should lead with.** The single most valuable item this
    round was not a state fact but a DEPENDENCY: no shipped APK emits the 7 telemetry op-types
    the v11 deploy just prepared the server for, so OI-85's measurement cannot start and an empty
    `client_errors` count reads as "rare" when it actually means "dead pipeline". A list of true
    facts would have preserved "v11 is live" and lost the thing that makes it not yet useful.
    Lead with what is blocked on what, then state.
  → **Sessions that query live infrastructure generate far more droppable bulk than code
    sessions.** The drop list was dominated by two full Edge Function source dumps and a
    41-function `list_edge_functions` JSON — none of which carry information the conclusions
    don't already hold. Worth expecting: an ops/verification session has a much better
    drop-to-preserve ratio than an implementation session, so the compaction is cheaper and
    should be reached for sooner.
  → **Step-6 timing held.** The log line records accept/decline, so it cannot be written before
    the founder answers. Resolved in the previous entry, applied here without re-litigating.
  → Written from the worktree, riding with the unpushed OI-56 commit so both land in one push
    rather than two CI cycles.

- **2026-08-07 ~13:40 IST — `post38-auth-fixes`, mid-batch, ACCEPTED (suggestion approved;
  founder's `/compact` then reported "Compaction canceled", so this records approval of the
  curated list, NOT that a compaction ran).**
  Trigger: round-2 fan-out returned AND a governing invariant had fired with a founder decision
  pending — §4.12.1 ("successive reviews keep surfacing new material issues ⇒ the unit is too
  large; split it"). Round 1 produced 16 findings, round 2 produced 11 more, and the decisive
  signal was not the count but that round 2's findings were largely defects introduced BY
  round 1's fixes. Diverging, not converging.
  → **New trigger worth adding to the skill's list: "a governing invariant has fired and a
    founder decision is open".** The skill currently lists phase-boundary / fan-out / ship /
    explicit / context-pressure. None of those is the reason this one mattered. An open scope
    decision is the highest-cost thing to lose, because after compaction the decision looks
    already-made in whichever direction the summary happens to lean.
  → **A MISLEADING GREEN STATE is a distinct preserve category, and worse than an unknown one.**
    Previous entries established "lead with the prohibition, because rules leave no artifact".
    This session sharpens it: the tree here is not merely silent about its problems, it actively
    argues FOR merging — 16/16 tests green, `flutter analyze` 0/0, six diagnose-docs passing
    their validator — while carrying three P1s verified against source (a telemetry cooldown
    that silences the very lane it was built for; an OAuth hang path outside its own try; a
    guard test that passes with all 16 guard call sites deleted). A future session doesn't just
    lack knowledge, it holds positive evidence pointing the wrong way. When green signals and
    truth disagree, the preserve list must say so FIRST and name the specific file:line, or the
    green wins by default.
  → **Live-vs-repo divergence is a preserve item in its own right.** Prod is AHEAD of the branch
    (migration 119 hand-applied and absent from `schema_migrations`; `log-client-error` v12
    deployed) while the repo has zero commits. Losing that invites a re-apply or a re-deploy.
  → **Mid-review tool loss belongs on the preserve list too.** The Supabase MCP disconnected
    between round 2 and this invocation, so every live claim in the diagnose-docs is currently
    unverifiable. That is a fact about what CANNOT be checked, which no artifact records.
  → Step-6 timing held again (3rd consecutive): the outcome is an input to this line, so it is
    written after the founder answers. Noting that the answer here was two-part — suggestion
    accepted, compaction itself cancelled — which is exactly the ambiguity that would have been
    guessed wrong had this been written in advance.
  → Written in the worktree, not the shared main folder. ⚠ `docs/superpowers/skills-log.md` also
    has an UNCOMMITTED edit sitting in the primary worktree from the previous session; these two
    copies will need reconciling before either lands.
