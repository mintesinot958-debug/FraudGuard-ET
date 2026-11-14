import 'package:flutter/material.dart';
import '../l10n.dart';
import '../services/auth_store.dart';
import '../services/backend_api.dart';

class CommunityReportsScreen extends StatefulWidget {
  const CommunityReportsScreen({super.key});

  @override
  State<CommunityReportsScreen> createState() => _CommunityReportsScreenState();
}

class _CommunityReportsScreenState extends State<CommunityReportsScreen> {
  static const _categories = {
    'phishing': 'report_type_phishing',
    'fake_receipt': 'report_type_fake_receipt',
    'impersonation': 'report_type_impersonation',
    'other': 'report_type_other',
  };

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _indicatorController = TextEditingController();
  final _providerController = TextEditingController();

  late Future<List<Map<String, dynamic>>> _reports;
  Future<Map<String, dynamic>>? _trends;
  int _trendDays = 30;
  String _category = 'phishing';
  bool _showForm = false;
  bool _submitting = false;

  bool get _isAdmin => AuthStore.instance.isAdmin;

  String _categoryLabel(String category) =>
      L.t(_categories[category] ?? category);

  @override
  void initState() {
    super.initState();
    _reports = _load();
    if (_isAdmin) _trends = _loadTrends();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _indicatorController.dispose();
    _providerController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (_isAdmin) {
      return BackendApi.instance.communityReports(admin: true);
    }

    final results = await Future.wait([
      BackendApi.instance.communityReports(),
      BackendApi.instance.myCommunityReports(),
    ]);
    final myReports = results[1];
    final myReportIds = myReports.map((report) => report['id']).toSet();
    return [
      ...myReports.map((report) => {...report, '_is_mine': true}),
      ...results[0]
          .where((report) => !myReportIds.contains(report['id']))
          .map((report) => {...report, '_is_mine': false}),
    ];
  }

  Future<Map<String, dynamic>> _loadTrends() =>
      BackendApi.instance.communityReportTrends(days: _trendDays);

  Future<void> _refresh() async {
    setState(() {
      _reports = _load();
      if (_isAdmin) _trends = _loadTrends();
    });
    try {
      await Future.wait([
        _reports,
        if (_isAdmin) _trends!,
      ]);
    } catch (_) {
      // The list shows the error and a Retry button.
    }
  }

