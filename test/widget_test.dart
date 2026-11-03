import 'package:eth_fraud_guard/main.dart';
import 'package:eth_fraud_guard/widgets/risk_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app opens to sign-in when onboarding is done and no session exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.textContaining('Create account'), findsOneWidget);
  });

  testWidgets('risk flags use low, medium, and high score thresholds',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Wrap(
          children: [
            RiskFlag(score: 29),
            RiskFlag(score: 30),
            RiskFlag(score: 60),
          ],
        ),
      ),
    );

    // RiskFlag renders its label in upper case.
    expect(find.text('LOW'), findsOneWidget);
    expect(find.text('MEDIUM'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
  });
}
