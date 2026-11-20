---
reviewed_at: 2026-11-20T21:30:00+05:30
staged_against: a6d240c137b5
blast_radius: platform
reviewer: claude-sonnet-via-skill (three fresh seats: A docs/registry/process, B guards and mirrors in lib, C tests and fixtures)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 23
verdict: accepted
verdict_note: coordinator triage, every finding fixed or recorded with a terminal state in docs/audit/2026-11-20-android-play-billing.closure.yaml. The hash names the whole reviewed diff; it is committed as four commits (the feature, two fix(profile) commits, then the ledger, this review and the plan-review record). Self-attested; the founder reads this at the merge.
---

# Code Review — a6d240c137b5 (play-billing-fallback, ADR-0022, platform tier)

Three context-blind Sonnet seats, read-only on the shared tree, each given the recorded decisions and rejected alternatives and an exhaustive command list (seat C ran only the named `flutter test` files). The staged diff is the reviewed object (no commit exists yet, by the founder's standing instruction). Seat B and seat C found finding 1 independently.

## Finding 1 — P1 — guard_without_its_mirror (release vs debug), asserted_fixture_value
- **file:line:** lib/core/constants/purchase_mode.dart:49-50 (as reviewed); test/contracts/purchase_mode_current_wiring_test.dart:31-37
- **claim:** `bool.fromEnvironment('dart.vm.product')` and `String.fromEnvironment('ANDROID_PURCHASE_MODE')` were call arguments, not const reads. Dart only guarantees them in a const context; a release AOT build has no run-time environment, so it would see `isRelease == false` and an empty define and resolve every store build to `razorpay`, the exact failure the feature prevents. Every test runs JIT, where it works, and the wiring pin locked the non-const text in. Not proven on an AOT build (none can be run here); the repo's own precedent (`ist_date.dart:21`, `app_constants.dart:11,12,196`) is const.
- **verification:** `grep -rn fromEnvironment lib` listed these as the only non-const uses.
- **suggested-fix:** make both const; pin the keyword.
- **status:** accepted, fixed. Both reads are `const`; the pin now requires the keyword and anchors each argument to its separator; mutants (non-const release flag, trailing `+ 'x'`, `kIsWeb || true`) all red. The on-device Profile build line remains the proof of the real binary.

## Finding 2 — P2 — guard_without_its_mirror (the only action fails)
- **file:line:** lib/shared/widgets/paywall_sheet.dart:366-396, lib/shared/widgets/paywall_unavailable_body.dart:129-142
- **claim:** In the neutral card CHECK MY PRO STATUS is the only functional control. When it failed, the snackbar was drawn behind the modal sheet, so the user saw `...` and then nothing.
- **verification:** traced `_handleRestore` catch branch; `showModalBottomSheet(isScrollControlled)` covers the bottom.
- **status:** accepted, fixed. Inline status line in the card with neutral copy; cleared when the next attempt starts; purchase mode keeps its snackbar. Behavioural tests (offline, retry in flight, retry success), two mutants red.

## Finding 3 — P2 — writer_reader_drift (inserted-lines sub-check)
- **file:line:** docs/sot_registry.yaml, 83 `line_range` entries across 21 edited files
- **claim:** Only the ranges the parity gate flagged had been shifted, by inconsistent offsets; the gate checks that the symbol is somewhere in the range, so real spans stayed wrong (e.g. createOrder's `_extractServerError` call fell out of its range; `_validatePromoCode` began inside `dispose()`).
- **status:** accepted, fixed. Every cite recomputed from the HEAD hunks by script, sentinels left at `1-9999`, one prose cite corrected, the new concept's ranges re-measured, and the cites seat A named checked by anchor.

## Finding 4 — P2 — missing_input (the package is not inert on web)
- **file:line:** pubspec.yaml:86, pubspec.lock
- **claim:** `purchases_flutter` 11.0.4 declares a web plugin whose `registerWith` appends a `<script>` for a vendored ~1 MB `purchases_js_hybrid_mappings.js` at app start, although nothing imports the package. Vercel builds web from `main`, so the first web deploy after this lands loads it on every page view. The ADR said the web build "ignores it".
- **verification:** read the pub cache (`lib/web/purchases_flutter_web.dart:74-90`, `assets/web/` 1,014,694 bytes, pubspec `web:` platform entry).
- **status:** accepted as a documented cost, decision recorded. ADR-0022 Decision 6 and Consequences now state it; closure entry `WEB-SCRIPT` is closed on the founder's acceptance (reopen at the web launch); a presence pin keeps the record from disappearing. The founder accepted the cost until the web launch (2026-11-20).

## Finding 5 — P2 — own tests are not evidence (source pins)
- **file:line:** test/contracts/purchase_surfaces_mode_none_test.dart (700-character window)
- **claim:** The pin accepted `showsUpgradeAffordance()` anywhere in the 700 characters before a literal, so a swapped ternary or a `!` inversion stayed green (shown by in-memory mutation on status_pill, phase_roadmap, input_bar, profile_content).
- **status:** accepted, fixed. One adjacency-and-polarity regex per literal; six real-file mutants red.

## Finding 6 — P2 — own tests are not evidence (call-site argument)
- **file:line:** nutrition_provider.dart:964, ai_coach_provider.dart:845,1256, prediction_card.dart:38, plan_expired_card.dart:266
- **claim:** Nothing pinned `purchaseUi: showsUpgradeAffordance()`; a hard-coded `true` would print upgrade wording in a no-purchase build with every test green.
- **status:** accepted, fixed. Per-file count of the argument and a repo-wide ban on `purchaseUi: true`; mutant red.

## Finding 7 — P2 — own tests are not evidence (expiry banner)
- **file:line:** purchase_surfaces_mode_none_test.dart (offset comparison); home_provider.dart:508-514
- **claim:** The banner was source-pinned by offsets an inverted guard also satisfies, with a title that did not match the check; the plan promised a behavioural row.
- **status:** accepted, fixed. `purchase_expiry_banner_mode_none_test.dart` (positive pair in razorpay); inverted and deleted guards red.

## Finding 8 — P2 — asserted_fixture_value (inventory scanner)
- **file:line:** test/contracts/purchase_literal_inventory_test.dart
- **claim:** The regex scanner reported 0 for real upgrade wording written with nested-quote interpolation (a real `RENEWS` hit at subscription_section.dart:109), triple quotes, adjacent split literals, a block-comment opener inside a line comment, `subscription` / `buy` / `trial` / `Rs.` / `\u{20B9}`, and it counted import URIs.
- **status:** accepted, fixed. Quote-state scanner, 25 self-test rows, table re-measured (51 files, 133 hits), three real-shape regressions red.

## Finding 9 — P3 — blast_radius / docs claims
- **file:line:** docs/audit closure (test count 18 vs 14), diagnose e5a9c3 (writer line 41, reader 278, copied evidence line), docs/architecture/subscription.md ("deep-analysis button"), GO_LIVE_CHECKLIST (permission list without BILLING), .claude/commands/build-apk.md (a contradiction and a refusal that came after the clean)
- **status:** accepted, fixed. Counts, lines and evidence corrected, sentence corrected, BILLING noted for the +50 build, the refusal moved before every gate, the `.opencode` mirror regenerated.

## Finding 10 — P3 — guard_without_its_mirror (PRO vs free pill)
- **file:line:** pro_pill_button.dart:47-48, status_pill.dart:63
- **claim:** In a no-purchase build a free and a PRO user's pill read the same word (colour is the only difference), and the free coach pill kept an upgrade arrow. Pushes on the recorded "pills read PRO" decision without reversing it.
- **status:** accepted, fixed. Screen-reader label for the free pill in that build only, arrow omitted; behavioural semantics tests.

## Finding 11 — P3 — function_exception_swallow
- **file:line:** razorpay_service.dart:139-144; paywall_sheet.dart:388
- **claim:** The `openCheckout` refusal was silent (debugPrint only); the restore-failure copy said "purchase" in a build that sells nothing.
- **status:** accepted, fixed. `razorpay_checkout_refused_mode` event (asserted per mode); neutral copy in none mode.

## Findings 12-15 — P3 — asserted_fixture_value (small test hardening)
- wiring pin was substring-only (`&& false` passed) — anchored; resolver unknowns lacked near misses of a real wire name — six added, a `startsWith` matcher mutant red; the razorpay guard case depended on an empty `RAZORPAY_KEY_ID` — it now skips with a stated reason when a key is defined; absence checks (`MAYBE LATER`, `₹`, `Upgrade to PRO`) had no razorpay positive pair — added.
- **status:** accepted, fixed.

## Finding 16 — P3 — own tests are not evidence (copy list)
- **claim:** the "no upgrade wording" test listed 12 copy members by hand; the rest (`manageSubscription`, `eyebrow`, `benefitsLabel`, `checkStatusButton`, `closeButton`) were unchecked. Also a comment above the wrong constant (cosmetic).
- **status:** accepted, fixed (all members listed, comment moved).

## Checked and clean (per seat)
- **Lens 4 secrets:** every added line grepped for `goog_`, `appl_`, `sk_`, `rzp_`, `eyJ`, `AIza`, `BEGIN … PRIVATE`, `secret|token|password|api_key`: only plan prose and "not applicable" rows; no literal values.
- **Lens 3 blast radius:** CLAUDE.md, pubspec.yaml, pubspec.lock are `platform` in docs/blast_radius.yaml; the diff measured `platform`; no mismatch.
- **Lens 5:** the only new `unawaited` is `paywall_unavailable_shown`, identical in form to the existing events; the new files have no async code.
- **Lens 6 razorpay-mode identity:** every edited string compared with `git show HEAD:` (food-analysis limit, photo analysis, feature required, prediction, deploy-to-phase, composer hint, status pill, report card, roadmap and preview CTAs, overlay default); the expiry-banner notifier's early return comes after the kill switch and before any state read; web ignores the define; `paywall_shown` / `paywall_dismissed` semantics unchanged; no layout hole or dead end in none mode (layouts, the coach limit tap target, `_sendMessage` at the cap, no second purchase path).
- **Lens 7:** all test paths cited by the new registry concept and the ledger exist; `purchases_flutter` is an exact pin with a matching lock hash; the ledger `@branch` commit form is accepted by the validator and used by twelve sibling ledgers; ADR index and amendment consistent; Play id matches Gradle.
- **Lens 8:** copy strings in the tests match `git show HEAD:` byte for byte; the override seam is reset in every file that sets it; GoogleFonts warm-ups first in each widget file.

## Founder triage notes
Finding 4 (`WEB-SCRIPT`): accepted by the founder 2026-11-20. The app name is decided (AvyaFit); applying it and the Play price are open and are not findings of this diff, as is the server-sent upgrade and price copy (GO_LIVE 0.4).

## Tuning entry
- **2026-11-20** - blast-radius platform - 23 findings (1 P1, 7 P2, 15 P3); 0 false_alarm; tuning: added a build-define sub-check to lens 6 (a non-const `fromEnvironment` reads its default in an AOT build while every JIT test sees the define; found independently by two seats), and the inventory-scanner lesson (a regex over Dart source misses nested quotes, triple quotes and split literals: use a quote-state scanner) is recorded here; two seats ran their own in-memory mutants against the diff's source pins and found polarity holes the diff's tests could not, so keep lens 6's "mutate the way a real regression re-enters" for source pins.
