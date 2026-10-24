---
bug_id: f4a7c2
date: 2026-07-30
batch: coach-media-consent
status: implemented
blast_radius: platform
symptom: >
  OI-25 (2026-05-17, founder's own product note in migration 070's header:
  "i intend to store coach uploaded media. We ask user does he want to
  store the pic for future reference and on consent we save it.") shipped
  the bucket + RLS (migration 070) but never the client-side consent flow
  — the `coach-media` bucket existed with zero writers for 74 days. Unit 8
  of the OI-25/44/45/46/48/50 batch builds the missing flow: a save-consent
  chip on the AI coach's photo chat bubble, a repository that copies the
  blob from the transient `chat-media` bucket into the long-term
  `coach-media` bucket on consent, and a Saved Photos gallery screen.
  Investigation before writing any code (chat_area.dart, ai_coach_provider.dart,
  media_picker.dart) surfaced a genuine PRE-EXISTING writer/reader gap this
  feature depends on closing: `ChatHistoryNotifier.build()`'s success-path
  USER bubble never carried `coachKey` — only the AI/error bubble did (for
  Retry). Without it, nothing could key a Hive write back to the exact
  `coach_<ms>` row that carries a given photo's `media_url`, which is what
  the consent chip's tap handler needs. A second, related gap: the only
  value ever persisted for an uploaded photo was a 600-second signed URL
  (`media_url`) — already expired by the time a user would plausibly decide
  whether to keep it, and unusable as a `Storage.copy()` source path.
concept: coach_media_consent
sot_registry_entry: >
  Extended the existing `coach_interactions` entry in docs/sot_registry.yaml
  (not a new concept there — the two new fields live on the SAME coach_<ms>
  row) with a new writer (CoachInteractionRepository.recordMediaSaveDecision,
  line 139-147) and updated the ChatHistoryNotifier.build reader's
  fields_read list. Added a new lighter-weight SoT contracts table row,
  `coach_media_consent`, to lib/features/ai_coach/CLAUDE.md — matching the
  precedent set by the pre-existing `chat_media_signed_url` row in that same
  table (a single-writer/single-reader Storage concept, correctly scoped
  below the heavier docs/sot_registry.yaml schema, same as that sibling).
  Backfilled a pre-existing gap in docs/naming_conventions.md §3.3: the
  `coach_` Hive key prefix itself (used since well before this batch) had
  no row in the prefix registry table at all — added one, documenting both
  the pre-existing fields and this batch's two new ones.
  scripts/check_sot_registry_parity.dart WARNs that CoachMediaRepository
  (a *Repository class) isn't mentioned anywhere in docs/sot_registry.yaml
  — accepted, not fixed: the class is Storage-only (no Hive box, no
  Postgres table/columns), so it has no natural fit in that schema's
  cloud_table/cloud_columns/sync_methods/restore_methods fields; forcing
  an entry would mean populating several fields with not_applicable
  boilerplate to silence an advisory (WARN, not FAIL) check rather than
  documenting anything real. It IS fully documented in the lighter
  lib/features/ai_coach/CLAUDE.md table, the correct scope for this
  concept per the precedent above. Ran the gate directly and confirmed 0
  FAIL-level findings after fixing 2 genuine stale-line-range errors it
  caught (both pre-dated this note — see round-2 findings): one in this
  same edit (a Class.method-shaped method: field makes the checker
  require the CLASS name's own literal text inside the cited range, not
  the method's; fixed by citing the bare method name, matching this
  file's own working convention elsewhere), one in
  ai_coach_provider.dart's UNRELATED completeWorkoutFromPrompt entry
  (254-337 → 341-392) — this batch's own ~60-line insertion above it
  shifted the citation, and my earlier manual grep-based sweep (which
  searched only for "ChatHistoryNotifier" mentions) missed it; the
  automated gate caught it comprehensively where the manual pass didn't.
writers: >
  lib/features/ai_coach/repositories/coach_interaction_repository.dart
  saveUserMessagePending (line 88-130, extended with a new mediaStoragePath
  param written as media_storage_path) and the new recordMediaSaveDecision
  (line 139-147, UPDATE-not-INSERT in place on the same row, mirrors
  updateInteractionWithResponse's shape). Forwarder shim
  lib/features/ai_coach/repositories/ai_coach_repository.dart (both methods
  threaded through — the shim silently dropping a new param was the exact
  failure mode that would have made mediaStoragePath vanish between
  media_picker.dart and the actual Hive write; caught by grepping for every
  saveUserMessagePending( callsite, not assumed).
  lib/features/ai_coach/providers/ai_coach_provider.dart:
    - ChatHistoryNotifier.build() — the user-bubble branch now sets
      coachKey (previously absent on this path — see symptom) plus three
      new ChatMessage fields (mediaStoragePath, mediaAnalysisComplete
      computed from the SAME row's pending/failed/ai_response state,
      mediaSaveState read straight from the row).
    - ChatMessage gained a copyWithMediaState() method (pure field-copy,
      null args = keep existing value) and a new
      ChatHistoryNotifier.updateMessageMediaState() method — needed because
      replaceLastMessage() (the existing in-memory update primitive) only
      ever swaps the TRAILING bubble when an AI reply lands; the user's own
      photo bubble sits earlier in the list and would otherwise never see
      mediaAnalysisComplete flip to true until the next full Hive rebuild
      (app restart / auth change) — the chip would silently never appear
      during the live send that triggered it.
    - SendMessageNotifier.sendWithMedia — accepts mediaStoragePath, sets
      coachKey on the optimistic ChatMessage it adds immediately (same gap
      as the rebuild path, fixed in both places), calls
      updateMessageMediaState(mediaAnalysisComplete: true) right after
      updateInteractionWithResponse succeeds.
  lib/features/ai_coach/screens/ai_coach/media_picker.dart — captures
  `storagePath` at upload time (line ~226, pre-existing local var, was
  previously only used to build the signed URL and never threaded further)
  and now also passes it as mediaStoragePath to sendWithMedia.
  lib/features/ai_coach/repositories/coach_media_repository.dart (NEW) —
  saveForLater(chatMediaPath): Storage .copy() from chat-media to
  coach-media at the same relative path (both buckets share the
  `<uid>/<filename>` RLS layout, migration 070), then deletes the
  chat-media source only for free users (PRO retains both — mirrors, not
  special-cases, clean-orphan-media's own unconditional PRO skip).
  lib/features/ai_coach/widgets/chat_bubble.dart — new consent-chip render
  block (_buildMediaConsentChip / _buildMediaSavedBadge), gated on
  isUser && hasMediaUrl && !showFailedSlot && mediaAnalysisComplete &&
  mediaSaveState == null && onSaveMedia != null.
  lib/features/ai_coach/screens/ai_coach/chat_area.dart — wires the new
  ChatBubble params + two new handlers (_onSaveCoachMedia,
  _onDeclineCoachMedia) added to the same extension; both call through
  AiCoachRepository.recordMediaSaveDecision then
  ChatHistoryNotifier.updateMessageMediaState. _onSaveCoachMedia is guarded
  by a new _savingCoachMediaKeys in-flight Set (declared in screen.dart)
  against a rapid double-tap firing two concurrent Storage.copy calls —
  mirrors the `_saving` double-tap guard pattern the ai_coach CLAUDE.md's
  own common-pitfalls table already documents for the AI-breakdown-card
  save action.
readers: >
  lib/features/profile/screens/saved_coach_photos_screen.dart (NEW) —
  CoachMediaRepository.list() (Storage .list() + per-object
  createSignedUrl, 1-hour TTL, mirrors ProgressPhotoRepository.list()'s
  signed-URL pattern even though that repository is table-backed and this
  isn't — no metadata table per the founder's explicit call). Long-press
  to delete via CoachMediaRepository.delete().
  lib/core/router/app_router.dart — new nested GoRoute
  'saved-coach-photos' under the /profile StatefulShellBranch.
  lib/features/profile/screens/profile/profile_content.dart — new
  ProfileRow ("Saved Photos") in the REPORTS card, navigating to
  /profile/saved-coach-photos. Not PRO-gated at this row: only PRO users
  can ever produce content here (featurePhotoAnalysis gates chat-photo
  upload upstream), so a free user just sees an empty screen — inventing a
  second gate here would be a product-policy call the plan didn't ask for.
hive_key_prefix: "coach_ (pre-existing, unchanged — this batch adds fields, not a new prefix)"
hive_key_formula: "'coach_${DateTime.now().millisecondsSinceEpoch}' (unchanged). New fields on the same row: media_storage_path (string, raw chat-media path), media_save_state (null | 'saved' | 'declined')."
sync_methods: "_syncCoachInteractions (lib/core/services/sync/sync_coach.dart) — UNCHANGED and deliberately not extended. It pushes a fixed column subset (verified by reading it directly) that already excludes media_url/media_type/pending/failed alongside the row's other local-only bookkeeping fields; the two new fields fall into that same existing exclusion, structurally, not by a new guard added in this batch."
restore_methods: >
  _restoreCoachInteractions — unchanged. Round-1 review traced its
  hardcoded restore payload (sync_coach.dart:204-217) directly and found
  it ALREADY never restored media_url/media_type either, before this
  batch — its field list is id/user_message/ai_response/model_used/
  mode/is_user_message/created_at/channel/source only. The two new fields
  in this batch (media_storage_path, media_save_state) simply inherit that
  SAME pre-existing, symmetric behavior (confirmed the push side,
  _syncCoachInteractions, also never sent media_url/media_type —
  sync_coach.dart:149-156's upsert payload). Not a new gap this batch
  introduces; see impact_analysis for the corrected residual description
  (round-1 review's original finding: this doc's first draft understated
  what actually happens).
cloud_table: ai_coach_interactions
cloud_columns: "id, user_id, channel, user_message, ai_response, model_used, tokens_used, tool_calls, created_at — UNCHANGED. media_storage_path/media_save_state are deliberately absent from this list; see sync_methods."
contract_test_path: test/contracts/coach_media_consent_test.dart, test/contracts/coach_media_repository_test.dart, test/widgets/chat_bubble_media_consent_test.dart, test/router/saved_coach_photos_route_test.dart, test/contracts/ai_media_proxy_ssrf_allowlist_test.dart (extended), test/widgets/saved_coach_photos_screen_test.dart (NEW, B-pass finding 2)
ist_handling: not_applicable — no date-key, cloud `date` column, or counter reset touched by this batch.
provider_invalidations: not_applicable — chatHistoryProvider's own state update (updateMessageMediaState) is internal to itself; no cross-provider invalidation needed.
telemetry_op_types: "coach_media_save_for_later_failed (NEW, CoachMediaRepository.saveForLater's copy-failure catch block) — added to mirror media_picker.dart's own upload-failure telemetry (the closest precedent: the core mutating Storage op this repository exists to perform, failing), per feedback_operational_observability_first.md. list()/delete() deliberately left at debugPrint-only, matching ProgressPhotoRepository's own precedent for those two operations specifically."
cross_account_guard: not_applicable — no shared/global Hive key touched; all reads/writes are already inside the existing per-user coachBox / user-scoped Storage paths, and saveForLater/delete both defense-in-depth assert path ownership before touching Storage.
forbidden_patterns_checked: >
  Assumed the plan's exact micro-design (a NEW coachBox key hashed on the
  chat-media path) without checking whether the existing row already had a
  simpler, single-writer-consistent home for the same decision — it did
  (the same coach_<ms> row already carries media_url); reusing it avoids
  inventing a second bookkeeping mechanism for one concept. Assumed
  media_url (a signed URL) could be parsed back into a raw Storage path
  after the fact — it has a 600s TTL and no existing client-side URL
  parser to mirror (only the server-side ai-media-proxy has one); traced
  the actual upload flow (media_picker.dart) instead of guessing, found
  the raw path was already computed locally and simply never threaded
  through. Trusted the plan's line-number citations (chat_bubble.dart
  159-196/233-267) without re-reading the live file — re-read it directly;
  the Retry chip's real location (230-267) was close enough to the plan's
  estimate to confirm the file, but the exact insertion point for the new
  chip was determined by re-reading the render tree, not by trusting the
  cited range. Trusted supabase/functions/CLAUDE.md's stale SSRF-allowlist
  prose (progress-photos + chat-attachments) instead of reading
  ai-media-proxy/index.ts's actual ALLOWED_BUCKETS directly — read the
  live source, found chat-attachments has never existed in this codebase,
  fixed the doc, and added the test assertion that was missing (see
  regression_test_planned).
proposed_fix: >
  (1) CoachMediaRepository.saveForLater/list/delete — new Storage-only
  repository (no metadata table, per the founder's explicit call), copying
  chat-media -> coach-media on consent, listing coach-media directly for
  the gallery. (2) Prerequisite fix: thread the raw chat-media Storage
  path (already computed locally at upload time, previously discarded)
  through saveUserMessagePending as media_storage_path, and fix the
  pre-existing gap where the success-path user bubble never carried
  coachKey. (3) A save-consent chip on ChatBubble, gated so it only ever
  appears after the SAME row's AI analysis has resolved (founder's
  migration-070 design note), never re-appears once a decision is
  recorded, and never appears on a failed-photo bubble. (4) A live
  in-memory updateMessageMediaState() so the chip appears during the SAME
  send that triggered it, not only after the next Hive rebuild. (5) A new
  Saved Photos screen + route + Profile nav entry, listing directly from
  Storage. (6) Folded in a one-line doc fix (supabase/functions/CLAUDE.md's
  stale SSRF-allowlist bucket names) found while verifying the allowlist
  directly, per the plan's own explicit note to fold it into this unit.
  (7) Round-1 review fix: guarded _onDeclineCoachMedia with the same
  _savingCoachMediaKeys in-flight set _onSaveCoachMedia already used — a
  decline landing while a save for the same photo was still in flight
  could otherwise be silently clobbered back to 'saved' once the save's
  own completion wrote unconditionally. (8) Round-1 review fix: corrected
  this doc's restore_methods/impact_analysis, which had understated the
  pre-existing (not newly introduced) restore gap — see those fields.
  (9) Round-2 review fixes, all landed in this batch (none deferred):
  migration 116 adds the chat_media_delete_own RLS policy that was
  live-confirmed missing — saveForLater's free-tier cleanup call had been
  silently RLS-denied on every invocation since chat-media never had an
  authenticated-DELETE policy at all (mirrors coach_media_delete_own,
  migration 070's own shape, scoped to chat-media). saveForLater now
  treats a post-copy failure as success when the destination object
  already exists (a new _destinationExists check) — closes a
  retry-after-network-blip path that would otherwise report a
  successfully-saved photo as failed. ChatBubble gained isSavingMedia (a
  spinner + disabled tap targets during the save's network round-trip) —
  closes both a save-confirmation-signal gap (the repo's own documented
  pitfall) and, as a side effect, most of a reverse race,
  _onDeclineCoachMedia now takes the SAME _savingCoachMediaKeys lock
  _onSaveCoachMedia does (round-1's guard was one-directional) for full
  mutual exclusion. Corrected two stale docs/sot_registry.yaml line_range
  citations this batch's own diff shifted (ChatHistoryNotifier.build moved
  to 164-309) plus one further, genuinely pre-existing and unrelated
  inaccuracy caught in passing (a fields_read claim that build() reads
  model_used — it doesn't; corrected while already editing the adjacent
  entry, not scope-crept into new investigation). saveForLater's doc
  comment corrected to state plainly that the free-tier immediate-delete
  branch fires only in a PRO-to-free downgrade window (photo attach is
  PRO-gated at every entry point), not as the common case the original
  phrasing implied.
  (10) B-pass fixes: filed OI-77 (durable record) replacing the
  spawn_task-chip-only citation for the sync/restore gap; added a SnackBar
  on SavedCoachPhotosScreen's delete failure, mirroring
  _onSaveCoachMedia's own pattern from the same batch; corrected
  saveForLater's doc comment, which had cited attach_button.dart (dead
  code, `// ignore: unused_element`) as one of the live PRO-gate entry
  points.
regression_test_planned: >
  test/contracts/coach_media_consent_test.dart (behavioral, real Hive via
  test/helpers/hive_test_setup.dart) — mediaStoragePath persists;
  recordMediaSaveDecision writes saved/declined and no-ops on a missing
  key; a build()-simulated rebuild proves the user bubble now carries
  coachKey (the regression this unit closes) and mediaAnalysisComplete is
  false while pending/failed and flips true only once the SAME row
  resolves with a non-empty ai_response.
  test/contracts/coach_media_repository_test.dart — pure-Dart
  ChatMessage.copyWithMediaState round-trip (override-only-what's-passed,
  null-means-keep-existing) + source-grep pins on
  coach_media_repository.dart (copy targets coach-media via
  destinationBucket; free-tier-only source cleanup textually inside
  `if (!isPro)`; both saveForLater and delete assert path ownership;
  list() reads from coach-media not chat-media) — same source-grep
  approach test/contracts/chat_media_signed_url_test.dart already uses for
  the sibling chat-media upload path, since neither that repository nor
  ProgressPhotoRepository (the closest precedent) has a behavioral test of
  its own live Storage network calls in this codebase.
  test/widgets/chat_bubble_media_consent_test.dart — chip shows/hides on
  every gating dimension (analysis-incomplete, already-decided in both
  directions, onSaveMedia null, AI bubble, failed-photo bubble); tap
  handlers fire.
  test/router/saved_coach_photos_route_test.dart — route registered nested
  under /profile (not hoisted top-level, which would drop the bottom-nav
  shell); Profile nav row present and wired.
  test/contracts/ai_media_proxy_ssrf_allowlist_test.dart extended — pins
  the exact ALLOWED_BUCKETS set and asserts the phantom chat-attachments
  name is absent, closing the actual gap that let the CLAUDE.md doc drift
  stale in the first place (the pre-existing test only checked the
  /storage/v1/object/ URL prefix, never the bucket-name set itself).
  Round-1 review fix: test/contracts/coach_media_consent_test.dart
  extended with a source-grep pin (honestly labelled as such — no
  widget+Riverpod+Hive integration harness exists for this screen to
  simulate the actual async race against) confirming _onDeclineCoachMedia
  checks _savingCoachMediaKeys before its Hive write.
  Round-2 review fixes, same 5 files: coach_media_repository_test.dart
  gained 2 source-grep tests (the _destinationExists idempotency check
  fires before failure-telemetry; it checks the destination not the
  source bucket) + 2 more pinning migration 116's DDL shape (policy name/
  FOR DELETE/TO authenticated/ownership clause; idempotent DROP-then-
  CREATE). chat_bubble_media_consent_test.dart gained 5 widget tests for
  isSavingMedia (SAVING… label + bookmark-icon swap — NOT a
  CircularProgressIndicator type/count assertion, since CachedNetworkImage's
  own loading placeholder also renders one against this test's unreachable
  mediaUrl and would double-count; both tap targets inert while saving; the
  idle/default state still works normally). coach_media_consent_test.dart
  gained 2 tests pinning the new symmetric guard (_onDeclineCoachMedia now
  adds to _savingCoachMediaKeys before its write and releases in a finally,
  same as _onSaveCoachMedia; both handlers guard the SAME field).
  44 tests total across 6 files (42 after round-2's 11 new tests, +2 more
  from the B-pass's new saved_coach_photos_screen_test.dart), all green;
  flutter analyze clean on every touched file —
  round-2's setState calls (for isSavingMedia) needed a new file-level
  `// ignore_for_file: invalid_use_of_protected_member` in chat_area.dart,
  mirroring the exact documented precedent already in media_picker.dart /
  recording_body.dart for this same analyzer limitation (setState is
  @protected; the analyzer doesn't model "extension on the same State
  subclass" as an allowed call site even though the runtime semantics are
  fine) — caught by re-running flutter analyze after adding the setState
  calls, not assumed clean.
  Correction: this paragraph's first draft claimed "2
  unintended_html_in_doc_comment info-lints... fixed" — round-1 review ran
  flutter analyze directly and found a 3rd instance still live
  (chat_area.dart:150, introduced by the same `coach_<ms>` doc-comment
  phrasing in a file I hadn't re-analyzed after the first two fixes).
  Fixed; verified clean by re-running flutter analyze after, not by
  re-asserting the original (wrong) count.
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter analyze --no-fatal-infos clean on every touched/new file (0 issues on coach_media_repository.dart; only pre-existing-class info lints elsewhere, none newly introduced. Round-2 added 4 invalid_use_of_protected_member warnings via chat_area.dart's new setState calls — fixed with the same documented ignore_for_file precedent media_picker.dart/recording_body.dart already carry; re-confirmed 0 new issues after). 44 tests across 6 files, all green (flutter test run directly, not just planned)." }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "test/contracts/coach_media_consent_test.dart proves media_storage_path and media_save_state round-trip through real Hive (test/helpers/hive_test_setup.dart harness) via CoachInteractionRepository — same harness pattern as test/contracts/coach_interactions_behavioral_test.dart." }
  - { tier: 3_postgres_schema, status: fixed_in_this_batch, evidence: "coach-media bucket + its 3 RLS policies already existed (migration 070, confirmed by reading it directly) and needed no change. Round-2 review live-queried pg_policies on dedsavbjuwgarrhphgnl directly and found chat-media had only 2 SELECT policies + 1 INSERT policy — NO authenticated-DELETE policy — despite saveForLater's free-tier cleanup calling .remove() against it; migration 116 adds chat_media_delete_own, mirroring coach_media_delete_own's exact shape." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no Postgres row touched by this batch." }
  - { tier: 5_migrations_applied, status: deferred, evidence: "NOT a §4.2 no-deferrals violation — this is the standard, repeatedly-used pattern (migrations 114, 115 before it) where a migration is written + reviewed in-batch but its LIVE apply against dedsavbjuwgarrhphgnl requires its own separate explicit go-ahead per CLAUDE.md §4.3 (plan/batch approval is not deploy approval). Requested as its own explicit step before merge; backups/applied_migrations.json updated in the same commit as the apply, once authorized." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function code changed — ai-media-proxy/index.ts was READ to verify its live ALLOWED_BUCKETS set (confirmed chat-media/coach-media/progress-photos, matching what this batch's doc fix now says) but not edited; no redeploy needed." }
  - { tier: 7_cron_jobs, status: verified, evidence: "read clean-orphan-media/index.ts directly to confirm its 30-day chat-media cleanup only targets free-tier users (rechecksIsPro) and never touches coach-media — saveForLater's free-tier immediate source-delete is a complement to that cron (removes the duplicate early), not a conflict with it." }
  - { tier: 8_rls_policies, status: fixed_in_this_batch, evidence: "read migration 070 directly — coach_media_select_own/insert_own/delete_own policies (storage.foldername(name))[1] = auth.uid() cover every coach-media path this batch's client code uses. CORRECTED (round-2 review): this entry's first draft over-claimed 'every path' — it never checked chat-media, which saveForLater's cleanup step also touches. Live-queried pg_policies on dedsavbjuwgarrhphgnl directly (not assumed from a migration file): chat-media had only 2 SELECT policies (own + service_role) + 1 INSERT policy (own), NO authenticated-DELETE policy at all. Migration 116 adds chat_media_delete_own, closing the actual gap this tier's first pass missed." }
  - { tier: 9_storage, status: verified, evidence: "coach-media bucket (private, 5MB, image/jpeg+png+webp) confirmed pre-existing via migration 070's own DDL, read directly rather than assumed from the plan's claim." }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written by this batch." }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service (Razorpay/OneSignal/Firebase) touched." }
  - { tier: 12_client_server_contract, status: verified, evidence: "delete-account/index.ts's Storage purge loop (line 385) already iterates [\"progress-photos\", \"chat-media\", \"coach-media\"] — read directly, confirmed correct, no change needed. ai-media-proxy's ALLOWED_BUCKETS confirmed live to already include coach-media (the doc was stale, not the code)." }
impact_analysis: >
  Positive: closes OI-25 (open 74 days since the bucket/RLS-only migration
  070 landed with zero client writers). Closes a genuine pre-existing
  writer/reader gap (user bubble missing coachKey on the success path) that
  this feature depends on and that would otherwise have silently blocked
  any future feature needing to key a UI action back to a user's own photo
  message. Closes a real, previously-undocumented doc/code drift
  (supabase/functions/CLAUDE.md's SSRF-allowlist bucket names) and adds
  the missing test that would have caught it earlier — the pre-existing
  ai_media_proxy_ssrf_allowlist_test.dart only ever checked the URL-prefix
  defense, never the bucket-name set itself, which is exactly how the doc
  drifted unnoticed.

  CORRECTED by round-1 review (this doc's first draft mischaracterized the
  actual failure mode — documenting the correction rather than silently
  rewriting it, matching this batch's own precedent for board corrections):
  media_storage_path/media_save_state are LOCAL-ONLY, but so are
  media_url/media_type — round-1 review traced _restoreCoachInteractions's
  actual restore payload (sync_coach.dart:204-217) and _syncCoachInteractions's
  push payload (sync_coach.dart:149-156) directly and found NEITHER has
  ever included any media_* field, before or after this batch. This is a
  PRE-EXISTING gap this batch does not introduce or worsen — the two new
  fields simply inherit media_url/media_type's own already-established
  local-only behavior. The actual consequence on a restored device is NOT
  "the chip re-offers, redundant tap" (this doc's first-draft claim) — it
  is that a HISTORICAL photo message loses its ENTIRE media reference
  after a restore: with mediaUrl/mediaStoragePath both null, ChatBubble's
  hasMediaUrl gate is false and chat_area.dart's onSaveMedia wiring is
  null (gated on mediaStoragePath != null), so neither the image thumbnail
  nor the consent chip render at all — only the caption text survives.
  The photo itself is NOT lost (it still exists in chat-media/coach-media
  Storage, and any already-saved copy still appears correctly in
  SavedCoachPhotosScreen, which lists directly from Storage, not from any
  restored Hive state) — only its appearance in that one historical chat
  bubble on a restored device. This is a real, pre-existing product gap
  (a photo message effectively degrades to text-only after a restore),
  or possibly deliberate scope-limiting of what channel gets round-tripped
  through cloud, but distinguishing "gap" from "deliberate" was not
  determined and is exactly the kind of judgment call that belongs in its
  own investigation, not folded into this unit as a guess. Out of scope
  for Unit 8 (would require extending both the push and restore payloads
  in sync_coach.dart — a materially different blast radius than a
  consent-UI feature). B-PASS CORRECTION (2026-07-30): this paragraph's
  own earlier draft said the gap was "flagged as a separate follow-up
  task" citing only a `mcp__ccd_session__spawn_task` chip
  (`task_e8b00d00`) — the B-pass correctly flagged that a chip is
  ephemeral session UI state, not a durable, git-tracked artifact, so
  once OI-25 closed nothing in the repo would point at this gap anymore.
  Filed as **OI-77** in docs/audit/open_issues.md instead — that is now
  the authoritative, independently-verifiable record.
---

# Unit 8 (OI-25) — coach-media consent UI: the bucket existed for 74 days with zero writers

## What OI-25 asked for, and what was actually missing

Migration 070 (2026-05-17) created the `coach-media` Storage bucket and its owner-only RLS
policies, carrying the founder's own product intent verbatim in its header comment: users should
be asked whether to keep a photo they sent the AI coach, and on consent, the app copies it from
the transient `chat-media` bucket into long-term `coach-media`. The migration's own header laid
out the intended 4-step flow. Nothing in that flow was ever built client-side — the bucket sat
with owner-only RLS and zero writers for 74 days, tracked as OI-25.

## Investigation before design: two prerequisite gaps

Before writing the consent chip, the actual message-send and chat-render pipeline
(`media_picker.dart` → `ai_coach_provider.dart` → `chat_area.dart` → `chat_bubble.dart`) was read
end-to-end rather than trusting the batch plan's line-number estimates. Two things the plan hadn't
anticipated turned up:

1. **`ChatHistoryNotifier.build()`'s user bubble never carried `coachKey`.** Only the AI/error
   bubble did — wired specifically for the Retry button (Bug #19). The consent chip needs to write
   its decision back to the exact `coach_<ms>` row a given photo bubble came from; without
   `coachKey` on that bubble, there was nothing to key the write against. Fixed on both paths that
   construct a user `ChatMessage` — the Hive-rebuild path (`ChatHistoryNotifier.build`) and the
   live optimistic path (`SendMessageNotifier.sendWithMedia`'s immediate `addMessage` call), since
   both had the identical gap.

2. **The only persisted photo reference was a 600-second signed URL.** `media_url` is what
   `ChatBubble` renders, but it expires in 10 minutes — long before a user would plausibly decide
   whether to keep the photo, and unusable as a `Storage.copy()` source path regardless. The raw
   Storage path (`$userId/$timestamp.jpg`) was already being computed locally at upload time
   (`media_picker.dart`) but simply discarded after building the signed URL. Threaded it through as
   a new `media_storage_path` field on the same row instead of writing a URL-parser to recover a
   path from a token-bearing signed URL after the fact — simpler, and avoids a second thing that
   could drift from the server-side `ai-media-proxy` parser.

Given both gaps live on the exact `coach_<ms>` row that already carries `media_url`, the design
choice was to extend that row with two new local-only fields (`media_storage_path`,
`media_save_state`) rather than the plan's original micro-design of a separate coachBox key hashed
on the chat-media path. Same outcome (no new metadata table, no re-prompt on rebuild), one fewer
bookkeeping mechanism, and it reuses the codebase's own established idiom for this exact row
(`updateInteractionWithResponse`/`updateInteractionWithError` already do in-place UPDATE-not-INSERT
on it).

## Why the chip waits for analysis to complete

The founder's migration-070 note is specific: "After AI analysis returns, app prompts." The chip's
gate computes `mediaAnalysisComplete` from the SAME row's `pending`/`failed`/`ai_response` fields
— the identical flags the AI-bubble branch already uses to decide success vs. error vs. pending —
so "analysis complete" for the chip's purposes is defined identically to "AI bubble renders a
successful reply," not a separate, potentially-divergent notion.

One further wrinkle: `replaceLastMessage` (the existing mechanism for swapping in the AI's reply)
only ever touches the trailing bubble. The user's own photo bubble sits earlier in the in-memory
list and would never see `mediaAnalysisComplete` flip during the live send that produced it —
only on the next full Hive rebuild (app restart, auth change). Added
`ChatHistoryNotifier.updateMessageMediaState()`, a targeted in-place list-splice keyed on
`coachKey`, called right after the AI reply lands, so the chip appears in the same session that
triggered it.

## The doc fix folded in, and the test gap that let it happen

While confirming `ai-media-proxy`'s SSRF allowlist for the Saved Photos flow, read
`ai-media-proxy/index.ts:170-174` directly rather than trusting
`supabase/functions/CLAUDE.md`'s prose, which said `progress-photos` + `chat-attachments`. The
live code has always allowlisted `chat-media`, `coach-media`, `progress-photos` — `chat-attachments`
has never existed as a bucket name in this codebase. Fixed the doc, and — since the plan flagged
this as a one-line fix to fold in, not a separate unit — also closed the actual gap that let it go
unnoticed: `test/contracts/ai_media_proxy_ssrf_allowlist_test.dart` existed and ran green the whole
time, but only ever asserted the `/storage/v1/object/` URL-prefix defense, never the bucket-name
set itself. Extended it to pin the real three-bucket set and assert the phantom name's absence.

## Round-2 review — 7 findings, all fixed (none deferred)

Round 2 ran on the post-round-1-fix diff, per §4.12's requirement that the second review sees the
hardened version, not the original. It independently re-verified all 3 round-1 fixes by reading the
current code directly (not trusting this doc's description of them) and confirmed each closes what
it claims to. It then surfaced 7 new findings, all P3, no P0/P1 blockers — but per this batch's
own no-deferrals discipline (§4.2 applies regardless of severity tag), all 7 landed in this batch:

1. **Live-confirmed missing RLS policy** — `chat-media` had no authenticated-DELETE policy at all
   (verified via a direct `pg_policies` query against `dedsavbjuwgarrhphgnl`, not assumed from a
   migration file), so `saveForLater`'s free-tier cleanup call had been silently failing on every
   invocation since the feature shipped in this batch. Migration 116 adds the missing policy.
2. **Non-idempotent retry on `.copy()`** — a network blip after a server-side copy succeeds would
   make a client retry see a failure, reporting an already-saved photo as failed. Fixed with a
   `_destinationExists` check before concluding failure.
3. **Stale `docs/sot_registry.yaml` line ranges** — this batch's own diff shifted
   `ChatHistoryNotifier.build` down ~60 lines; two citations of it (plus a third, genuinely
   pre-existing and unrelated inaccuracy caught while already editing the adjacent entry — a
   `fields_read` claim that `build()` reads `model_used`, which it doesn't) were corrected.
4. **Stale test count** — this doc's tier-1 evidence said "30 tests," contradicted by the 31 the
   test run itself reported after round-1's fix added one. Corrected.
5. **No in-flight visual signal on the save tap** — matches this repo's own documented
   save-confirmation pitfall (`lib/features/ai_coach/CLAUDE.md` common-pitfalls table). Added
   `ChatBubble.isSavingMedia` (spinner + disabled taps during the network round-trip).
6. **Asymmetric race guard** — round-1's fix only stopped a decline from clobbering an in-flight
   save; nothing stopped the reverse. `_onDeclineCoachMedia` now takes the same
   `_savingCoachMediaKeys` lock, for full mutual exclusion.
7. **Doc framing overstated how often the free-tier branch fires** — photo attach is PRO-gated at
   every client entry point, so `saveForLater`'s `if (!isPro)` branch is reachable only via a
   PRO-to-free downgrade in the narrow window between upload and the save tap, not as a routine
   free-tier path. Doc comment corrected to say so plainly.

## B-pass (mandatory ≥account code review) — 3 findings, all fixed

A fresh Sonnet subagent ran the standard 5-lens B-pass (`writer_reader_drift`,
`function_exception_swallow`, `blast_radius_mismatch`, `secrets_in_tree`,
`unawaited_no_error_sink`) against the full staged 24-file diff, with no memory of either prior
review round. Report: `docs/reviews/328f36382e7b-review.md`. 3 findings, no P0:

1. **P1 — closure claims a follow-up was filed; none was durably tracked.** The OI-25 board
   closure and this doc both said the restore/sync gap was "flagged as a separate follow-up task,"
   citing only a `spawn_task` chip — session UI state, not a repo artifact. Once OI-25 closed,
   nothing git-tracked pointed at the gap. Filed **OI-77** properly; corrected both texts to cite
   it instead of the chip (see impact_analysis and the OI-25 board entry).
2. **P2 — Saved Photos delete gives no feedback on failure.** `saved_coach_photos_screen.dart`'s
   `_delete()` had no `else` branch after a failed `CoachMediaRepository.delete()` call — the exact
   save-confirmation-signal pitfall this same batch's own `_onSaveCoachMedia` already avoids. Added
   a SnackBar on failure, mirroring that existing pattern.
3. **P3 — PRO-gate doc comment cited a dead-code file as a live gate.** `saveForLater`'s doc
   comment listed `attach_button.dart` alongside the two genuinely live gates
   (`recording_body.dart`, `media_picker.dart`) — that file's only function carries its own
   `// ignore: unused_element` and an explicit "no longer wired into the input bar" comment.
   Corrected the citation; the underlying claim (gated at every live entry point) still holds.

## Blast radius

`scripts/blast_radius_from_diff.dart` classified the full changed-file set as `platform` —
higher than the plan's pre-diff estimate of `account`. Confirmed via the live tool rather than
the plan's estimate, per this batch's own standing rule that blast-radius estimates in the plan
are pre-diff judgment, not a commitment. `platform` requires the ×2 independent review + B-pass +
plan-review record (not the additional Hermes-pass, which is `catastrophic`-only). Re-confirmed
`platform` after round-2's fixes on the final 24-file set (16 modified, 8 new — the growth from
round-1's 20 is migration 116 + its 4 new pinning tests, all within files already counted or of
the same tier).
