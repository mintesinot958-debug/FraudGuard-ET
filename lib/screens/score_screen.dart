import 'package:flutter/material.dart' hide Action;
import '../l10n.dart';
import '../services/backend_api.dart';
import '../widgets/result_card.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});
  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  final amt = TextEditingController(text: '5000');
  final hour = TextEditingController(text: DateTime.now().hour.toString());
  final age = TextEditingController(text: '120');
  final n24 = TextEditingController(text: '1');
  bool newR = false, sim = false;
  bool busy = false;
  Map<String, dynamic>? res;
  String? error;

  @override
  void dispose() {
    amt.dispose();
    hour.dispose();
    age.dispose();
    n24.dispose();
    super.dispose();
  }

  Widget _inputLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 16),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
    ),
  );

  Future<void> _run() async {
    final amount = double.tryParse(amt.text.trim().replaceAll(',', ''));
    final transactionHour = int.tryParse(hour.text);
    final accountAge = int.tryParse(age.text);
    final transactionCount = int.tryParse(n24.text);
    
    if (amount == null || transactionHour == null || accountAge == null || transactionCount == null) {
      setState(() => error = 'Please enter valid numbers');
      return;
    }

    if (amount <= 0 || transactionHour < 0 || transactionHour > 23 ||
        accountAge < 0 || transactionCount < 0) {
      setState(() => error = 'Amount must be above 0 and hour must be 0-23.');
      return;
    }

    setState(() {
      error = null;
      busy = true;
    });

    try {
      final result = await BackendApi.instance.scoreTransfer(
        amount: amount,
        hour: transactionHour,
        accountAgeDays: accountAge,
        transactions24h: transactionCount,
        newRecipient: newR,
        simChanged: sim,
      );
      if (mounted) setState(() => res = result);
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (e) {
      if (mounted) setState(() => error = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = res;
    final riskScore = r == null ? 0 : (r['risk_score'] as num).toInt();
    
    final (label, color) = r == null
        ? ('', Colors.grey)
        : switch (r['risk_level']) {
            'low' => (L.t('low'), Colors.green),
            'medium' => (L.t('medium'), Colors.orange),
            _ => (L.t('high'), Colors.red),
          };

    final actionLabel = switch (r?['action']) {
      'allow' => L.t('allow'),
      'step_up' => L.t('stepup'),
      'hold' => L.t('hold'),
      'block' => L.t('block'),
      _ => '',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Transfer Risk Scorer',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Analyze transfer parameters to determine risk level and suggested action.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _inputLabel(L.t('amount')),
                  TextField(
                    controller: amt,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(prefixText: 'ETB ', hintText: '0.00'),
                  ),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _inputLabel(L.t('hour')),
                            TextField(
                              controller: hour,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '0-23'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _inputLabel(L.t('tx24')),
                            TextField(
                              controller: n24,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: 'Count'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  _inputLabel(L.t('acct_age')),
                  TextField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(suffixText: 'days'),
                  ),
                  
                  const SizedBox(height: 20),
                  const Divider(),
                  
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(L.t('new_rcpt')),
                    value: newR,
                    onChanged: (v) => setState(() => newR = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(L.t('sim_change')),
                    value: sim,
                    onChanged: (v) => setState(() => sim = v),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy ? null : _run,
            icon: busy 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.security),
            label: Text(L.t('check').toUpperCase()),
          ),
          
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
            ),
            
          const SizedBox(height: 32),
          
          if (r != null)
            ResultCard(
              title: '$label → $actionLabel'.toUpperCase(),
              color: color,
              score: riskScore,
              reasons: (r['reasons'] as List<dynamic>).map((e) => e.toString()).toList(),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
