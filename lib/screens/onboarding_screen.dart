import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import '../l10n.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  List<OnboardingItem> get _items => [
        OnboardingItem(
          title: L.t('verify_payments_intro'),
          description: L.t('verify_payments_intro_desc'),
          lottieUrl:
              'https://assets10.lottiefiles.com/packages/lf20_6sxyjyjj.json', // Security shield
          icon: Icons.verified_user,
        ),
        OnboardingItem(
          title: L.t('detect_scams_intro'),
          description: L.t('detect_scams_intro_desc'),
          lottieUrl:
              'https://assets10.lottiefiles.com/packages/lf20_t9gk1yfw.json', // Alert/Warning
          icon: Icons.chat_bubble,
        ),
        OnboardingItem(
          title: L.t('secure_transfers_intro'),
          description: L.t('secure_transfers_intro_desc'),
          lottieUrl:
              'https://assets10.lottiefiles.com/packages/lf20_ai93y4ym.json', // Wallet/Payment
          icon: Icons.account_balance_wallet,
        ),
        OnboardingItem(
          title: L.t('motorcycle_intro'),
          description: L.t('motorcycle_intro_desc'),
          icon: Icons.motorcycle,
          animateMotorcycle: true,
        ),
      ];

  void _complete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Tooltip(
                  message: L.t(
                    L.lang == 'en' ? 'switch_to_amharic' : 'switch_to_english',
                  ),
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => L.lang = L.lang == 'en' ? 'am' : 'en',
                    ),
                    icon: const Icon(Icons.language),
                    label: Text(L.lang == 'en' ? 'አማ' : 'EN'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: item.animateMotorcycle ? 160 : 200,
                          child: item.animateMotorcycle
                              ? _MotorcycleRideAnimation(
                                  bikeColor: theme.colorScheme.primary,
                                  roadColor: theme.colorScheme.outlineVariant,
                                )
                              : Lottie.network(
                                  item.lottieUrl!,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                    item.icon,
                                    size: 120,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          item.title,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          item.description,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _items.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary
                                  .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (_currentPage < _items.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _complete();
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                    child: Text(_currentPage == _items.length - 1
                        ? L.t('get_started')
                        : L.t('next')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingItem {
  final String title;
  final String description;
  final String? lottieUrl;
  final IconData icon;
  final bool animateMotorcycle;

  OnboardingItem({
    required this.title,
    required this.description,
    this.lottieUrl,
    required this.icon,
    this.animateMotorcycle = false,
  });
}

class _MotorcycleRideAnimation extends StatefulWidget {
  final Color bikeColor;
  final Color roadColor;

  const _MotorcycleRideAnimation({
    required this.bikeColor,
    required this.roadColor,
  });

  @override
  State<_MotorcycleRideAnimation> createState() =>
      _MotorcycleRideAnimationState();
}

class _MotorcycleRideAnimationState extends State<_MotorcycleRideAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const bikeSize = 72.0;
        final travelDistance = constraints.maxWidth + bikeSize * 2;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Container(height: 3, color: widget.roadColor),
              ),
              Positioned(
                left: _controller.value * travelDistance - bikeSize,
                top: 48,
                child: Icon(
                  Icons.motorcycle,
                  size: bikeSize,
                  color: widget.bikeColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
