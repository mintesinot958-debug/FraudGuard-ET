import 'package:eth_fraud_guard/main.dart';
import 'package:eth_fraud_guard/l10n.dart';
import 'package:eth_fraud_guard/screens/offline_safety_screen.dart';
import 'package:eth_fraud_guard/widgets/risk_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Amharic is the initial app language', () {
    expect(L.lang, 'am');
  });

  testWidgets(
      'app opens to sign-in when onboarding is done and no session exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.text(L.t('welcome_back')), findsOneWidget);
    expect(find.textContaining(L.t('new_to_fraudguard')), findsOneWidget);
    expect(find.text(L.t('offline_safety_mode')), findsOneWidget);
  });

  testWidgets('sign-in page can change language and theme', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    L.lang = 'am';
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(L.t('switch_to_english')));
    await tester.pumpAndSettle();
    expect(find.text(L.t('welcome_back')), findsOneWidget);
    expect(L.lang, 'en');

    await tester.tap(find.byTooltip(L.t('switch_to_dark_mode')));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp).last).themeMode,
        ThemeMode.dark);

    L.lang = 'am';
  });

  testWidgets(
      'offline safety mode provides local message analysis and guidance',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OfflineSafetyScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text(L.t('offline_safety_mode')), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'You won a prize! Send your PIN and click http://example.com',
    );
    await tester.tap(find.text(L.t('analyze_offline')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining(L.t('scam')).first,
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining(L.t('scam')), findsOneWidget);
    expect(find.textContaining(L.t('reason_contains_link')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(L.t('stay_safe')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('ደረሰኝን ለማረጋገጥ'),
      findsOneWidget,
    );
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
    expect(find.text(L.t('low')), findsOneWidget);
    expect(find.text(L.t('medium')), findsOneWidget);
    expect(find.text(L.t('high')), findsOneWidget);
  });
}
