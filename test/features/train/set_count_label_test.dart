// OI-371: plural count labels for logged-exercise rows, joined with a
// non-breaking space (U+00A0) so a wrapped row never splits a number from
// its unit.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/utils/set_count_label.dart';

void main() {
  final nb = String.fromCharCode(0xA0);

  test('sets: singular at 1, plural otherwise', () {
    expect(setCountLabel(1), '1${nb}set');
    expect(setCountLabel(3), '3${nb}sets');
    expect(setCountLabel(0), '0${nb}sets');
  });

  test('reps: singular at 1, plural otherwise', () {
    expect(repCountLabel(1), '1${nb}rep');
    expect(repCountLabel(12), '12${nb}reps');
  });

  test('the separator keeps the dot on the line it ends', () {
    expect(kNbsp, nb);
    expect(kDetailSeparator, '$nb· ');
  });
}
