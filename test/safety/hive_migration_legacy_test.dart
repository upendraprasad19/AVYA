import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_mig_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('migration: legacy coachBox content copied to coachBox_<hash>', () async {
    // Simulate pre-namespacing state: data lives in shared coachBox
    final legacy = await Hive.openBox('coachBox');
    await legacy.put('msg_1', {'role': 'user', 'content': 'hello'});
    await legacy.put('msg_2', {'role': 'assistant', 'content': 'hi'});
    await legacy.close();

    // Sign in user A → migration should fire
    const userId = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
    await HiveUserSession.openForUser(userId);

    // Namespaced box has the data
    final namespaced = Hive.box('coachBox_5f0a13b2');
    expect(namespaced.get('msg_1'), {'role': 'user', 'content': 'hello'});
    expect(namespaced.get('msg_2'), {'role': 'assistant', 'content': 'hi'});

    // Legacy shared box is gone
    expect(File('${tempDir.path}/coachBox.hive').existsSync(), false);

    await HiveUserSession.closeAll();
  });

  test('migration is idempotent — second call no-ops', () async {
    final legacy = await Hive.openBox('coachBox');
    await legacy.put('msg_1', {'role': 'user', 'content': 'hello'});
    await legacy.close();

    const userId = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
    await HiveUserSession.openForUser(userId);
    await HiveUserSession.closeAll();

    // Second open of same user — no legacy file remains, migration skips silently
    await HiveUserSession.openForUser(userId);
    final namespaced = Hive.box('coachBox_5f0a13b2');
    expect(namespaced.get('msg_1'), {'role': 'user', 'content': 'hello'});
    await HiveUserSession.closeAll();
  });
}
