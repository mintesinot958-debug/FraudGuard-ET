import 'package:flutter/material.dart';
import '../l10n.dart';
import '../services/auth_store.dart';
import '../services/backend_api.dart';
import 'forgot_password_screen.dart';
import 'offline_safety_screen.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const AuthScreen({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = L.t('please_fill_all_fields'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registering) {
        await AuthStore.instance.register(email, _password.text);
      } else {
        await AuthStore.instance.login(email, _password.text);
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = L.t('cannot_reach_server'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPasswordReset() async {
    final reset = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim()),
      ),
    );
    if (reset == true && mounted) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t('password_reset_success'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: L.t(
              L.lang == 'en' ? 'switch_to_amharic' : 'switch_to_english',
            ),
            onPressed: () => setState(
              () => L.lang = L.lang == 'en' ? 'am' : 'en',
            ),
            icon: const Icon(Icons.language),
          ),
          IconButton(
            tooltip: L.t(widget.themeMode == ThemeMode.light
                ? 'switch_to_dark_mode'
                : 'switch_to_light_mode'),
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.themeMode == ThemeMode.light
                ? Icons.dark_mode_outlined
                : Icons.light_mode_outlined),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.shield_rounded,
                            size: 72,
                            color: theme.colorScheme.primary,
                          ),
                          Icon(
                            Icons.check_rounded,
                            size: 36,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'FraudGuard ET',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  _registering ? L.t('create_account') : L.t('welcome_back'),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  decoration: InputDecoration(
                      labelText: L.t('email_address'),
                      prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: L.t('password'),
                      prefixIcon: Icon(Icons.lock_outline)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_registering
                          ? L.t('create_account')
                          : L.t('sign_in')),
                ),
                TextButton(
                  onPressed: () => setState(() => _registering = !_registering),
                  child: Text(_registering
                      ? L.t('already_have_account')
                      : L.t('new_to_fraudguard')),
                ),
                if (!_registering)
                  TextButton(
                    onPressed: _busy ? null : _openPasswordReset,
                    child: Text(L.t('forgot_password')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OfflineSafetyScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.offline_bolt_outlined),
                  label: Text(L.t('offline_safety_mode')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
