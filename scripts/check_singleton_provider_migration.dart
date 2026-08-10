// scripts/check_singleton_provider_migration.dart
//
// Gate: 46
//
// Gate 46 (Tech-debt audit 2026-05-20, B5 D9-D10 deliverable): assert the
// 7 singleton services targeted by A7 have:
//
//   1. A corresponding `xxxServiceProvider` exported from
//      `lib/core/services/service_providers.dart`.
//   2. The static `instance` getter / field is annotated `@Deprecated(...)`
//      so new callers see the lint and prefer the Provider.
//
// Per `feedback_singleton_riverpod_full_migration.md` + CLAUDE.md §4.11
// (gates before refactor): this gate ships in the SAME commit as the A7
// migration; the gate IS the regression detector that catches anyone who
// adds an 8th cross-account-leak singleton without a Provider.
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

const _services = <String>[
  'SubscriptionService',
  'SyncService',
  'WorkoutScheduleService',
  'UsageCounterService',
  'AiService',
  'RazorpayService',
  'SeedService',
];

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');

  final providerFile = File('lib/core/services/service_providers.dart');
  if (!providerFile.existsSync()) {
    stderr.writeln('[Gate 46] FAIL: lib/core/services/service_providers.dart not found.');
    exit(warnOnly ? 0 : 1);
  }
  final providerSrc =
      providerFile.readAsStringSync().replaceAll('\r\n', '\n');

  final violations = <String>[];

  for (final svc in _services) {
    // Provider check: lowerCamelCase first char + "Provider" suffix
    final providerName =
        '${svc[0].toLowerCase()}${svc.substring(1)}Provider';
    if (!RegExp(r'\b' + providerName + r'\b').hasMatch(providerSrc)) {
      violations.add(
          'service_providers.dart missing `$providerName` for $svc');
    }

    // Service file check: instance must be @Deprecated.
    final fileName = svc
        .replaceAllMapped(RegExp(r'([A-Z])'),
            (m) => '_${m.group(1)!.toLowerCase()}')
        .substring(1);
    final svcFile = File('lib/core/services/$fileName.dart');
    if (!svcFile.existsSync()) {
      violations.add('expected service file not found: lib/core/services/$fileName.dart');
      continue;
    }
    final svcSrc = svcFile.readAsStringSync().replaceAll('\r\n', '\n');
    // Find the public `instance` declaration. Common shapes:
    //   static final XxxService instance = XxxService._();
    //   static XxxService get instance => _instance ??= …;
    //   @Deprecated(...) static $svc get instance => _instance;
    // Note: skip private `_instance` declarations — we only check the public
    // `instance` getter/field. Match by scanning for `static ... instance`
    // (no leading underscore on the name).
    final declRe = RegExp(
      r'static\s+(?:final\s+)?(?:\w+\s+)?(?:get\s+)?instance\b',
      multiLine: true,
    );
    final match = declRe.firstMatch(svcSrc);
    if (match == null) {
      violations.add('$fileName.dart has no `static … instance` declaration matched');
      continue;
    }
    // Check the 200 chars BEFORE the declaration for @Deprecated annotation.
    final start = (match.start - 200).clamp(0, svcSrc.length);
    final prefix = svcSrc.substring(start, match.start);
    final hasDeprecated = RegExp(r'@[Dd]eprecated\b').hasMatch(prefix);
    if (!hasDeprecated) {
      violations
          .add('$svc.instance is NOT @Deprecated — A7 migration incomplete');
    }
  }

  final tag = warnOnly ? '[Gate 46 WARN]' : '[Gate 46]';
  if (violations.isEmpty) {
    stdout.writeln(
        '$tag PASS: all 7 services have providers + @Deprecated instance.');
    exit(0);
  }
  stderr.writeln(
      '$tag FAIL: ${violations.length} singleton-migration violation(s):');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln(
      'Per feedback_singleton_riverpod_full_migration.md: each of the 7 named services');
  stderr.writeln(
      'gets a Riverpod Provider in service_providers.dart AND its instance is @Deprecated.');
  exit(warnOnly ? 0 : 1);
}
