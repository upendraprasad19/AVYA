---
branch: coach-media-consent
date: 2026-07-30
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/328f36382e7b-review.md
---

# Plan review — coach-media-consent

Unit 8 of the OI-25/44/45/46/48/50 batch. The `coach-media` Storage bucket (migration 070,
2026-05-17) sat with owner-only RLS and zero client writers for 74 days — the founder's own
consent-flow design note in that migration's header was never implemented. This branch builds it:
a save-consent chip on AI-coach photo chat bubbles, `CoachMediaRepository` copying
`chat-media` → `coach-media` on consent, and a Saved Photos gallery screen. Investigation before
implementation surfaced two prerequisite gaps the plan hadn't anticipated (the success-path user
photo bubble never carried `coachKey`; the only persisted photo reference was a 600s-TTL signed
URL, unusable as a copy source) and fixed both as part of the same unit. Tier is `platform`:
`scripts/blast_radius_from_diff.dart` classified the diff above the plan's own pre-diff `account`
estimate, both before and after all three review rounds added files.

## Rounds

| Round | Outcome |
|---|---|
| 1 — independent, context-blind (general-purpose agent), on the first-draft diff | **PASS.** 3 findings, all fixed: (P2) `_onDeclineCoachMedia` had no guard against a concurrent in-flight `_onSaveCoachMedia` for the same photo — a decline landing mid-save would be silently clobbered back to `'saved'` once the save's unconditional write completed; fixed with a `_savingCoachMediaKeys` in-flight guard. (P2) The diagnose-doc understated the restore/sync gap — traced `sync_coach.dart`'s actual push/restore payloads directly and found the real consequence is total loss of the photo reference on a restored device (no thumbnail, no chip), not a mere re-prompt; corrected. (P3) A stale "2 lints fixed" claim — flutter analyze found a 3rd `unintended_html_in_doc_comment` instance the first cleanup pass missed; fixed and the claim corrected. |
| 2 — independent, context-blind (general-purpose agent), on the round-1-hardened diff | **PASS.** Independently re-verified all 3 round-1 fixes by reading the current code (not trusting round 1's description) and confirmed each closes what it claims. Found 7 new P3 issues, none P0/P1, all fixed per this batch's own no-deferrals discipline (applies regardless of severity tag): a live-queried `pg_policies` check found `chat-media` had NO authenticated-DELETE policy at all, so `saveForLater`'s free-tier cleanup had been silently RLS-denied on every call — migration 116 adds the missing policy; a non-idempotent `.copy()` retry path that would report an already-saved photo as failed after a network blip — fixed with a `_destinationExists` check; a missing in-flight visual signal on the save tap (this repo's own documented save-confirmation pitfall) — added `ChatBubble.isSavingMedia`; the round-1 race guard was one-directional — `_onDeclineCoachMedia` now takes the same lock for full mutual exclusion; 3 stale `docs/sot_registry.yaml` line-range citations this batch's own diff shifted (one a genuinely pre-existing, unrelated inaccuracy caught in passing while fixing the adjacent entry); a stale test count; doc framing that overstated how often the free-tier delete branch fires. |
| B-pass — fresh context-blind (sonnet, `/code-review` skill, 5 lenses) | **PASS → accepted.** 3 findings, all fixed (detail in `docs/reviews/328f36382e7b-review.md`): (P1) the OI-25 closure text and diagnose-doc both claimed the restore/sync gap was "flagged as a separate follow-up task," citing only a `spawn_task` session-UI chip — not a durable, git-tracked artifact, so once OI-25 closed nothing in the repo pointed at the gap anymore; filed **OI-77** and corrected both texts to cite it. (P2) `SavedCoachPhotosScreen._delete()` gave no user feedback on a failed delete — inconsistent with this same batch's own `_onSaveCoachMedia` failure-feedback pattern; added a SnackBar. (P3) `saveForLater`'s doc comment cited `attach_button.dart` as a live PRO-gate entry point; it is dead code (`// ignore: unused_element`, explicit "no longer wired" comment) — corrected to name the two genuinely live gates. Also independently re-ran `blast_radius_from_diff.dart` and live-queried `pg_policies` to verify migration 116's claims — both confirmed clean. |

