// test/contracts/plate_attribution_surface_test.dart
//
// CC BY-SA 4.0 requires attribution to reach the RECIPIENT of the work. 292
// licensed assets ship inside this app, and before this batch `lib/` had zero
// hits for showLicensePage, LicenseRegistry or AboutDialog — there was no
// credit surface at all. A repo-side ATTRIBUTION.md discharges nothing: it is
// not distributed to anyone who installs the APK.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*'), '');

void main() {
  test('the plate artwork licence is registered at startup', () {
    final src = _strip(File('lib/main.dart').readAsStringSync());
    expect(src.contains('LicenseRegistry.addLicense'), isTrue,
        reason: 'CC BY-SA artwork ships with no licence registered');
    expect(src.contains('workout-guide') || src.contains('exercise_plates'),
        isTrue,
        reason: 'the registered licence does not name its source');
  });

  test('the licence text ships as an asset', () {
    final f = File('assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt');
    expect(f.existsSync(), isTrue);
    final t = f.readAsStringSync();
    // Attribution, licence link, and a statement of what was changed are the
    // three things CC BY-SA actually requires of an adaptation.
    expect(t.contains('CC BY-SA 4.0'), isTrue);
    expect(t.contains('creativecommons.org/licenses/by-sa/4.0'), isTrue);
    expect(t.toLowerCase().contains('changes made') ||
        t.toLowerCase().contains('adaptation'), isTrue,
        reason: 'an adaptation must state what was changed');
  });

  test('a user can reach the credits from the Profile tab', () {
    final hits = Directory('lib/features/profile')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => _strip(f.readAsStringSync()).contains('showLicensePage'))
        .toList();
    expect(hits, isNotEmpty,
        reason: 'the licence page is registered but nothing opens it');
  });
}
