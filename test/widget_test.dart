import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/app.dart';

void main() {
  testWidgets('App renders ICANBEFITTER text', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICanBeFitterApp()),
    );

    expect(find.text('ICANBEFITTER'), findsOneWidget);
  });
}
