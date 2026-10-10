import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allways_driver_partner/main.dart';

void main() {

  test('PIN verification accepts the deployed and legacy success keys', () {
    expect(pinVerificationSucceeded({'ok': true, 'rideId': 'ride-1'}), isTrue);
    expect(pinVerificationSucceeded({'verified': true}), isTrue);
    expect(pinVerificationSucceeded({'ok': false}), isFalse);
    expect(pinVerificationSucceeded({'verified': false}), isFalse);
    expect(pinVerificationSucceeded('not-a-response'), isFalse);
  });
  testWidgets('Carrier login renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DriverPartnerLoginPage()),
    );
    await tester.pump();
    expect(find.text('ALLways Driver Partner'), findsOneWidget);
  });
}
