import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n.dart';
import '../services/fraud_engine.dart';
import '../services/sms_monitor_service.dart';

class _ScannedPaymentSms {
  final PaymentSmsMessage message;
  final PaymentSmsAnalysis analysis;

  const _ScannedPaymentSms(this.message, this.analysis);
}

class SmsMonitorScreen extends StatefulWidget {
  const SmsMonitorScreen({super.key});

  @override
  State<SmsMonitorScreen> createState() => _SmsMonitorScreenState();
}

class _SmsMonitorScreenState extends State<SmsMonitorScreen> {
  List<_ScannedPaymentSms> _messages = [];
  bool _scanning = false;
  bool _hasScanned = false;
  String? _error;

  Future<void> _scanInbox() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('scan_recent_sms_confirm')),
        content: Text(L.t('sms_scan_privacy')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L.t('continue')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final granted = await SmsMonitorService.requestReadPermission();
      if (!granted) {
        throw StateError(L.t('sms_permission_denied'));
      }

      final sms = await SmsMonitorService.readRecentMessages();
      final payments = <_ScannedPaymentSms>[];
      for (final message in sms) {
        final analysis = FraudEngine.analyzePaymentSms(message.body);
        if (analysis.isPaymentRelated) {
          payments.add(_ScannedPaymentSms(message, analysis));
        }
      }
      if (mounted) {
        setState(() {
          _messages = payments;
          _hasScanned = true;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? L.t('sms_access_fail'));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Color _colorFor(ScamLabel label) => switch (label) {
        ScamLabel.safe => Colors.green,
        ScamLabel.suspicious => Colors.orange,
        ScamLabel.scam => Colors.red,
      };

  String _labelFor(ScamLabel label) => switch (label) {
        ScamLabel.safe => L.t('no_obvious_red_flags'),
        ScamLabel.suspicious => L.t('suspicious'),
        ScamLabel.scam => L.t('scam'),
      };

  Widget _messageCard(_ScannedPaymentSms item) {
    final color = _colorFor(item.analysis.label);
    final date = item.message.receivedAt.toLocal();
    final sender = item.message.sender.trim();
    final displaySender = sender.isEmpty
        ? L.t('unknown_sender')
        : RegExp(r'^[+0-9()\-\s]+$').hasMatch(sender)
            ? FraudEngine.maskPhone(sender)
            : sender;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displaySender,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${date.month}/${date.day}/${date.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(item.message.body),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.shield_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _labelFor(item.analysis.label),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text('${L.t('risk')} ${item.analysis.score}/100'),
              ],
            ),
            for (final reason in item.analysis.reasons) ...[
              const SizedBox(height: 6),
              Text('• ${L.reason(reason)}'),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Scaffold(
        appBar: AppBar(title: Text(L.t('sms_monitor_title'))),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(L.t('sms_android_only')),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(L.t('sms_monitor_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L.t('check_payment_messages'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(L.t('sms_scan_description')),
                  const SizedBox(height: 8),
                  Text(L.t('sms_warning_note')),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _scanning ? null : _scanInbox,
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sms_outlined),
                    label: Text(_scanning
                        ? L.t('scanning')
                        : L.t('scan_recent_payment_sms')),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          ],
          if (_hasScanned) ...[
            const SizedBox(height: 16),
            Text(
              '${L.t('payment_notifications_found')}: ${_messages.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_messages.isEmpty)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(L.t('no_payment_sms_found')),
                ),
              )
            else
              for (final message in _messages) _messageCard(message),
          ],
        ],
      ),
    );
  }
}
