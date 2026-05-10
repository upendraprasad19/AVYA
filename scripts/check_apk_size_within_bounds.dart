// scripts/check_apk_size_within_bounds.dart
//
// Gate 13: APK size within ±10% of last shipped size.
//
// Reads backups/apk_sizes.json. Compares the freshly built APK at
// build/app/outputs/flutter-apk/app-prod-release.apk to the most recent
// entry. Fails if delta > ±10%.
//
// Special cases:
//   - If backups/apk_sizes.json doesn't exist → create it as {} and exit 0.
//   - If APK file doesn't exist → exit 0 (script run before build).
//   - If --record flag is passed: records the current APK size into
//     backups/apk_sizes.json under the current pubspec.yaml version.
//
// Usage:
//   dart run scripts/check_apk_size_within_bounds.dart            # check only
//   dart run scripts/check_apk_size_within_bounds.dart --record   # check + record

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final apkPath =
      '$projectRoot/build/app/outputs/flutter-apk/app-prod-release.apk';
  final sizesPath = '$projectRoot/backups/apk_sizes.json';
  final shouldRecord = args.contains('--record');

  // ── 1. Initialize sizes file if missing ───────────────────────────────────

  final sizesFile = File(sizesPath);
  if (!sizesFile.existsSync()) {
    sizesFile
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    stdout.writeln(
        '[Gate 13] INFO — backups/apk_sizes.json not found; created empty. First run, exit 0.');
    exit(0);
  }

  // ── 2. Check if APK exists ────────────────────────────────────────────────

  final apkFile = File(apkPath);
  if (!apkFile.existsSync()) {
    stdout.writeln(
        '[Gate 13] SKIP — APK not found at $apkPath (run after build). Exit 0.');
    exit(0);
  }

  final apkSize = apkFile.lengthSync();

  // ── 3. Load existing sizes ────────────────────────────────────────────────

  late Map<String, dynamic> sizes;
  try {
    sizes = jsonDecode(sizesFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln(
        '[Gate 13] ERROR — could not parse backups/apk_sizes.json: $e');
    exit(1);
  }

  // ── 4. Find most recent entry ─────────────────────────────────────────────

  // Entries keyed by version string "1.0.0+N".
  // Sort by N numerically to find the latest.
  final versionKeys = sizes.keys.toList();
  versionKeys.sort((a, b) {
    final na = _versionCode(a);
    final nb = _versionCode(b);
    return na.compareTo(nb);
  });

  int? lastSize;
  String? lastVersion;
  if (versionKeys.isNotEmpty) {
    final last = versionKeys.last;
    final entry = sizes[last] as Map<String, dynamic>?;
    if (entry != null && entry.containsKey('size_bytes')) {
      lastSize = entry['size_bytes'] as int?;
      lastVersion = last;
    }
  }

  // ── 5. Compare ────────────────────────────────────────────────────────────

  if (lastSize != null && lastSize > 0) {
    final delta = (apkSize - lastSize).abs();
    final pct = (delta / lastSize) * 100;

    if (pct > 10) {
      final direction = apkSize > lastSize ? 'GREW' : 'SHRANK';
      stderr.writeln('\n[Gate 13] FAIL — APK $direction by ${pct.toStringAsFixed(1)}%'
          ' (last: ${_mb(lastSize)} MB ($lastVersion),'
          ' now: ${_mb(apkSize)} MB).');
      stderr.writeln(
          '  If intentional (large asset added), update backups/apk_sizes.json'
          ' manually to reset the baseline.');
      exit(1);
    } else {
      stdout.writeln('[Gate 13] PASS — APK size ${_mb(apkSize)} MB'
          ' (${pct.toStringAsFixed(1)}% vs last shipped ${_mb(lastSize)} MB @ $lastVersion).');
    }
  } else {
    stdout.writeln(
        '[Gate 13] PASS — no prior size baseline; skipping delta check.');
  }

  // ── 6. Record (if --record flag) ──────────────────────────────────────────

  if (shouldRecord) {
    final version = _readPubspecVersion(projectRoot);
    if (version == null) {
      stderr.writeln(
          '[Gate 13] WARN — could not read version from pubspec.yaml; skipping record.');
    } else {
      final md5 = await _computeMd5(apkPath);
      final now = DateTime.now().toUtc().toIso8601String();
      sizes[version] = {
        'md5': md5,
        'size_bytes': apkSize,
        'shipped_at': now,
      };
      sizesFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(sizes),
      );
      stdout.writeln('[Gate 13] RECORDED — $version: ${_mb(apkSize)} MB, md5 $md5');
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

int _versionCode(String version) {
  // "1.0.0+17" → 17
  final plusIdx = version.lastIndexOf('+');
  if (plusIdx == -1) return 0;
  return int.tryParse(version.substring(plusIdx + 1)) ?? 0;
}

String _mb(int bytes) =>
    (bytes / (1024 * 1024)).toStringAsFixed(1);

String? _readPubspecVersion(String projectRoot) {
  final pubspecFile = File('$projectRoot/pubspec.yaml');
  if (!pubspecFile.existsSync()) return null;
  final lines = pubspecFile.readAsLinesSync();
  for (final line in lines) {
    if (line.startsWith('version:')) {
      return line.replaceFirst('version:', '').trim();
    }
  }
  return null;
}

Future<String> _computeMd5(String path) async {
  // On Windows/Mac/Linux, run md5sum or certutil for a quick MD5.
  // Fall back to a simple hex representation of the size if unavailable.
  ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run(
      'certutil',
      ['-hashfile', path, 'MD5'],
      runInShell: true,
    );
    if (result.exitCode == 0) {
      final lines = (result.stdout as String).split('\n');
      if (lines.length >= 2) {
        return lines[1].trim().replaceAll(' ', '');
      }
    }
  } else {
    result = await Process.run('md5sum', [path]);
    if (result.exitCode == 0) {
      return (result.stdout as String).split(' ').first.trim();
    }
  }
  // Fallback: not ideal but non-blocking
  return 'unknown-${File(path).lengthSync()}';
}