  Widget _trendCounts(
    String title,
    List<dynamic> entries,
    String key,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text(L.t('no_reviewed_reports_period'))
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          key == 'category'
                              ? _categoryLabel(entry[key].toString())
                              : entry[key].toString(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        entry['count'].toString(),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _reportTrends() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              L.t('reviewed_report_trends'),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(L.t('reviewed_report_note')),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 7, label: Text(L.t('days_7'))),
                ButtonSegment(value: 30, label: Text(L.t('days_30'))),
                ButtonSegment(value: 90, label: Text(L.t('days_90'))),
                ButtonSegment(value: 0, label: Text(L.t('all'))),
              ],
              selected: {_trendDays},
              onSelectionChanged: (selection) {
                setState(() {
                  _trendDays = selection.first;
                  _trends = _loadTrends();
                });
              },
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: _trends,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L.t('trend_load_fail')),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _trends = _loadTrends()),
                        icon: const Icon(Icons.refresh),
                        label: Text(L.t('retry')),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!;
                final period = data['days'] as int;
                final periodLabel = period == 0
                    ? L.t('all_time')
                    : '${L.t('last_days')} $period ${L.lang == 'am' ? 'ቀናት' : 'days'}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${data['total_reviewed']} ${L.t('reports_reviewed')} ($periodLabel)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            '${L.t('published')}: ${data['published']}',
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${L.t('rejected')}: ${data['rejected']}',
                          ),
                        ),
                      ],
                    ),
                    _trendCounts(
                      L.t('by_scam_type'),
                      data['by_category'] as List<dynamic>,
                      'category',
                    ),
                    _trendCounts(
                      L.t('by_provider'),
                      data['by_provider'] as List<dynamic>,
                      'provider',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await BackendApi.instance.submitCommunityReport(
        category: _category,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        indicator: _indicatorController.text.trim(),
        provider: _providerController.text.trim(),
      );
      _titleController.clear();
      _descriptionController.clear();
      _indicatorController.clear();
      _providerController.clear();
      setState(() => _showForm = false);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L.t('report_submit_success')),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${L.t('report_submit_fail')}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _moderate(int id, String status) async {
    try {
      await BackendApi.instance.updateCommunityReport(id, status);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${L.t('report_update_fail')}: $error')),
        );
      }
    }
  }

  Future<void> _deleteReport(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('delete_report_title')),
        content: Text(L.t('delete_report_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              L.t('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;

    try {
      await BackendApi.instance.deleteCommunityReport(id);
      if (!mounted) return;
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t('report_delete_success'))),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${L.t('report_delete_fail')}: $error')),
        );
      }
    }
  }

  Widget _reportForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L.t('share_fraud_incident'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(L.t('report_safety_note')),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(labelText: L.t('report_type')),
                items: [
                  for (final entry in _categories.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(L.t(entry.value)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: L.t('title'),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 3
                    ? L.t('title_min_length')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLength: 1500,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: L.t('what_happened'),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 10
                    ? L.t('description_min_length')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _indicatorController,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: L.t('indicator_optional'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _providerController,
                maxLength: 50,
                decoration: InputDecoration(
                  labelText: L.t('provider_optional'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(L.t('submit_for_review')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final status = report['status'] as String;
    final id = (report['id'] as num).toInt();
    final isMine = report['_is_mine'] == true;
    final createdAt = DateTime.tryParse(report['created_at'] as String);
    final date = createdAt == null
        ? ''
        : '${createdAt.toLocal().year}-${createdAt.toLocal().month.toString().padLeft(2, '0')}-${createdAt.toLocal().day.toString().padLeft(2, '0')}';
    final statusLabel = switch (status) {
      'pending' => L.t('under_review'),
      'published' => L.t('published'),
      'rejected' => L.t('rejected'),
      _ => status,
    };

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
                    report['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isAdmin)
                  IconButton(
                    onPressed: () => _deleteReport(id),
                    tooltip: L.t('delete_report'),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                  ),
                if (_isAdmin || isMine)
                  Chip(
                    label: Text(statusLabel),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_categoryLabel(report['category'] as String)} · $date',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(report['description'] as String),
            if (report['indicator'] != null &&
                (report['indicator'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText('${L.t('indicator')}: ${report['indicator']}'),
            ],
            if (report['provider'] != null &&
                (report['provider'] as String).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${L.t('provider')}: ${report['provider']}'),
            ],
            if (_isAdmin && status == 'pending') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _moderate(id, 'published'),
                    child: Text(L.t('publish')),
                  ),
                  OutlinedButton(
                    onPressed: () => _moderate(id, 'rejected'),
                    child: Text(L.t('reject')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _reports,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L.t('community_load_fail')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _refresh,
                  child: Text(L.t('retry')),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final reports = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _isAdmin
                    ? L.t('community_report_review')
                    : L.t('community_reports'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isAdmin
                    ? L.t('review_reports_note')
                    : L.t('community_reports_note'),
              ),
              if (_isAdmin) ...[
                const SizedBox(height: 16),
                _reportTrends(),
              ],
              if (!_isAdmin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showForm = !_showForm),
                  icon:
                      Icon(_showForm ? Icons.close : Icons.add_alert_outlined),
                  label: Text(
                    L.t(_showForm ? 'cancel_report' : 'report_fraud'),
                  ),
                ),
                if (_showForm) ...[
                  const SizedBox(height: 12),
                  _reportForm(),
                ],
              ],
              const SizedBox(height: 16),
              if (!_isAdmin) ...[
                Text(
                  L.t('my_reports'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (final report in reports.where(
                  (item) => item['_is_mine'] == true,
                ))
                  _reportCard(report),
                if (!reports.any((item) => item['_is_mine'] == true))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(L.t('no_my_reports')),
                  ),
                const SizedBox(height: 12),
                Text(
                  L.t('published_community_reports'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
              ],
              if (reports.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      _isAdmin
                          ? L.t('no_reports_to_review')
                          : L.t('no_community_reports'),
                    ),
                  ),
                )
              else if (_isAdmin)
                for (final report in reports) _reportCard(report)
              else if (!reports.any(
                (item) => item['_is_mine'] != true,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text(L.t('no_published_community_reports'))),
                )
              else
                for (final report in reports.where(
                  (item) => item['_is_mine'] != true,
                ))
                  _reportCard(report),
            ],
          ),
        );
      },
    );
  }
}
