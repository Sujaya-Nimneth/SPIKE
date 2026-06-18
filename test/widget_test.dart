import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ring/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartRingApp());
    // Verify the readiness score text is present on the home screen.
    expect(find.text('88'), findsOneWidget);
  });
}
