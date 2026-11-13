import 'package:eth_fraud_guard/main.dart';
import 'package:eth_fraud_guard/l10n.dart';
import 'package:eth_fraud_guard/screens/onboarding_screen.dart';
import 'package:eth_fraud_guard/screens/offline_safety_screen.dart';
import 'package:eth_fraud_guard/services/backend_api.dart';
import 'package:eth_fraud_guard/widgets/risk_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Amharic is the initial app language', () {
    expect(L.lang, 'am');
  });

  test('backend init ignores and removes a previously saved URL', () async {
    SharedPreferences.setMockInitialValues({
      'api_base_url': 'http://10.0.2.2:8000',
    });

    await BackendApi.instance.init();

    final preferences = await SharedPreferences.getInstance();
    expect(BackendApi.baseUrl, 'https://fraudguard-et-1.onrender.com');
    expect(preferences.containsKey('api_base_url'), isFalse);
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

  testWidgets('onboarding language can change before signup', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    L.lang = 'am';
    addTearDown(() => L.lang = 'am');

    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () {})),
    );
    await tester.pump();

    expect(find.text(L.t('verify_payments_intro')), findsOneWidget);
    await tester.tap(find.byTooltip(L.t('switch_to_english')));
    await tester.pump();

    expect(L.lang, 'en');
    expect(find.text(L.t('verify_payments_intro')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motorcycle animation appears before onboarding finishes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    L.lang = 'am';
    addTearDown(() => L.lang = 'am');

    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () {})),
    );
    await tester.pump();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text(L.t('motorcycle_intro')), findsOneWidget);
    expect(find.byIcon(Icons.motorcycle), findsOneWidget);
    expect(find.text(L.t('get_started')), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('phone-sized sign-in layout shows the logo and app name cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    L.lang = 'am';

    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    final logo = tester.getRect(find.byIcon(Icons.shield_rounded));
    final appName = tester.getRect(find.text('FraudGuard ET'));
    expect(appName.top, greaterThan(logo.bottom));
    expect(appName.bottom, lessThan(tester.view.physicalSize.height));
    expect(find.textContaining('Connected to'), findsNothing);
    expect(find.textContaining('10.0.2.2'), findsNothing);
    expect(tester.takeException(), isNull);
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
