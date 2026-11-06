---
bug_id: b9d3f1
date: 2026-11-06
batch: telegram-surface-off
status: fixed
blast_radius: platform
symptom: >
  Telegram is dropped (founder, 2026-11-04) but the app still promised it in three places a user can reach. The paywall
  sold "Weekly AI nutrition report + Telegram push" as a PRO perk that cannot be delivered. The AI Coach overflow menu
  offered "Switch to Telegram", which replaced the whole chat (input bar, quick prompts, measurement chip) with a
  "Telegram - Coming Soon" screen. A tester whose saved coach channel was already "telegram" landed on that dead
  screen with no chat at all, and only the same menu item got them back. A dead TelegramCard widget and a t.me deep
  link helper were still in the tree.
concept: >
  Removing a feature leaves a surface the feature owned. OI-227 (2026-09-21) removed the "Connect" entry points but
  deliberately kept the channel toggle, the Coming Soon view, the channel provider and the paywall perk; a contract
  test then pinned those leftovers as REQUIRED, so the next person to remove them had a red test saying they must
  stay. The removal has to take the surface, its state providers, the tests that pin them and the docs that describe
  them in one batch.
sot_registry_entry: not_applicable
writers:
  - { file: lib/shared/widgets/paywall_sheet.dart, method: "_proBenefits perk list, entry 4 now reads Weekly AI nutrition report", line: 122 }
  - { file: lib/features/ai_coach/screens/ai_coach/compact_header.dart, method: "coachHeaderMenuItems, the overflow entries (Clear conversation, and Upgrade to PRO on a free account)", line: 174 }
  - { file: lib/features/ai_coach/screens/ai_coach/screen.dart, method: "_AiCoachScreenState.build, chat area with no channel branch", line: 452 }
