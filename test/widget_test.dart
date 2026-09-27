import 'package:flutter_test/flutter_test.dart';
import 'package:allways_carrier/main.dart';

void main() {
  testWidgets('Carrier login renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CarrierLoginPage()),
    );
    await tester.pump();
    expect(find.text('ALLways Carrier'), findsOneWidget);
  });
}