## Why this is converged rather than merely green

Three consecutive rounds, three consecutive sets of NEW findings, each genuine and
non-overlapping with what the prior round caught — and, notably, escalating in a specific
direction: round 1 found bugs in the FEATURE LOGIC (a race, an understated doc claim); round 2,
reviewing the hardened diff, found bugs in the INFRASTRUCTURE the feature logic assumed was solid
(a live RLS gap neither round 1 nor the original plan had verified, a non-idempotent network
retry path); the B-pass, using a differently-framed lens checklist rather than an open-ended
"review this diff" prompt, found a PROCESS-INTEGRITY gap — a closure claim that was true in
spirit (a follow-up chip really was raised) but false in the durable sense the codebase's own
audit-trail discipline actually requires. Each round genuinely deepened the review rather than
re-finding the same class of issue, which is the signal this record treats as convergence rather
than just "three passes came back clean." Every fix at every round was verified by re-running the
actual test suite and `flutter analyze` afterward, not assumed correct from the finding's
plausibility alone — 44 tests green after the final round (across 6 files), up from 26 before
round 1 started; the SoT registry parity gate and the diagnose-doc validator both re-run clean
after every round's edits, not just the last one.

## Ground truth

Verified directly against live systems and files, not taken from any round's own prose: the
`chat-media` bucket's actual RLS policy set was read via a live `pg_policies` query against
`dedsavbjuwgarrhphgnl` (twice — once by round 2, independently re-confirmed by the B-pass) rather
than assumed from migration 070's text, which only documents `coach-media`'s policies;
`ChatHistoryNotifier.build`'s and `completeWorkoutFromPrompt`'s real line ranges were read
directly from `ai_coach_provider.dart` after this batch's own edits shifted them, not estimated
from the diff size; `sync_coach.dart`'s push (`_syncCoachInteractions`) and restore
(`_restoreCoachInteractions`) payloads were read character-for-character to settle exactly which
fields do and don't round-trip, twice (round 1's initial finding, the B-pass's independent
re-derivation before proposing OI-77); `attach_button.dart` was read in full to confirm it is
genuinely dead code before removing it from a doc citation, not assumed from its filename;
`storage_client`'s installed package source (`.copy()`'s actual request shape) was read directly
to design the idempotent-retry fix rather than guessed from the Supabase REST API's general
reputation.

## Residuals, stated

- **OI-77** (filed this batch): AI-coach chat photo references (`media_url`, `media_type`,
  `media_storage_path`, `media_save_state`) never round-trip through `sync_coach.dart`'s push or
  restore payloads — pre-existing, not introduced by this batch, but only became independently
  actionable once this batch's own investigation surfaced it. A historical photo message degrades
  to caption-only text after a cross-device restore. Whether this is an oversight or a deliberate
  scope-limit on what channel gets cloud-synced was not determined — that judgment call belongs to
  OI-77's own investigation, not a guess baked into this unit.
- Migration 116 (chat-media DELETE-own RLS policy) is written, reviewed, and pinned by tests, but
  **not yet applied live** — per CLAUDE.md §4.3, live apply requires its own separate explicit
  authorization, requested after this review converged, not assumed from plan/batch approval. See
  the "Post-review" section below once that happens.
- `SavedCoachPhotosScreen`'s null-`signed_url` and delete-fails-to-refresh-silently-until-retried
  behaviors (round-2 review, risk area D) are byte-for-byte the existing `ProgressPhotosScreen`
  pattern — real gaps, but pre-existing precedent this unit did not introduce, and out of scope to
  fix unilaterally in a sibling screen's shared idiom.
