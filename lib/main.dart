import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/scam_screen.dart';
import 'screens/score_screen.dart';
import 'screens/verify_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/education_screen.dart';
import 'screens/admin_management_screen.dart';
import 'screens/community_reports_screen.dart';
import 'services/auth_store.dart';
import 'services/backend_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackendApi.instance.init();
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _initialized = false;
  bool _showOnboarding = true;

  static const _seed = Color(0xFF0B7A3B);

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showOnboarding = !(prefs.getBool('onboarding_complete') ?? false);
      _initialized = true;
    });
  }

  void _toggleTheme() => setState(() => _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    if (_showOnboarding) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: _seed),
        home: OnboardingScreen(
            onFinished: () => setState(() => _showOnboarding = false)),
      );
    }

    return MaterialApp(
      title: 'FraudGuard ET',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: MainScreen(
        onToggleTheme: _toggleTheme,
        themeMode: _themeMode,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const MainScreen(
      {super.key, required this.onToggleTheme, required this.themeMode});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int tab = 0;
  Key _dashboardKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthStore.instance,
      builder: (context, _) {
        final authenticated = AuthStore.instance.isAuthenticated;
        final isAdmin = AuthStore.instance.isAdmin;

        if (!authenticated) {
          return AuthScreen(
            onToggleTheme: widget.onToggleTheme,
            themeMode: widget.themeMode,
          );
        }

        final pages = <Widget>[
          VerifyScreen(),
          ScamScreen(),
          ScoreScreen(),
          EducationScreen(),
          DashboardScreen(key: _dashboardKey),
          CommunityReportsScreen(),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(L.t('app_title'),
                style: TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings,
                      color: Colors.orange),
                  tooltip: L.t('admin_panel'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminManagementScreen()),
                  ),
                ),
              IconButton(
                onPressed: widget.onToggleTheme,
                icon: Icon(widget.themeMode == ThemeMode.light
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => L.lang = L.lang == 'en' ? 'am' : 'en'),
                child: Text(L.lang == 'en' ? 'አማ' : 'EN',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                  onPressed: AuthStore.instance.logout,
                  icon: const Icon(Icons.logout_rounded)),
            ],
          ),
          body: IndexedStack(index: tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() {
              tab = i;
              if (i == 4) _dashboardKey = UniqueKey();
            }),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.verified_user_outlined),
                  label: L.t('verify')),
              NavigationDestination(
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: L.t('nav_scam')),
              NavigationDestination(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: L.t('score')),
              NavigationDestination(
                  icon: const Icon(Icons.school_outlined), label: L.t('learn')),
              NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  label: L.t('dash')),
              NavigationDestination(
                  icon: const Icon(Icons.groups_outlined),
                  label: L.t('reports')),
            ],
          ),
        );
      },
    );
  }
}