readers:
  - { file: lib/features/ai_coach/screens/ai_coach/compact_header.dart, method_or_widget: "PopupMenuButton itemBuilder calls coachHeaderMenuItems", line: 139 }
  - { file: lib/shared/widgets/paywall_sheet.dart, method_or_widget: "PaywallSheet perk rows built from _proBenefits", line: 478 }
  - { file: lib/core/services/user_config_migrator.dart, method_or_widget: "MigratedKey list names telegram_connected and coach_channel; no code reads their values any more", line: 79 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/telegram_surface_removed_test.dart
recurrence: >
  Recurrence class: a PARTIAL removal leaves the adjacent surfaces and a test then pins the leftover. Prior instance:
  OI-227 (2026-09-21), whose code review (docs/reviews/b87e8a1f3f2a-review.md, finding 4) asked for a pin and got one
  that required the channel toggle and the Coming Soon view to stay. Same family as c1b9d4 (OI-232, the scroll fix that
  existed only because the toggle remounted the chat). Bug-history search done: the diagnose index for telegram,
  channel and coach channel (c1b9d4; c7e3b9, which records the in-repo telegram-bot/ and the receive_email flaw that OI-227 carried and OI-476 now carries; and the telegram-admin-bot docs, which are the founder-ops bot and unrelated),
  and the OI board for OI-227, OI-232, OI-466, OI-467, OI-278. Not recurrence of the founder-ops Telegram bot.
related_bugs: [c1b9d4, c7e3b9]
ist_handling: not_applicable
cross_account_guard: >
  not_applicable. Two user-scoped providers that watched authUserIdTokenProvider are deleted; six other watchers of
  it remain in ai_coach_provider.dart (69 across lib/; the base commit had 8 in that file, which included
  the two deleted), so the auth-invalidation contract is unaffected.
provider_invalidations: not_applicable
telemetry_op_types: none
forbidden_patterns_checked: >
  No Edge Function, migration, schema or Hive adapter touched, so no deploy, no live apply and no deno check.
  Server prompts carry no Telegram copy (grep over captain_manual.ts, coach_replies.ts, ai-proxy and ai-proxy-pro is
  empty). Not touched on purpose: pullRecentCrossChannelLogs and its source 'telegram' label (OI-467), the two key
  names in the migrator list, the founder-ops telegram-admin-bot, the morning-alert Telegram fallback and the tracked
  telegram-bot/ directory (OI-476).
impact_analysis: >
  User-visible: the paywall perk list loses one false claim, the AI Coach three-dot menu loses one item, and a tester
  with a saved Telegram channel lands in chat. Nothing else changes for a normal account. Accepted residue, stated and
  not solved: (1) the saved-channel guarantee is PRESENCE-ONLY. AiCoachScreen cannot be pumped in a unit test, so it
  rests on the structural scan (no reader of coach_channel and no channel branch left in lib/) plus device check A17 of
  OI-348. (2) Adjacent string literals ('Tele' 'gram') and Unicode lookalikes slip through any substring scan; the
  realistic threat is an old branch merged back, which the scan catches (mutant M10 survives and is recorded). (3) Three
  non-comment occurrences of 'telegram' stay in sync_service.dart and one in the migrator list; the scan pins those
  counts exactly. (4) The coach tool dispatcher and ai-proxy are untouched, so a model reply could still mention
  Telegram in free text; no prompt tells it to.
proposed_fix: >
  Take the whole surface in one batch. Paywall perk becomes "Weekly AI nutrition report". The overflow menu becomes the
  pure top-level function coachHeaderMenuItems (Clear conversation, plus Upgrade to PRO on a free account); the
  channel switch, the Telegram view, TelegramCard, _openTelegramBot, the url_launcher import, channelProvider,
  ChannelNotifier, telegramConnectionProvider and TelegramConnectionNotifier are deleted, and the four channel
  branches in the screen build collapse to their chat branch. Tests that cited the old code are repointed
  (neighbour-adjacency pin for the measurement chip, a stable slice anchor for the sanitization test) and the contract
  test that required the leftovers is replaced. Docs, three registry entries and the board follow.
regression_test_planned: >
  test/contracts/telegram_surface_removed_test.dart (11 tests. Group P: the real PaywallSheet pumped for the generic
  upgrade and again for EVERY feature label of its subtitle switch plus the default branch, 15 labels; group M: the
  real menu function pumped from a PopupMenuButton, free and PRO; group S: a comment-stripped, string-aware scan of
  584 lib files plus the text files under assets/ and web/ with an EXACT-LINE allow-list, whole-word symbol and file
  absence, coach_channel pinned to one use in the migrator, the header wiring pinned once, every menu value tied to
  its case label in the header handler, and the chat area pinned as the unconditional body of the screen build by its
  neighbours). Repointed: test/contracts/measurement_flag_off_identity_test.dart,
  test/contracts/coach_chat_reply_sanitization_test.dart, test/ai_coach/initial_scroll_to_bottom_test.dart (only the
  test of the retired OI-232 listener left), test/ai_coach/measurement_chip_slot_test.dart (title). Retired:
  test/contracts/telegram_connect_ui_removed_test.dart.
  MUTATIONS, each computed in memory, applied, confirmed applied, run, restored by the harness with a sha256 check
  (0 drift); the WHOLE table was re-run on the final code after the B-pass fixes. First round: M1 perk restored = red;
  M2 menu item re-added = red (2 tests); M3 coach_channel constant in screen.dart = red; M4 telegram_view.dart
  recreated = red; M5 Telegram in a string = red; M6 'x // Telegram' inside a string literal = red (proves the
  string-aware stripper); M7 CONNECT @AVYACOACHBOT without the word = red; M8 a fourth 'telegram' in sync_service.dart
  = red; M9 switch_channel token = red; M10 adjacent literals 'Tele' 'gram' = SURVIVES (known residue, recorded); M11
  chip re-gated on a channel local = red; M12 old class terminators put back in the sanitization test = red (count 3
  vs 2, so the retarget is load-bearing); M14 chip re-gated with if (!isPro) = red (the first draft of the repointed
  pin would have survived this; found by plan review round 2); M15 quick prompts re-gated = red; M16 menu function
  unwired from the real button = red. B-pass round, one mutant per new assertion: N1 chat area gated behind isPro =
  red; N2 and N2b a case label renamed in the header handler = red; N3 a deep link built as host t.me with no slash =
  red; N3b a tg:// scheme link = red; N3c the Devanagari spelling as real characters = red; N4 user copy swapped into
  an allow-listed sync_service line with the count unchanged = red; N5 a second coach_channel use inside the exempt
  migrator = red; N6 Tele and gram joined at run time in the Weekly AI Report subtitle = red (only the per-label
  paywall pump can see it); N7 CONTROL, a legitimate NotificationChannelNotifier = stays green (proves the
  whole-word symbol check). M13 (a gate mutant, the old 479-486 registry range put back) = check_sot_registry_parity
  fails with [range-overflow] 479-486 vs 475 lines, re-run on the final registry. Result: 23 of 24 harness mutants
  red, M10 the declared survivor, N7 the green control, M13 red.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ after the edits: 0 errors, 0 warnings, 60 infos (3 in screen.dart are the pre-existing speech_to_text deprecations at lines 253-255). Whole-project flutter analyze --no-fatal-infos after the B-pass fixes: 0 errors, 0 warnings, 398 infos (the baseline). The new test file passes 11 of 11; the repointed sanitization, flag-off identity, chip-slot and scroll tests pass." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "coach_channel and telegram_connected are read by nobody after this change (scan of lib/); a saved value of telegram is inert. They stay in the MigratedKey list on purpose (append-only history; the contract test of that list is one-directional)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "users.telegram_connected, users.telegram_chat_id and telegram_connections are untouched (OI-476 owns their fate)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function changed or deployed; server prompts read for Telegram copy, none found." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Traced the only user-reachable Telegram paths end to end by reading: paywall perk text, overflow menu item and its onSelected case, the screen channel branch, the provider that persisted the choice. All removed; sync_service.dart source value 'telegram' is a write-only label with no UI reader found in lib/ (OI-467)." }
---

# Telegram promises removed from the paywall and the AI Coach tab

## What happened

Telegram was dropped on 2026-11-04, but a user could still be told about it on the screen where they pay, and could
tap a menu item that swapped the AI Coach chat for a "Coming Soon" screen. OI-227 had removed only the "Connect" entry
points in September and kept the rest on purpose; a contract test then required that rest to stay.

## The fix

One batch removes the whole surface: the paywall perk text, the channel toggle and its view, the dead card and deep
link helper, the channel and Telegram-connection providers, and the OI-232 scroll listener that existed only to
recover from the toggle. The overflow menu is now a pure function so a test can pump the real entries.

## Proof levels (stated, not rounded up)

- Paywall: BEHAVIORAL, the real sheet is pumped for the generic upgrade and for every feature label of its subtitle
  switch (a string assembled at run time in one branch is caught; mutant N6).
- Overflow menu: BEHAVIORAL, the real entries are pumped; the header wiring is pinned once and each value is tied to
  its case label by a source pin (the values and the dispatch live in two places).
- A tester with a saved Telegram channel lands in chat: PRESENCE-ONLY (a structural scan: no reader of the key, no
  channel branch, and the chat area pinned as the unconditional body of the screen build), plus device check A17 of
  OI-348. The screen cannot be pumped in a unit test.
- `Clear conversation` is pinned to EXIST and be wired; it is not claimed to work (OI-479, below).

## Found by plan review, not by the first draft

Two review rounds (five Sonnet reviewers) caught what the first plan would have shipped red: two source pins on the
literal `if (channel == 'in_app')`, a test that slices a source file up to the next class and would have counted a
top-level function definition, a registry line range that would have overflowed its file, and a repointed pin weak
enough to pass under a different condition. The simulation of the sanitization slice (count 2 to 3) was reproduced on
the real file before the plan was changed.

## Found by the B-pass, not by the author

Two fresh Sonnet reviewers (code and tests; docs, registry, board) found no P0 or P1 and 15 findings of P2 or lower,
all verified against the files before acting. Fixed in this batch: the menu's values and its case labels were pinned
on one side only; nothing pinned the chat area as unconditional; the deny regex missed a deep link spelled as host
t.me, a tg:// link and the Devanagari spelling; the allow-list pinned counts, not lines; the paywall was pumped for
one subtitle of fifteen; OI-476 overstated the exploit (the table has UNIQUE on user_id, so replacing an existing
owner's chat is not established, while an account-existence oracle and a name and plan disclosure are real); the
review-finding number in `recurrence` was wrong; the watcher count was the base commit's; six live statements still
called the bot out-of-repo or said the UI reads `source`; a registry range was one line short; and stale text sat on
lines this batch already touched. Six of the eight mutants one reviewer proposed as text were real survivors of the
first table and are now rows N1 to N6.

## Not done, on purpose

`pullRecentCrossChannelLogs` and its `source: 'telegram'` label (OI-467, blocked on OI-279 and OI-281). The tracked
`telegram-bot/` directory and the morning-alert fallback: OI-476 carries the unproven-ownership account-linking flaw
of `receive_email` and the keep-or-delete question for the founder. The `Clear conversation` menu item does nothing
(its handler only invalidates `chatHistoryProvider`, which re-reads every row from `coachBox`; byte-identical at the
base commit): OI-479 carries it, because what "clear" should mean across Hive and the cloud is a founder decision
and not part of removing Telegram.
