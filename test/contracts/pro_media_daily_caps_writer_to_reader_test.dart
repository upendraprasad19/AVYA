// OI-153 — the PRO image daily cap had NEVER FIRED and PRO video was UNCAPPED.
//
// THE BUG: `ai-media-proxy` counted `ai_coach_interactions` rows on channels
// `pro_image_analysis` / `image_analysis`, which NOTHING writes — 0 rows in
// the table's whole history — so `used >= 50` was structurally false; and
// PRO+video matched neither `isVideo && !isPro` (paywall) nor
// `!isVideo && isPro` (cap), falling straight through to Gemini. This is the
// 5th and LAST reader of the pruned-log quota class (OI-162 slices 1–4 moved
// the other nine). The fix moves both caps onto `usage_counters` via ONE
// atomic `consume_quota` call per request, placed AFTER the Storage fetch
// (a rejected upload never spends a unit) and BEFORE the Gemini call (the
// spend is bounded even under concurrency — an advisory read is not).
//
// SCOPE — presence + association, over comment-stripped source. These greps
// prove the code SAYS the right thing; CI's `deno check` + `deno test` prove
// it compiles and the deploy-time smoke proves it runs. Live-ledger
// behaviour (1..cap then -1, key isolation) is proven in
// `test/sql/oi153_pro_media_caps_live_verify.sql` inside a rolled-back
// transaction.
//
// Every anchor below was checked for UNIQUENESS against the file (review
// round 4): a bare `fetchImageAsBase64(` first matches the DECLARATION, a
// bare `=== -1` also matches the free path's `consumedCount === -1`, and
// `quota_unavailable` is a substring of `pro_quota_unavailable`. Membership
// checks on those would have been vacuous.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _proxyPath = 'supabase/functions/ai-media-proxy/index.ts';
const _copyPath = 'supabase/functions/_shared/coach_replies.ts';

