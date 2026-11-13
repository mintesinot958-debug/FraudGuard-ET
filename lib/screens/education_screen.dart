import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n.dart';
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
                return Center(
                    child: Text('${L.t('error_prefix')}: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 100),
                    const Center(
                        child: Icon(Icons.video_library_outlined,
                            size: 64, color: Colors.grey)),
                    const SizedBox(height: 16),
                    Center(child: Text(L.t('no_education_content'))),
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
                          label: Text(L.t('post_education_content')),
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
                  final postType = item['post_type'] as String? ?? 'video';
                  final imageUrl = item['image_url'] as String?;
                  final videoUrl = item['video_url'] as String? ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (postType == 'image' && imageUrl != null)
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                            child: Image.network(
                              imageUrl.startsWith('http')
                                  ? imageUrl
                                  : '${BackendApi.baseUrl}$imageUrl',
                              height: 220,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                height: 180,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          )
                        else if (postType == 'video')
                          Container(
                            height: 180,
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            child: const Icon(Icons.play_circle_outline,
                                size: 64, color: Colors.white),
                          )
                        else
                          Container(
                            height: 100,
                            color: theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.article_outlined,
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
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
                              if (postType != 'text')
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    postType == 'image'
                                        ? L.t('image_post')
                                        : L.t('video'),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
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
                                              '${L.t('ai_safety_tip')}: ${item['ai_summary']}',
                                              style: const TextStyle(
                                                  fontSize: 12))),
                                    ],
                                  ),
                                ),
                              ],
                              if (postType == 'video' &&
                                  videoUrl.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => launchUrl(Uri.parse(
                                    videoUrl.startsWith('http')
                                        ? videoUrl
                                        : '${BackendApi.baseUrl}$videoUrl',
                                  )),
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(L.t('watch_video')),
                                ),
                              ],
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
              icon: const Icon(Icons.add),
              label: Text(L.t('create_post')),
              backgroundColor: Colors.orange,
            ),
          ),
      ],
    );
  }
}
