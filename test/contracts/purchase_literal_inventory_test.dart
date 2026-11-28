// ADR-0022 / plan section 7 test 5: an inventory of upgrade wording.
//
// A TEST, not a gate (no check_*.dart script, so rule 24 does not apply). It
// counts, per file under lib/, the words that sit INSIDE string literals (so
// an identifier such as needExerciseUpgrade is not counted), case-insensitive:
// go pro, upgrade, renew, subscribe, unlock, purchase, both spellings of the
// rupee sign, monthlyPriceInr, yearlyPriceInr. Comments are stripped first.
//
// The scanner is a quote-state machine, not a regex: it handles nested quotes
// inside `${...}` interpolation, triple-quoted and raw strings, a phrase split
// across adjacent literals ('Tap to go ' 'PRO'), `//` inside a URL literal, a
// block-comment opener inside a line comment, and it ignores import / export /
// part URIs (B-pass 2026-11-20, F5: the first regex version missed all of
// those). The expected counts below were measured on the tree that introduced
// the no-purchase mode. A new file, a changed count or an unlisted file fails with
// a message that says what to do: classify the surface in plan section 5.2
// (docs/plans/2026-11-20-android-play-billing.md), make it safe in a binary
// that sells nothing (PurchaseCopy / showsUpgradeAffordance()), then update
// the table. A literal restored inside an allowlisted file changes that file's
// count and fails. PRESENCE only: the behavioural counterpart is
// purchase_surfaces_mode_none_test.dart.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Map<String, int> kExpected = {
  'lib/core/constants/purchase_mode.dart': 1,
  'lib/core/copy/payment_copy.dart': 1,
  'lib/core/copy/purchase_copy.dart': 18,
  'lib/core/copy/referral_copy.dart': 4,
  'lib/core/copy/wardroom_copy.dart': 5,
  'lib/core/services/auth_session_bootstrapper.dart': 1,
  'lib/core/services/badge_service.dart': 1,
  'lib/core/services/play_billing_service.dart': 3,
  'lib/core/services/rank_service.dart': 1,
  'lib/core/services/razorpay_service.dart': 3,
  'lib/core/services/subscription_service.dart': 4,
  'lib/core/services/sync_service.dart': 2,
  'lib/core/services/user_config_migrator.dart': 1,
  'lib/core/utils/hold_week_labels.dart': 1,
  'lib/features/admin/widgets/revenue_tab.dart': 4,
  'lib/features/ai_coach/copy/coach_replies.dart': 5,
  'lib/features/ai_coach/models/coach_memory.dart': 2,
  'lib/features/ai_coach/providers/ai_coach_provider.dart': 4,
  'lib/features/ai_coach/repositories/ai_coach_repository.dart': 1,
  'lib/features/ai_coach/screens/ai_coach/compact_header.dart': 3,
  'lib/features/ai_coach/screens/ai_coach/input_bar.dart': 2,
  'lib/features/ai_coach/screens/ai_coach/status_pill.dart': 1,
  'lib/features/ai_coach/services/ai_snapshot_builder.dart': 3,
  'lib/features/ai_coach/widgets/deep_analysis_card.dart': 1,
  'lib/features/nutrition/widgets/diet_supplements_section.dart': 1,
  'lib/features/profile/models/referrer_summary.dart': 1,
  'lib/features/profile/providers/profile_completeness_provider.dart': 1,
  'lib/features/profile/screens/delete_account_screen.dart': 2,
  'lib/features/profile/screens/notification_settings_screen.dart': 1,
  'lib/features/profile/screens/profile/profile_content.dart': 2,
  'lib/features/profile/screens/profile/screen.dart': 1,
  'lib/features/profile/screens/profile/subscription_section.dart': 4,
  'lib/features/profile/screens/progress_photos_screen.dart': 1,
  'lib/features/profile/screens/reports_screen.dart': 1,
  'lib/features/profile/screens/settings_screen.dart': 1,
  'lib/features/profile/services/referral_credit_notice_rules.dart': 1,
  'lib/features/profile/widgets/badges_grid.dart': 5,
  'lib/features/profile/widgets/build_stamp.dart': 1,
  'lib/features/profile/widgets/referrer_counters_block.dart': 1,
  'lib/features/profile/widgets/weekly_report_card.dart': 2,
  'lib/features/train/screens/graduation_screen.dart': 7,
  'lib/features/train/screens/phase_roadmap_screen.dart': 1,
  'lib/features/train/screens/preview_workout_screen.dart': 2,
  'lib/features/train/screens/train/phase_unlock_card.dart': 3,
  'lib/features/train/widgets/phase2_preview_card.dart': 2,
  'lib/features/train/widgets/plan_expired_card.dart': 1,
  'lib/shared/services/pro_phase_advance.dart': 2,
  'lib/shared/widgets/paywall_sheet.dart': 18,
  'lib/shared/widgets/paywall_play_body.dart': 8,
  'lib/shared/widgets/paywall_sheet_phase_variant.dart': 5,
  'lib/shared/widgets/pro_locked_overlay.dart': 1,
  'lib/shared/widgets/pro_pill_button.dart': 1,
  'lib/shared/widgets/subscription_expiry_banner.dart': 4,
};

