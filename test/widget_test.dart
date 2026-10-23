import 'package:flutter_test/flutter_test.dart';
import 'package:photon/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VeriTrustApp());

    // Verify that VeriTrust title text is present.
    expect(find.text('VeriTrust'), findsWidgets);
  });
}
