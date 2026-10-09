import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late String tmpDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = Directory.systemTemp.createTempSync('apk154_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmpDir);
    Hive.init(tmpDir);
  });

  setUp(() async {
    HiveUserSession.currentOwnerListenable.value = null;
  });

  tearDown(() async {
    await Hive.close();
    HiveUserSession.currentOwnerListenable.value = null;
  });

  test('GuardedBox.empty returns null on get and throws on put', () async {
    final empty = GuardedBox<dynamic>.empty('some-auth-uid');
    expect(empty.get('any_key'), isNull);
    expect(empty.length, 0);
    expect(empty.keys, isEmpty);
    expect(empty.isEmpty, isTrue);
    expect(empty.isNotEmpty, isFalse);
    expect(() => empty.put('k', 'v'), throwsA(isA<StateError>()));
    expect(() => empty.delete('k'), throwsA(isA<StateError>()));
  });
}
