// coach-log-truth (OI-368 / OI-369, plan docs/plans/coach-log-truth.md §3).
//
// Wiring pins for the write-claim rule, over COMMENT-STRIPPED source, counted
// and position-scoped. `ai-proxy` and `ai-media-proxy` call `serve()` at module
// scope and cannot be imported by a Deno test, so these pins prove the
// handlers use the builders the Deno golden / tool-loop / detector tests
// cover behaviourally (supabase/functions/_shared/write_claim_*_test.ts).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

int count(String haystack, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(haystack).length;

void main() {
  final proxy =
      readSourceFileStripped('supabase/functions/ai-proxy/index.ts');
  final media =
      readSourceFileStripped('supabase/functions/ai-media-proxy/index.ts');
  final loop = readSourceFileStripped('supabase/functions/_shared/tool-loop.ts');

  group('ai-proxy', () {
    test('ruleOn is read once, before the dedup read', () {
      const read = 'const ruleOn = !isWriteClaimRuleDisabled()';
      expect(count(proxy, read), 1);
      expect(proxy.indexOf(read), lessThan(proxy.indexOf('dedupCutoff')));
    });

    test('the prompt pieces come from the builders', () {
      expect(
          count(proxy,
              'const promptParts: string[] = [CAPTAIN_MANUAL, icbfLogInstructions(ruleOn)];'),
          1);
      expect(count(proxy, 'writeClaimSuffix(ruleOn)'), 1);
      expect(
          count(proxy,
              'daySwapRoutingBlock(isProUser, capabilities, ruleOn)'),
          1);
      expect(proxy, isNot(contains('FITNESS DATA LOGGING — INSTANT')));
    });

    test('the tool loop gets the rule', () {
      final call = proxy.indexOf('runToolLoop({');
      expect(call, isNot(-1));
      final close = proxy.indexOf('});', call);
      expect(proxy.substring(call, close), contains('writeClaimRule: ruleOn'));
    });

    test('two detector calls: after extractLogActions and in the replay branch',
        () {
      expect(count(proxy, 'logWriteClaimDetection('), 2);
      final replay = proxy.indexOf('if (dedup === "replay_reply" && recentDup)');
      final replayCall = proxy.indexOf('logWriteClaimDetection(', replay);
      expect(proxy.substring(replay, replayCall),
          isNot(contains('return new Response(')),
          reason: 'the replay call sits inside the replay branch');
      expect(
          proxy.substring(replayCall, replayCall + 120),
          contains(
              'logWriteClaimDetection("ai-proxy", recentDup.id, ruleOn, extracted.reply, () => replayCtxOf(extracted));'));
      final main = proxy.indexOf('const extracted = extractLogActions(loop.text);');
      expect(main, isNot(-1));
      expect(proxy.indexOf('logWriteClaimDetection(', main), greaterThan(main));
      // The ctx is a thunk, so its expressions run inside the helper's try.
      expect(
          count(proxy,
              'logWriteClaimDetection("ai-proxy", chatReservationId, ruleOn, cleanReply, () => ({'),
          1);
      expect(count(proxy, 'const cleanReply = extracted.reply;'), 1);
    });

    test('the dedup read selects id as its own column', () {
      final at = proxy.indexOf('dedupCutoff');
      final sel = RegExp(r'\.select\("([^"]*)"\)')
          .firstMatch(proxy.substring(at))!;
      final columns = sel.group(1)!.split(',').map((c) => c.trim()).toList();
      expect(columns, contains('id'));
    });

    test('the size log carries the flag', () {
      expect(
          proxy, contains(r'system_prompt_size=${systemPrompt.length}'));
      expect(proxy, contains(r'write_claim_rule=${ruleOn}'));
    });
  });

  group('ai-media-proxy', () {
    test('ruleOn is read once and feeds the authored prompt', () {
      expect(count(media, 'const ruleOn = !isWriteClaimRuleDisabled()'), 1);
      final authored = media.indexOf('asAuthoredPrompt(');
      final tail = media.indexOf(
          'mediaIcbfLogInstructions(ruleOn) + writeClaimSuffix(ruleOn, { tools: false })');
      final fence = media.indexOf('if (snapshot_json)');
      expect(authored, isNot(-1));
      expect(tail, greaterThan(authored));
      expect(tail, lessThan(fence),
          reason: 'the rule is authored text, before the snapshot fence');
      expect(media, isNot(contains('FITNESS DATA LOGGING — INSTANT')));
    });

    test('one detector call after extractLogActions(rawReply)', () {
      expect(count(media, 'logWriteClaimDetection('), 1);
      final ext = media.indexOf('const extracted = extractLogActions(rawReply);');
      expect(ext, isNot(-1));
      expect(media.indexOf('logWriteClaimDetection('), greaterThan(ext));
      expect(
          count(media,
              'logWriteClaimDetection("ai-media-proxy", null, ruleOn, extracted.reply, () => ({'),
          1);
      expect(count(media, 'ai_response: extracted.reply,'), 1);
      expect(count(media, 'let finalReply = extracted.reply;'), 1);
    });
  });

  test('tool-loop: the description swap feeds the declarations', () {
    expect(
        loop,
        matches(RegExp(
            r'applyWriteClaimDescriptions\(\s*allTools\(opts\.ctx\.isPro, opts\.capabilities\),\s*writeClaimRule,\s*\)\.map\(toolToFunctionDeclaration\)')));
  });
}
