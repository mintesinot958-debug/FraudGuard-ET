import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/backend_api.dart';
import '../widgets/risk_flag.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _history;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _history = BackendApi.instance.history();
  }

  Future<void> _refresh() async {
    final request = BackendApi.instance.history();
    setState(() => _history = request);
    await request;
  }

  String _typeLabel(Map<String, dynamic> item) =>
      item['kind'] == 'receipt' ? L.t('receipt_check') : L.t('transfer_check');

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return L.t('date_unavailable');
    final local = date.toLocal();
    final datePart =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final timePart =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$datePart • $timePart';
  }

  String _verificationLabel(String value) => switch (value) {
        'verified' => L.t('verified'),
        'unverified' => L.t('unverified'),
        'suspicious' => L.t('suspicious'),
        'likely_fake' => L.t('fake'),
        _ => value.replaceAll('_', ' '),
      };

  String _actionLabel(String value) => switch (value) {
        'allow' => L.t('allow'),
        'step_up' => L.t('stepup'),
        'hold' => L.t('hold'),
        'block' => L.t('block'),
        _ => value.replaceAll('_', ' '),
      };

  Future<void> _showDetails(Map<String, dynamic> item) async {
    final score = (item['risk_score'] as num).toInt();
    final reasons =
        (item['reasons'] as List<dynamic>? ?? []).map((e) => e.toString());
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_typeLabel(item)} • #${item['id']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_dateLabel(item['created_at'])),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RiskFlag(score: score),
                  Text('${L.t('risk')} $score/100'),
                ],
              ),
              const SizedBox(height: 16),
              _DetailLine(
                label: L.t('amount'),
                value: 'ETB ${(item['amount'] as num).toStringAsFixed(2)}',
              ),
              _DetailLine(
                label: L.t('verification'),
                value:
                    _verificationLabel(item['verification_status'] as String),
              ),
              _DetailLine(
                label: L.t('recommended_action'),
                value: _actionLabel(item['action'] as String),
              ),
              if (item['provider'] != null)
                _DetailLine(
                  label: L.t('provider'),
                  value: item['provider'].toString(),
                ),
              if (item['reference'] != null &&
                  item['reference'].toString().isNotEmpty)
                _DetailLine(
                  label: L.t('reference'),
                  value: item['reference'].toString(),
                ),
              const SizedBox(height: 16),
              Text(
                L.t('why_flagged'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (reasons.isEmpty)
                Text(L.t('no_risk_explanation'))
              else
                for (final reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(L.reason(reason))),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L.t('fraud_check_history')),
        actions: [
          IconButton(
            tooltip: L.t('refresh_history'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(L.t('history_load_fail')),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      child: Text(L.t('retry')),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allItems = snapshot.data!;
          final items = allItems.where((item) {
            return _filter == 'all' || item['kind'] == _filter;
          }).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  L
                      .t('your_latest_checks')
                      .replaceAll('{count}', '${allItems.length}'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'all', label: Text(L.t('all'))),
                    ButtonSegment(
                        value: 'receipt', label: Text(L.t('receipts'))),
                    ButtonSegment(
                        value: 'transfer', label: Text(L.t('transfers'))),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (selection) {
                    setState(() => _filter = selection.first);
                  },
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        allItems.isEmpty
                            ? L.t('no_fraud_checks')
                            : L.t('no_checks_category'),
                      ),
                    ),
                  )
                else
                  for (final item in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () => _showDetails(item),
                        leading: Icon(
                          item['kind'] == 'receipt'
                              ? Icons.receipt_long_outlined
                              : Icons.compare_arrows,
                        ),
                        title: Text(
                          '${_typeLabel(item)} • ETB ${(item['amount'] as num).toStringAsFixed(2)}',
                        ),
                        subtitle: Text(
                          '${_dateLabel(item['created_at'])} • ${_verificationLabel(item['verification_status'].toString())}',
                        ),
                        trailing: RiskFlag(
                          score: (item['risk_score'] as num).toInt(),
                        ),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
