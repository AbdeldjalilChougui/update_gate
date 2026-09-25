import 'package:flutter_test/flutter_test.dart';
import 'package:update_gate_example/main.dart';

void main() {
  testWidgets('starts with the optional dialog', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Version 1.4 brings offline mode.'), findsOneWidget);
  });
}
