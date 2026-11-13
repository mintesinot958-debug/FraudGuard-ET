import 'package:flutter/material.dart';
import '../l10n.dart';
import '../services/backend_api.dart';

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _descriptionController = TextEditingController();

  late Future<Map<String, dynamic>> _reconciliation;
  bool _showForm = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reconciliation = BackendApi.instance.reconciliation();
  }

  @override
  void dispose() {
    _providerController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _reconciliation = BackendApi.instance.reconciliation();
    });
    try {
      await _reconciliation;
    } catch (_) {
      // The FutureBuilder displays the request error and Retry action.
    }
  }

  Future<void> _addExpectedPayment() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await BackendApi.instance.addExpectedPayment(
        provider: _providerController.text.trim(),
        expectedAmount: double.parse(_amountController.text.trim()),
        reference: _referenceController.text.trim(),
        description: _descriptionController.text.trim(),
      );
      _providerController.clear();
      _amountController.clear();
      _referenceController.clear();
      _descriptionController.clear();
      setState(() => _showForm = false);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${L.t('could_not_add_expected_payment')}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteExpectedPayment(int id) async {
    try {
      await BackendApi.instance.deleteExpectedPayment(id);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${L.t('could_not_remove_expected_payment')}: $error')),
        );
      }
    }
  }

  Color _statusColor(String status) => switch (status) {
        'matched' => Colors.green,
        'amount_mismatch' || 'duplicate' => Colors.red,
        _ => Colors.orange,
      };

  String _statusLabel(String status) => switch (status) {
        'matched' => L.t('matched'),
        'amount_mismatch' => L.t('amount_mismatch'),
        'duplicate' => L.t('duplicate_receipt'),
        _ => L.t('missing'),
      };

  Widget _expectedPaymentCard(Map<String, dynamic> item) {
    final actual = (item['actual_transactions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final status = item['status'] as String;

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
                    (item['description'] as String).isEmpty
                        ? item['provider'] as String
                        : item['description'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: L.t('remove_expected_payment'),
                  onPressed: () =>
                      _deleteExpectedPayment((item['id'] as num).toInt()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Text(
              '${item['provider']} • ${L.t('expected_amount')} ETB ${(item['expected_amount'] as num).toStringAsFixed(2)}',
            ),
            if (item['reference'] != null &&
                (item['reference'] as String).isNotEmpty)
              Text('${L.t('reference')}: ${item['reference']}'),
            const SizedBox(height: 8),
            Chip(
              avatar: Icon(
                status == 'matched'
                    ? Icons.check_circle_outline
                    : status == 'missing'
                        ? Icons.hourglass_empty
                        : Icons.warning_amber_outlined,
                color: _statusColor(status),
                size: 18,
              ),
              label: Text(_statusLabel(status)),
            ),
            for (final transaction in actual) ...[
              const SizedBox(height: 6),
              Text(
                '${L.t('received_amount')} ETB ${(transaction['amount'] as num).toStringAsFixed(2)}'
                ' • ${L.t('receipt_number')} #${transaction['id']}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _form() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L.t('add_expected_payment'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(L.t('reconciliation_description')),
              const SizedBox(height: 16),
              TextFormField(
                controller: _providerController,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: L.t('provider'),
                  hintText: L.t('provider_hint'),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? L.t('enter_provider')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${L.t('expected_amount')} (ETB)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null || amount <= 0 || amount > 100000000) {
                    return L.t('valid_amount');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referenceController,
                maxLength: 2048,
                decoration: InputDecoration(
                  labelText: L.t('transaction_reference_recommended'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: L.t('note_optional'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _addExpectedPayment,
                child:
                    Text(_saving ? L.t('saving') : L.t('add_expected_payment')),
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
        title: Text(L.t('payment_reconciliation')),
        actions: [
          IconButton(
            tooltip: L.t('refresh_reconciliation'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _reconciliation,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(L.t('reconciliation_load_fail')),
                    const SizedBox(height: 12),
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

          final data = snapshot.data!;
          final expected = (data['expected_payments'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          final unmatched = (data['unmatched_received'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(L.t('compare_payment_amounts_desc')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showForm = !_showForm),
                  icon: Icon(_showForm ? Icons.close : Icons.add),
                  label: Text(
                      _showForm ? L.t('cancel') : L.t('add_expected_payment')),
                ),
                if (_showForm) ...[
                  const SizedBox(height: 12),
                  _form(),
                ],
                const SizedBox(height: 20),
                Text(
                  '${L.t('expected_payments')} (${expected.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (expected.isEmpty)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(L.t('no_expected_payments_start')),
                    ),
                  )
                else
                  for (final item in expected) _expectedPaymentCard(item),
                const SizedBox(height: 16),
                Text(
                  '${L.t('unmatched_verified_receipts')} (${unmatched.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (unmatched.isEmpty)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(L.t('no_unmatched_verified_receipts')),
                    ),
                  )
                else
                  for (final transaction in unmatched)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(
                          '${transaction['provider'] ?? L.t('unknown_provider')}'
                          ' • ETB ${(transaction['amount'] as num).toStringAsFixed(2)}',
                        ),
                        subtitle: Text(
                          'Receipt #${transaction['id']}'
                          '${transaction['reference'] == null ? '' : ' • ${transaction['reference']}'}',
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
