import 'package:flutter_test/flutter_test.dart';
import 'package:photon/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that brand new project text is present.
    expect(find.text('Brand New Project'), findsOneWidget);
  });
}
