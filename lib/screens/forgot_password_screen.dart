import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n.dart';
import '../services/backend_api.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, required this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = L.t('please_fill_all_fields'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendApi.instance.requestPasswordReset(email);
      if (!mounted) return;
      setState(() => _codeSent = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = L.t('cannot_reach_server'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_code.text.trim().length != 8) {
      setState(() => _error = L.t('reset_code_invalid_format'));
      return;
    }
    if (_newPassword.text.length < 10) {
      setState(() => _error = L.t('password_min_length'));
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _error = L.t('passwords_do_not_match'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendApi.instance.resetPassword(
        email: _email.text.trim(),
        code: _code.text.trim(),
        newPassword: _newPassword.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = L.t('cannot_reach_server'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(L.t('forgot_password'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  L.t('forgot_password_instructions'),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  enabled: !_codeSent && !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: L.t('email_address'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  Text(
                    L.t('reset_code_generic_response'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: InputDecoration(
                      labelText: L.t('reset_code'),
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newPassword,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: L.t('new_password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmPassword,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: L.t('confirm_new_password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : _codeSent
                          ? _resetPassword
                          : _requestCode,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          L.t(_codeSent ? 'reset_password' : 'send_reset_code'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
