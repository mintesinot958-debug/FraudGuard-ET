import 'package:flutter/material.dart';
import '../l10n.dart';
import '../services/auth_store.dart';
import '../services/backend_api.dart';
import '../widgets/risk_flag.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _statuses = [
    'Open',
    'Investigating',
    'Confirmed Fraud',
    'False Positive',
  ];

  late Future<List<Map<String, dynamic>>> _history;

  @override
  void initState() {
    super.initState();
    _history = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => BackendApi.instance.history(
        admin: AuthStore.instance.isAdmin,
      );

  Future<void> _refresh() async {
    setState(() => _history = _load());
    try {
      await _history;
    } catch (_) {
      // The FutureBuilder shows the error and a Retry button.
    }
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    try {
      await BackendApi.instance
          .updateAlert((item['id'] as num).toInt(), status);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the alert.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = AuthStore.instance.isAdmin;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    L.t('load_fail'),
                    style: theme.textTheme.titleMedium,
                  ),
                  Text('${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _refresh, child: Text(L.t('retry'))),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data!;
        final types = <String, int>{};
        int highRiskCount = 0;

        for (final item in items) {
          final type = item['kind'] == 'receipt' ? L.t('receipt') : L.t('transfer');
          types[type] = (types[type] ?? 0) + 1;
          if ((item['risk_score'] as num) >= 60) {
            highRiskCount++;
          }
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                isAdmin ? L.t('admin_dash') : L.t('tab_dash'),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              // Summary Cards
              Row(
                children: [
                  _SummaryCard(
                    label: L.t('total_checks'),
                    value: items.length.toString(),
                    icon: Icons.bar_chart,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  _SummaryCard(
                    label: L.t('high_risk'),
                    value: highRiskCount.toString(),
                    icon: Icons.warning_amber_rounded,
                    color: Colors.red,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                L.t('fraud_by_type'),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (types.isEmpty)
                 Text(L.t('no_transactions'))
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (final entry in types.entries) ...[
                          Row(
                            children: [
                              Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                              const Spacer(),
                              Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: items.isEmpty ? 0 : entry.value / items.length,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          if (entry.key != types.keys.last) const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    L.t('alerts'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton(onPressed: _refresh, child: Text(L.t('refresh'))),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                 Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      L.t('no_transactions'),
                      style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                    ),
                  ),
                )
              else
                for (final item in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: RiskFlag(
                        score: (item['risk_score'] as num).toInt(),
                      ),
                      title: Text(
                        '${item['kind'] == 'receipt' ? L.t('receipt') : L.t('transfer')} • #${item['id']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (item['provider'] != null) item['provider'],
                            if (item['reference'] != null) item['reference'],
                            '${L.t('status')}: ${item['review_status']}',
                          ].join(' • '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      trailing: isAdmin
                          ? PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (s) => _setStatus(item, s),
                              itemBuilder: (context) => _statuses
                                  .map((s) => PopupMenuItem(value: s, child: Text(s)))
                                  .toList(),
                            )
                          : const Icon(Icons.chevron_right, size: 16),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
