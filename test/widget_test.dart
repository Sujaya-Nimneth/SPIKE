import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_ring/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmartRingApp()));
    // Verify the readiness score text is present on the home screen.
    expect(find.text('88'), findsNWidgets(2));
  });
}
