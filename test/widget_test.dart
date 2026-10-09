import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allways_driver_partner/main.dart';

void main() {
  testWidgets('Carrier login renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DriverPartnerLoginPage()),
    );
    await tester.pump();
    expect(find.text('ALLways Driver Partner'), findsOneWidget);
  });
}
