// scripts/check_workout_schedule_split.dart
//
// Gate 47 (Tech-debt audit 2026-05-20, B5 D13-D17 / A2 deliverable):
// assert the 4-way split of `WorkoutScheduleService` is in place.
//
// The original ~1970-line `workout_schedule_service.dart` was split into
// 4 services in A2:
//
//   - WorkoutScheduleReadService — plan generation + reads.
//   - WorkoutScheduleWriteService — markCompleted / markSkipped / pause /
//     redoWeek4 / copyWeek.
//   - SwapService — swap days / swap exercise / shorten / travel mode.
//   - TemplateService — assignTemplateToDate / unschedule / cleanSync.
//
// This gate locks the split in place:
//
//   1. Each of the 4 new service files exists at the named path.
//   2. Each service file contains its expected class declaration.
//   3. Each service has a corresponding Provider in
//      lib/core/services/service_providers.dart.
//   4. The original workout_schedule_service.dart is the @Deprecated shim
//      (still exists for caller back-compat).
//
// Per CLAUDE.md §4.11 (gates before refactor): this gate ships in the
// SAME commit as the A2 split.
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

const _splitServices = <_SplitService>[
  _SplitService(
    className: 'WorkoutScheduleReadService',
    filePath: 'lib/core/services/workout_schedule_read_service.dart',
    providerName: 'workoutScheduleReadServiceProvider',
  ),
  _SplitService(
    className: 'WorkoutScheduleWriteService',
    filePath: 'lib/core/services/workout_schedule_write_service.dart',
    providerName: 'workoutScheduleWriteServiceProvider',
  ),
  _SplitService(
    className: 'SwapService',
    filePath: 'lib/core/services/swap_service.dart',
    providerName: 'swapServiceProvider',
  ),
  _SplitService(
    className: 'TemplateService',
    filePath: 'lib/core/services/template_service.dart',
    providerName: 'templateServiceProvider',
  ),
];

const _shimPath = 'lib/core/services/workout_schedule_service.dart';
const _providersPath = 'lib/core/services/service_providers.dart';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final violations = <String>[];

  // 1. Each split service file exists with expected class declaration.
  for (final svc in _splitServices) {
    final file = File(svc.filePath);
    if (!file.existsSync()) {
      violations.add('split service file missing: ${svc.filePath}');
      continue;
    }
    final src = file.readAsStringSync().replaceAll('\r\n', '\n');
    if (!RegExp(r'class\s+' + svc.className + r'\b').hasMatch(src)) {
      violations.add(
          '${svc.filePath} does not declare class ${svc.className}');
    }
  }

  // 2. Each service has a Provider in service_providers.dart.
  final providerFile = File(_providersPath);
  if (!providerFile.existsSync()) {
    violations.add('service_providers.dart not found at $_providersPath');
  } else {
    final providerSrc =
        providerFile.readAsStringSync().replaceAll('\r\n', '\n');
    for (final svc in _splitServices) {
      if (!RegExp(r'\b' + svc.providerName + r'\b').hasMatch(providerSrc)) {
        violations.add(
            'service_providers.dart missing Provider `${svc.providerName}` for ${svc.className}');
      }
    }
  }

  // 3. The shim file exists and is @Deprecated.
  final shimFile = File(_shimPath);
  if (!shimFile.existsSync()) {
    violations.add('shim file missing: $_shimPath');
  } else {
    final shimSrc = shimFile.readAsStringSync().replaceAll('\r\n', '\n');
    // Look for @Deprecated annotation preceding `class WorkoutScheduleService`.
    final declMatch = RegExp(r'@Deprecated\([^)]*\)\s*\nclass\s+WorkoutScheduleService\b')
        .hasMatch(shimSrc);
    if (!declMatch) {
      violations.add(
          'WorkoutScheduleService class in $_shimPath is not @Deprecated — A2 shim must mark the class so callers see the lint');
    }
  }

  if (violations.isEmpty) {
    stdout.writeln(
        '[Gate 47] PASS: WorkoutScheduleService 4-way split intact (Read/Write/Swap/Template + @Deprecated shim).');
    exit(0);
  }

  stderr.writeln('[Gate 47] FAIL: ${violations.length} violation(s):');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exit(warnOnly ? 0 : 1);
}

class _SplitService {
  final String className;
  final String filePath;
  final String providerName;
  const _SplitService({
    required this.className,
    required this.filePath,
    required this.providerName,
  });
}
