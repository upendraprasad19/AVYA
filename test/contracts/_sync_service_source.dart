import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Drop-in replacement for `File('lib/core/services/sync_service.dart')`
/// used by source-grep contract tests across the codebase.
///
/// Returns a [File]-shaped facade whose `readAsStringSync()` /
/// `readAsString()` methods return the CONCATENATED source of
/// `lib/core/services/sync_service.dart` plus every `.dart` file
/// under `lib/core/services/sync/` (the part-file directory created
/// by the refactor/sync-service-part-split branch, 2026-05-13).
///
/// Source-grep tests should ALWAYS use this instead of reading
/// `sync_service.dart` directly, because methods may live in part
/// files. Both `existsSync()` and `lengthSync()` are also provided
/// so test guard checks (e.g. `expect(f.existsSync(), isTrue)`) keep
/// working unchanged.
///
/// Returns by VALUE, not by reference — each call re-reads from disk,
/// which is fine for test code.
class SyncServiceSourceFacade implements File {
  static const String _rootPath = 'lib/core/services/sync_service.dart';
  static const String _partsDirPath = 'lib/core/services/sync';

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    final root = File(_rootPath).readAsStringSync(encoding: encoding);
    final partsDir = Directory(_partsDirPath);
    if (!partsDir.existsSync()) return root;
    final parts = partsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync(encoding: encoding))
        .toList();
    return [root, ...parts].join('\n\n');
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);

  @override
  bool existsSync() => File(_rootPath).existsSync();

  @override
  Future<bool> exists() async => existsSync();

  @override
  String get path => _rootPath;

  // Implement File interface — most members are unused by tests.
  // We throw on any method that callers might accidentally rely on
  // (rather than silently misbehaving). If a test fails with
  // UnimplementedError, the test is doing something the helper
  // wasn't designed for and should be reviewed.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'SyncServiceSourceFacade does not implement '
      '${invocation.memberName} — this helper is for source-grep '
      'tests only. If you need the underlying File, refer to '
      'File(\'$_rootPath\') directly.',
    );
  }
}

/// Returns a [File]-shaped facade for the SyncService source.
/// Use everywhere a test currently does `File('lib/core/services/sync_service.dart')`.
File loadSyncServiceSource() => SyncServiceSourceFacade();