class _Piece {
  _Piece(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

/// Scans [s] from [i]; strings found are appended to [target]. With
/// [untilBrace] it stops after the `}` that closes a `${` interpolation.
int _code(String s, int i, List<_Piece> target, List<_Piece> nested,
    {required bool untilBrace}) {
  var depth = 0;
  bool identChar(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);
  while (i < s.length) {
    final c = s[i];
    final n = i + 1 < s.length ? s[i + 1] : '';
    if (c == '/' && n == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && n == '*') {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
      continue;
    }
    final prevIdent = i > 0 && identChar(s[i - 1]);
    if (c == 'r' && (n == "'" || n == '"') && !prevIdent) {
      i = _string(s, i, i + 1, true, target, nested);
      continue;
    }
    if (c == "'" || c == '"') {
      i = _string(s, i, i, false, target, nested);
      continue;
    }
    if (untilBrace) {
      if (c == '{') depth++;
      if (c == '}') {
        if (depth == 0) return i + 1;
        depth--;
      }
    }
    i++;
  }
  return i;
}

/// Reads one string literal whose opening quote is at [q]; [start] is where
/// the literal begins (the `r` of a raw one). Returns the index after it.
int _string(String s, int start, int q, bool raw, List<_Piece> target,
    List<_Piece> nested) {
  final quote = s[q];
  final triple = q + 2 < s.length && s[q + 1] == quote && s[q + 2] == quote;
  var i = q + (triple ? 3 : 1);
  final buf = StringBuffer();
  while (i < s.length) {
    final c = s[i];
    if (!raw && c == r'\') {
      buf.write(c);
      if (i + 1 < s.length) buf.write(s[i + 1]);
      i += 2;
      continue;
    }
    if (!raw && c == r'$') {
      final n = i + 1 < s.length ? s[i + 1] : '';
      if (n == '{') {
        buf.write(' ');
        i = _code(s, i + 2, nested, nested, untilBrace: true);
        continue;
      }
      if (RegExp(r'[A-Za-z_]').hasMatch(n)) {
        buf.write(' ');
        i++;
        while (i < s.length && RegExp(r'[A-Za-z0-9_]').hasMatch(s[i])) {
          i++;
        }
        continue;
      }
    }
    if (triple) {
      if (c == quote &&
          i + 2 < s.length &&
          s[i + 1] == quote &&
          s[i + 2] == quote) {
        i += 3;
        break;
      }
    } else {
      if (c == quote) {
        i++;
        break;
      }
      if (c == '\n') break; // an unterminated literal: stop, do not run on
    }
    buf.write(c);
    i++;
  }
  target.add(_Piece(start, i, buf.toString()));
  return i;
}

final _directive = RegExp(r'(^|[\s;])(import|export|part\s+of|part)\s*$');

/// Every string group of [src]: nested interpolation literals each alone,
/// adjacent top-level literals joined (whitespace only between them), and
/// import / export / part URIs left out.
List<String> groups(String src) {
  final tops = <_Piece>[];
  final nested = <_Piece>[];
  _code(src, 0, tops, nested, untilBrace: false);
  tops.sort((a, b) => a.start.compareTo(b.start));
  final out = <String>[];
  var i = 0;
  while (i < tops.length) {
    var j = i;
    final buf = StringBuffer(tops[i].text);
    while (j + 1 < tops.length &&
        src.substring(tops[j].end, tops[j + 1].start).trim().isEmpty) {
      j++;
      buf.write(tops[j].text);
    }
    final from = tops[i].start < 24 ? 0 : tops[i].start - 24;
    final before = src.substring(from, tops[i].start);
    if (!_directive.hasMatch(before)) out.add(buf.toString());
    i = j + 1;
  }
  for (final p in nested) {
    out.add(p.text);
  }
  return out;
}

final _words = <RegExp>[
  RegExp(r'go\s+pro'),
  RegExp(r'get\s+pro'),
  RegExp('upgrade'),
  RegExp('renew'),
  RegExp('subscribe'),
  RegExp(r'\bsubscription\b'),
  RegExp('unlock'),
  RegExp('purchase'),
  RegExp(r'\bbuy\b'),
  RegExp(r'\btrial\b'),
  RegExp(r'\brs\.?\s?\d'),
  RegExp('\u20b9'),
  RegExp(r'\\u\{?20b9\}?'),
  RegExp('monthlypriceinr'),
  RegExp('yearlypriceinr'),
];

int count(String src) {
  var n = 0;
  for (final g in groups(src)) {
    final t = g.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final w in _words) {
      n += w.allMatches(t).length;
    }
  }
  return n;
}

Map<String, int> measure() {
  final out = <String, int>{};
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final n = count(e.readAsStringSync());
    if (n > 0) out[e.path.replaceAll(r'\', '/')] = n;
  }
  return out;
}

void main() {
  const how = 'classify this surface in section 5.2 of '
      'docs/plans/2026-11-20-android-play-billing.md, make it safe in a '
      'binary that sells nothing, then update kExpected';

  group('the scanner counts only words inside string literals', () {
    final cases = <String, int>{
      'final needExerciseUpgrade = 1;': 0,
      "// 'upgrade' in a comment\nfinal a = 'Upgrade now';": 1,
      "final a = 'Go PRO and unlock';": 2,
      "final a = '\u20b9349'; final b = r'\\u20b9';": 2,
      // nested quotes inside interpolation (a real hit on the tree)
      r"final a = '${isPro ? 'Manage' : 'Upgrade'} plan';": 1,
      r"final a = '${(p ?? '').contains('trial') ? 'EXPIRES' : 'RENEWS'} $d';": 2,
      // triple-quoted, multi-line
      "final a = '''\nTap to Upgrade\n''';": 1,
      // a phrase split across adjacent literals
      "final a = 'Tap here to go '\n    'PRO now';": 1,
      "final a = 'Up' 'grade';": 1,
      // a block-comment opener inside a line comment must not eat real code
      "// see lib/*.dart\nfinal a = 'Upgrade';\n/* real */": 1,
      // other wording
      "final a = 'Start your subscription';": 1,
      "final a = 'Get PRO';": 1,
      "final a = 'Buy now';": 1,
      "final a = 'Start free trial';": 1,
      "final a = 'Rs. 349';": 1,
      "final a = 'GO  PRO';": 1,
      r"final a = '\u{20B9}349';": 1,
      // things that must NOT count
      "import 'package:x/purchase_mode.dart';": 0,
      "export 'src/upgrade_card.dart';": 0,
      "part 'x_upgrade.dart';": 0,
      "part of 'unlock_screen.dart';": 0,
      "final a = 'x'; // 'Upgrade' note": 0,
      "final a = 'referral_trial'; final b = 'subscriptions';": 0,
      "final a = r'Upgrade';": 1,
      'final u = "https://x.test//a"; final b = "Upgrade";': 1,
    };
    cases.forEach((src, want) {
      test(src.replaceAll('\n', r'\n'), () => expect(count(src), want));
    });
  });

  test('no file outside the table carries upgrade wording', () {
    final got = measure();
    final extra = got.keys.where((k) => !kExpected.containsKey(k)).toList()
      ..sort();
    expect(extra, isEmpty, reason: 'unlisted: $extra; $how');
  });

  test('every listed file still has exactly the expected count', () {
    final got = measure();
    final diffs = <String>[];
    kExpected.forEach((path, want) {
      final have = got[path] ?? 0;
      if (have != want) diffs.add('$path: expected $want, found $have');
    });
    expect(diffs, isEmpty, reason: '${diffs.join('; ')}; $how');
  });
}