/// Source with `/* */` blocks and `//` comments stripped, so an ABSENCE
/// assertion can never be satisfied by prose about the code (this file's own
/// header names the retired channels by design). `(?<!:)//` keeps `https://`.
String _stripComments(String raw) {
  final noBlock = raw
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = RegExp(r'(?<!:)//').firstMatch(l)?.start ?? -1;
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

/// The substring from the FIRST occurrence of [from] to the first occurrence
/// of [to] after it. Fails loudly (not vacuously) if either is missing — an
/// absent anchor must never read as "the span is clean".
String _span(String src, String from, String to) {
  final a = src.indexOf(from);
  expect(a, greaterThanOrEqualTo(0), reason: 'anchor "$from" not found');
  final b = src.indexOf(to, a + from.length);
  expect(b, greaterThan(a), reason: 'anchor "$to" not found after "$from"');
  return src.substring(a, b);
}

int _count(String src, String needle) =>
    needle.allMatches(src).length;

void main() {
  late String src;
  late String copy;

  setUpAll(() {
    src = _stripComments(File(_proxyPath).readAsStringSync());
    copy = _stripComments(File(_copyPath).readAsStringSync());
  });

  group('OI-153 — the dormant channel-counting gate is GONE', () {
    test('no reader of the pruned log remains for the PRO cap', () {
      for (final dead in const [
        'countProImageAnalysesToday',
        'pro_image_analysis',
        '"image_analysis"',
        '.in("channel"',
        'code: "RATE_LIMITED"',
        '"Retry-After"',
        'status: 429',
        '!isVideo && isPro',
      ]) {
        expect(src.contains(dead), isFalse,
            reason: '`$dead` is back — the cap is counting a channel nothing '
                'writes again (0 rows ever), or PRO video is falling through '
                'the tier branches again.');
      }
    });
  });

  group('OI-153 — both caps consume the ledger, once, atomically', () {
    test('constants and keys carry the founder-decided values', () {
      expect(RegExp(r'PRO_IMAGE_DAILY_CAP\s*=\s*50;').hasMatch(src), isTrue);
      expect(RegExp(r'PRO_VIDEO_DAILY_CAP\s*=\s*10;').hasMatch(src), isTrue);
      expect(
          RegExp(r'PRO_IMAGE_QUOTA_KEY\s*=\s*"pro_image_daily";').hasMatch(src),
          isTrue);
      expect(
          RegExp(r'PRO_VIDEO_QUOTA_KEY\s*=\s*"pro_video_daily";').hasMatch(src),
          isTrue);
    });

    test('the key AND the cap are both selected by isVideo (arrangement, not membership)', () {
      // Two ternaries, each pinned in ORDER. Swapping the arms of either one
      // leaves every membership check green — round 1 caught that pinning
      // the key ternary alone left video capped at 50.
      expect(
        RegExp(r'proQuotaKey\s*=\s*isVideo\s*\?\s*PRO_VIDEO_QUOTA_KEY\s*:\s*PRO_IMAGE_QUOTA_KEY')
            .hasMatch(src),
        isTrue,
        reason: 'video must select the video key, image the image key',
      );
      expect(
        RegExp(r'proCap\s*=\s*isVideo\s*\?\s*PRO_VIDEO_DAILY_CAP\s*:\s*PRO_IMAGE_DAILY_CAP')
            .hasMatch(src),
        isTrue,
        reason: 'video must select the 10 cap, image the 50 cap',
      );
    });

    test('the gate is `if (isPro)` — video and image alike — and calls consume_quota with the derived inputs', () {
      final gate = _span(src, 'if (isPro) {', '} else if (proCount === -1)');
      expect(gate, contains('.rpc("consume_quota"'));
      expect(RegExp(r'p_user_id:\s*userId').hasMatch(gate), isTrue);
      expect(RegExp(r'p_quota_key:\s*proQuotaKey').hasMatch(gate), isTrue);
      expect(RegExp(r'p_window_start:\s*proWindowStart').hasMatch(gate), isTrue);
      expect(RegExp(r'p_limit:\s*proCap').hasMatch(gate), isTrue);
      expect(_count(src, 'p_quota_key: proQuotaKey'), 1,
          reason: 'ONE quota_key => ONE call site (sot_registry usage_quota_ledger)');
      expect(_count(src, 'p_quota_key: FREE_IMAGE_ANALYSIS_QUOTA_KEY'), 1,
          reason: 'the free lifetime key must keep exactly one call site too');
    });

    test('the condition guarding the PRO consume is EXACTLY isPro — no isVideo narrowing', () {
      // B-pass (2026-09-13) mutation (a): `if (isPro)` -> `if (isPro && !isVideo)`
      // — the exact pre-fix shape (PRO video uncapped) — reddened the test
      // above only through _span's "anchor not found" guard, i.e. by
      // accident of the literal, not by an assertion about the GUARD. This
      // one reads the condition of the nearest `if (` ABOVE the PRO RPC and
      // pins it, so any narrowing (`&& !isVideo`, `&& mediaType !== "video"`,
      // a nested `if (isVideo)`) reddens on its own terms.
      final rpc = src.indexOf('p_quota_key: proQuotaKey');
      expect(rpc, greaterThanOrEqualTo(0));
      final before = src.substring(0, rpc);
      final ifStart = before.lastIndexOf('if (');
      expect(ifStart, greaterThanOrEqualTo(0));
      final condEnd = before.indexOf(')', ifStart);
      final condition = before.substring(ifStart + 'if ('.length, condEnd).trim();
      expect(condition, 'isPro',
          reason: 'the PRO consume must be guarded by isPro ALONE — video and '
              'image alike. A narrowed guard is the H-23 defect re-entering: '
              'PRO video would skip the ledger and reach Gemini uncapped.');
      // And between that guard and the RPC there is no second conditional at
      // all — no `if (isVideo)` / ternary that could route one media type
      // around the consume.
      final between = before.substring(condEnd);
      expect(between.contains('if ('), isFalse,
          reason: 'no conditional may sit between `if (isPro)` and the RPC');
      expect(between.contains('isVideo'), isFalse,
          reason: 'isVideo must not appear between the guard and the RPC — '
              'the key/cap were derived at function scope, above the guard');
    });

    test('the window is the IST day, computed once at function scope', () {
      expect(RegExp(r'const proWindowStart\s*=\s*istDayStartIso\(\);').hasMatch(src),
          isTrue,
          reason: 'midnight IST reset is the founder decision; a UTC bucket '
              'would reset at 05:30 IST');
      expect(src, contains('import { istDayStartIso } from "../_shared/ist_date.ts"'));
    });

    test('ORDER: PRO consume sits AFTER the Storage fetch and BEFORE the Gemini call', () {
      final fetchCall = src.indexOf('await fetchImageAsBase64(');
      final consume = src.indexOf('p_quota_key: proQuotaKey');
      final gemini = src.indexOf('await geminiChat(');
      expect(fetchCall, greaterThanOrEqualTo(0));
      expect(gemini, greaterThan(fetchCall));
      expect(consume, greaterThan(fetchCall),
          reason: 'a unit must never be spent on a rejected upload (5 MB, '
              'SSRF, Storage 404 race)');
      expect(consume, lessThan(gemini),
          reason: 'the spend must be bounded BEFORE Gemini — an advisory read '
              'lets N concurrent requests all reach Gemini');
      expect(_count(src, 'await fetchImageAsBase64('), 1);
      expect(_count(src, 'await geminiChat('), 1);
    });

    test('ORDER: the free lifetime consume stays AFTER the conversation-log insert', () {
      final insert = src.indexOf('channel: interactionChannel');
      final freeConsume = src.indexOf('p_quota_key: FREE_IMAGE_ANALYSIS_QUOTA_KEY');
      expect(insert, greaterThanOrEqualTo(0));
      expect(freeConsume, greaterThan(insert),
          reason: 'slice 3b: a lifetime unit is spent only after the analysis '
              'it pays for has been persisted');
    });
  });

  group('Hermes L23 F2 (2026-09-13) — the SERVED MIME, not the client claim, selects the cap', () {
    // The key, the cap and the free-tier video paywall were selected by the
    // client's `media_type` while the bytes are typed by Storage's
    // content-type — the MIME Gemini is told. A PRO caller labelling a video
    // "image" drew from the 50/day bucket; a free caller did the same to walk
    // a video past the PRO-only paywall for one lifetime image unit.
    test('isVideo is re-derived from the served content-type AFTER the fetch, BEFORE the key/cap are derived', () {
      final fetchCall = src.indexOf('await fetchImageAsBase64(');
      final served = RegExp(r'const servedAsVideo\s*=\s*mimeType\.startsWith\("video/"\)')
          .firstMatch(src);
      expect(served, isNotNull, reason: 'the served type must come from mimeType');
      final reconcile = src.indexOf('isVideo = servedAsVideo');
      expect(reconcile, greaterThan(served!.start), reason: 'isVideo must be REASSIGNED to the served answer');
      expect(served.start, greaterThan(fetchCall), reason: 'only the fetch knows the served type');
      expect(RegExp(r'let isVideo\s*=').hasMatch(src), isTrue,
          reason: 'a `const isVideo` cannot be reconciled');
      final keyDerive = RegExp(r'const proQuotaKey\s*=\s*isVideo').firstMatch(src);
      final capDerive = RegExp(r'const proCap\s*=\s*isVideo').firstMatch(src);
      expect(keyDerive, isNotNull);
      expect(capDerive, isNotNull);
      expect(keyDerive!.start, greaterThan(reconcile),
          reason: 'a key derived above the reconciliation is the client\'s key');
      expect(capDerive!.start, greaterThan(reconcile));
      expect(src.indexOf('p_quota_key: proQuotaKey'), greaterThan(capDerive.start));
      // Exactly one derivation each — a pre-fetch copy left behind would be
      // the one the ternary regexes above happily match.
      expect(_count(src, 'const proQuotaKey ='), 1);
      expect(_count(src, 'const proCap ='), 1);
    });

    test('the video paywall has EXACTLY ONE site — post-fetch, on the RECONCILED type', () {
      // B-pass finding (2026-09-13): a pre-fetch video paywall gated on the
      // CLIENT's claim used to exist here too, and it was the asymmetric
      // half of the same trust-the-claim bug this whole group is about — a
      // free user who mislabelled a real IMAGE as "video" was paywalled
      // before the bytes were ever inspected, denying a legitimate free
      // analysis. There must be exactly ONE site now, after the fetch, on
      // the reconciled isVideo.
      final fetchCall = src.indexOf('await fetchImageAsBase64(');
      final sites = 'if (isVideo && !isPro)'.allMatches(src).map((m) => m.start).toList();
      expect(sites.length, 1,
          reason: 'a pre-fetch site trusts the unverified client claim — '
              'exactly the bug this fix removes');
      expect(sites[0], greaterThan(fetchCall),
          reason: 'the one remaining site must be POST-fetch, on the server-verified type');
      expect(sites[0], lessThan(RegExp(r'const proQuotaKey\s*=').firstMatch(src)!.start),
          reason: 'the paywall precedes the key derivation and the consume');
      expect(_count(src, 'return await videoPaywallReply(supabaseClient, userId, message, media_url);'), 1);
      expect(_count(src, 'gate_reason: "video_pro_only"'), 1);
      expect(_count(src, 'channel: "video_paywall"'), 1);
    });

    test('the free-image cap check has EXACTLY TWO sites, sharing ONE helper — pre-fetch fast path AND post-fetch mirror', () {
      // The mirror of the finding above: a free caller whose claim says
      // "video" skips the PRE-fetch free-image check (isVideo is still true
      // at that point), so without a SECOND, post-fetch call the free-image
      // lifetime cap would never be checked at all for that caller —
      // reconciliation alone finds the truth, it does not enforce anything.
      final fetchCall = src.indexOf('await fetchImageAsBase64(');
      final sites = 'if (!isVideo && !isPro)'
          .allMatches(src)
          .map((m) => m.start)
          .where((i) => i < src.indexOf('geminiChat({'))
          .toList();
      expect(sites.length, 2,
          reason: 'one fast-path site (honest claim=image) and one mirror '
              'site (claim=video, served=image) are both required');
      expect(sites[0], lessThan(fetchCall), reason: 'the fast path runs before the Storage fetch');
      expect(sites[1], greaterThan(fetchCall), reason: 'the mirror runs after reconciliation');
      expect(_count(src, 'await checkFreeImageQuota(supabaseClient, userId, media_url, media_type, message)'), 2,
          reason: 'both sites delegate to the ONE helper, so the reply, the log row and the '
              'gate_reasons cannot drift between them');
    });
  });

  group('OI-153 — every refusal is a distinguishable 200/gated reply', () {
    const newReasons = [
      'pro_quota_unavailable',
      'tier_unavailable',
      'pro_image_daily_limit_reached',
      'pro_video_daily_limit_reached',
    ];

    test('each new gate_reason literal occurs exactly once, on a 200', () {
      for (final r in newReasons) {
        // The bare quoted literal — the two cap reasons sit inside ONE
        // `isVideo ? … : …` ternary, so `gate_reason: "<r>"` would match
        // neither of them.
        final needle = '"$r"';
        expect(_count(src, needle), 1,
            reason: '`$r` must be produced by exactly one branch');
        // The response carrying it must be a 200 — the coach-bubble path
        // the installed client already renders. A 4xx here would land in
        // sendWithMedia's catch as "Sorry, I couldn't analyse that photo."
        final at = src.indexOf(needle);
        final statusAt = src.indexOf('status:', at);
        expect(statusAt, greaterThan(at), reason: 'no status after `$r`');
        final statusLine = src.substring(statusAt, statusAt + 12);
        expect(statusLine.startsWith('status: 200'), isTrue,
            reason: '`$r` must ride a 200 response, got "$statusLine"');
      }
    });

    test('ledger error OR a non-numeric result → pro_quota_unavailable, honest copy, no cap claim (fail CLOSED)', () {
      // Hermes L23 F3 (2026-09-13): the refusal condition is the ERROR **or**
      // a result that is not a number. `consume_quota` returns int / -1;
      // `null` here is a shape drift, and the old `proCount as number` read
      // it as GRANTED. The anchor pins both halves of the condition.
      final branch = _span(
        src,
        'if (proConsumeError || typeof proCount !== "number")',
        '} else if (proCount === -1)',
      );
      expect(branch, contains('gate_reason: "pro_quota_unavailable"'));
      expect(branch, contains('expected an int'),
          reason: 'the non-numeric arm must say what shape arrived, so a '
              'drift is diagnosable from the log line alone');
      expect(_count(branch, 'gate_reason:'), 1,
          reason: 'the error branch must not also carry a cap reason');
      expect(branch, contains('imageLedgerUnavailable'));
      expect(branch, contains('videoLedgerUnavailable'));
      expect(branch.contains('DailyCapReached'), isFalse,
          reason: 'an unreadable ledger must never be reported as a reached cap');
      expect(branch, contains('gated: true'));
    });

    test('-1 → the cap reply with the cap passed in, resets_at, and refusal telemetry', () {
      final branch = _span(src, '} else if (proCount === -1)', '} else {');
      expect(branch, contains('console.warn('),
          reason: '-1 neither increments nor touches updated_at (128), so '
              'this warn is the only refusal telemetry');
      expect(branch, contains('"pro_image_daily_limit_reached"'));
      expect(branch, contains('"pro_video_daily_limit_reached"'));
      expect(branch, contains('proImageDailyCapReached(proCap)'),
          reason: 'the number in the copy must be the constant, never typed');
      expect(branch, contains('proVideoDailyCapReached(proCap)'));
      expect(branch, contains('resets_at'));
      expect(branch, contains('pro_daily_limit: proCap'));
      expect(branch, contains('gated: true'));
    });

    test('tier unknown → tier_unavailable, before either tier branch runs', () {
      expect(
          RegExp(r'error:\s*subscriptionError\s*\}\s*=\s*await supabaseClient')
              .hasMatch(src),
          isTrue,
          reason: 'the subscriptions read must CAPTURE its error — discarded, '
              'a PostgREST fault silently routed paying users down the free '
              'path and spent a lifetime free unit they did not own');
      final branch = _span(src, 'if (subscriptionError)', 'if (isVideo && !isPro)');
      expect(branch, contains('gate_reason: "tier_unavailable"'));
      expect(branch, contains('gated: true'));
      expect(branch, contains('imageLedgerUnavailable'));
      expect(branch, contains('videoLedgerUnavailable'));
    });

    test('the success body reports the PRO counter (null for non-PRO)', () {
      expect(src, contains('pro_daily_used: proDailyUsed'));
      expect(src.contains('proCount as number'), isFalse,
          reason: 'a cast is how a null result was read as a granted unit '
              '(L23 F3) — the value reaches proDailyUsed only past the '
              'typeof guard above');
      expect(RegExp(r'pro_daily_limit:\s*isPro\s*\?\s*proCap\s*:\s*null').hasMatch(src),
          isTrue);
    });
  });

  group('OI-153 — the copy exists, is rank-free, states the reset, sells nothing', () {
    test('the four new keys exist in the server copy file', () {
      for (final key in const [
        'imageLedgerUnavailable',
        'videoLedgerUnavailable',
        'proImageDailyCapReached(cap: number)',
        'proVideoDailyCapReached(cap: number)',
      ]) {
        expect(copy, contains(key), reason: 'missing $key');
      }
    });

    test('the cap copies interpolate the cap and name the midnight-IST reset', () {
      for (final fn in const ['proImageDailyCapReached', 'proVideoDailyCapReached']) {
        final body = _span(copy, '$fn(cap: number)', '},');
        expect(body, contains(r'${cap}'),
            reason: '$fn must interpolate the cap; a typed 50/10 would drift '
                'from the constant');
        expect(body, contains('midnight IST'));
        expect(body.contains('Upgrade'), isFalse,
            reason: 'a PRO user must never be shown an upgrade CTA');
        expect(body.contains('Recruit'), isFalse,
            reason: 'PRO users hold ranks — the cap copy is rank-free');
      }
    });

    test('the rank-free unavailable copies say "not a limit" and sell nothing', () {
      for (final key in const ['imageLedgerUnavailable', 'videoLedgerUnavailable']) {
        final body = _span(copy, '$key:', ',\n');
        expect(body, contains('not a limit'));
        expect(body.contains('Upgrade'), isFalse);
        expect(body.contains('Recruit'), isFalse);
      }
    });
  });
}
