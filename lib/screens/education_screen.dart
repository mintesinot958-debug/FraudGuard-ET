import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/backend_api.dart';
import '../services/auth_store.dart';
import 'admin_management_screen.dart';

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  late Future<List<Map<String, dynamic>>> _content;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _content = BackendApi.instance.listEducation();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = AuthStore.instance.isAdmin;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _content,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 100),
                    const Center(
                        child: Icon(Icons.video_library_outlined,
                            size: 64, color: Colors.grey)),
                    const SizedBox(height: 16),
                    const Center(
                        child: Text('No educational content available yet.')),
                    if (isAdmin)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AdminManagementScreen()),
                          ).then((_) => _refresh()),
                          icon: const Icon(Icons.add),
                          label: const Text('Post Your First Video'),
                        ),
                      ),
                  ],
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final item = snapshot.data![index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 180,
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          child: const Icon(Icons.play_circle_outline,
                              size: 64, color: Colors.white),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['title'],
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(item['description'],
                                  style: theme.textTheme.bodyMedium),
                              if (item['ai_summary'] != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.green
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.auto_awesome,
                                          size: 16, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Expanded(
                                          child: Text(
                                              'AI Safety Tip: ${item['ai_summary']}',
                                              style: const TextStyle(
                                                  fontSize: 12))),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => launchUrl(Uri.parse(item[
                                            'video_url']
                                        .startsWith('http')
                                    ? item['video_url']
                                    : '${BackendApi.baseUrl}${item['video_url']}')),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('WATCH VIDEO'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (isAdmin)
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminManagementScreen()),
              ).then((_) => _refresh()),
              icon: const Icon(Icons.video_call),
              label: const Text('Post Video'),
              backgroundColor: Colors.orange,
            ),
          ),
      ],
    );
  }
}
