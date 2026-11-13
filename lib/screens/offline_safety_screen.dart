import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/fraud_engine.dart';
import 'sms_monitor_screen.dart';

class OfflineSafetyScreen extends StatefulWidget {
  const OfflineSafetyScreen({super.key});

  @override
  State<OfflineSafetyScreen> createState() => _OfflineSafetyScreenState();
}

class _OfflineSafetyScreenState extends State<OfflineSafetyScreen> {
  final _messageController = TextEditingController();
  ScamResult? _result;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _analyzeMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() => _result = FraudEngine.checkMessage(message));
  }

  Color _resultColor(ScamLabel label) => switch (label) {
        ScamLabel.safe => Colors.green,
        ScamLabel.suspicious => Colors.orange,
        ScamLabel.scam => Colors.red,
      };

  String _resultLabel(ScamLabel label) => switch (label) {
        ScamLabel.safe => L.t('no_obvious_red_flags'),
        ScamLabel.suspicious => L.t('suspicious'),
        ScamLabel.scam => L.t('scam'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canScanSms = defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      appBar: AppBar(title: Text(L.t('offline_safety_mode'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.offline_bolt_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(L.t('offline_notice')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L.t('check_message_locally'),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(L.t('offline_message_note')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: L.t('paste_msg'),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_result != null) setState(() => _result = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _analyzeMessage,
                    icon: const Icon(Icons.shield_outlined),
                    label: Text(L.t('analyze_offline')),
                  ),
                  if (_result case final result?) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _resultColor(result.label),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_resultLabel(result.label)} • ${L.t('risk')} ${result.score}/100',
                            style: TextStyle(
                              color: _resultColor(result.label),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (result.reasons.isEmpty)
                            Text(L.t('no_warning_signs'))
                          else
                            for (final reason in result.reasons)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• ${L.reason(reason)}'),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L.t('offline_low_score_note'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (canScanSms) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: Text(L.t('scan_recent_payment_sms')),
                subtitle: Text(L.t('offline_sms_note')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SmsMonitorScreen(),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.t('stay_safe'), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  for (final tipKey in const [
                    'tip_keep_codes_private',
                    'tip_verify_in_official_app',
                    'tip_avoid_unexpected_links',
                    'tip_pause_if_pressured',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(L.t(tipKey))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.account_balance_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(L.t('offline_verification_note')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
