import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n.dart';
import '../services/backend_api.dart';
import 'package:intl/intl.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _videos = [];

  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _descController = TextEditingController();

  String _selectedCategory = 'general';
  String _selectedPostType = 'video';
  File? _videoFile;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        BackendApi.instance.listUsers(),
        BackendApi.instance.listEducation(),
      ]);
      setState(() {
        _users = results[0];
        _videos = results[1];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${L.t('admin_load_fail')}: $e')),
        );
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _videoFile = File(file.path);
        _urlController.clear();
      });
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file != null) {
      setState(() => _imageFile = File(file.path));
    }
  }

  Future<void> _viewVideo(String url) async {
    final uri = url.startsWith('http')
        ? Uri.parse(url)
        : Uri.parse('${BackendApi.baseUrl}$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t('open_video_fail'))),
        );
      }
    }
  }

  Future<void> _deleteVideo(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t('delete_education_title')),
        content: Text(L.t('delete_education_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L.t('delete'),
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await BackendApi.instance.deleteEducation(id);
      _refreshData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${L.t('delete_fail')}: $e')));
      }
    }
  }

  Future<void> _editEducation(Map<String, dynamic> item) async {
    final titleController =
        TextEditingController(text: item['title'] as String? ?? '');
    final descriptionController =
        TextEditingController(text: item['description'] as String? ?? '');
    final categoryController =
        TextEditingController(text: item['category'] as String? ?? 'general');
    final videoUrlController =
        TextEditingController(text: item['video_url'] as String? ?? '');
    final isVideo = (item['post_type'] as String? ?? 'video') == 'video';

    try {
      final changes = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(L.t('edit_post')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: L.t('title')),
                ),
                if (isVideo)
                  TextField(
                    controller: videoUrlController,
                    decoration: InputDecoration(labelText: L.t('video_url')),
                  ),
                TextField(
                  controller: descriptionController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(labelText: L.t('description')),
                ),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(labelText: L.t('category')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'title': titleController.text.trim(),
                'description': descriptionController.text.trim(),
                'category': categoryController.text.trim(),
                if (isVideo) 'video_url': videoUrlController.text.trim(),
              }),
              child: Text(L.t('save')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (changes == null) return;
      if (changes['title']!.isEmpty || changes['category']!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t('enter_title'))),
        );
        return;
      }

      await BackendApi.instance.updateEducation(
        id: item['id'] as int,
        title: changes['title']!,
        description: changes['description']!,
        category: changes['category']!,
        videoUrl: changes['video_url'],
      );
      if (!mounted) return;
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t('education_post_updated'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${L.t('education_post_update_fail')}: $error')),
        );
      }
    } finally {
      titleController.dispose();
      descriptionController.dispose();
      categoryController.dispose();
      videoUrlController.dispose();
    }
  }

  Future<void> _addVideo() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(L.t('enter_title'))));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await BackendApi.instance.addEducation(
        title: _titleController.text.trim(),
        videoUrl:
            _urlController.text.isEmpty ? null : _urlController.text.trim(),
        videoFile: _videoFile,
        description: _descController.text.trim(),
        category: _selectedCategory,
      );
      if (mounted) {
        Navigator.pop(context); // Close loading
        _titleController.clear();
        _urlController.clear();
        _descController.clear();
        setState(() => _videoFile = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.t('video_published')),
            backgroundColor: Colors.green));
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${L.t('video_publish_fail')}: $e')));
      }
    }
  }

  Future<void> _publishEducation() async {
    if (_selectedPostType == 'video') {
      if (_videoFile == null && _urlController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t('choose_video_or_url'))),
        );
        return;
      }
      await _addVideo();
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t('enter_title'))),
      );
      return;
    }
    if (_selectedPostType == 'text' && _descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t('enter_education_text'))),
      );
      return;
    }
    if (_selectedPostType == 'image' && _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t('choose_image'))),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await BackendApi.instance.addEducationPost(
        postType: _selectedPostType,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        category: _selectedCategory,
        imageFile: _imageFile,
      );
      if (mounted) {
        Navigator.pop(context);
        _titleController.clear();
        _descController.clear();
        setState(() {
          _imageFile = null;
          _selectedPostType = 'video';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L.t('education_post_published')),
            backgroundColor: Colors.green,
          ),
        );
        _refreshData();
      }
    } catch (error) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${L.t('education_post_publish_fail')}: $error')),
        );
      }
    }
  }

  Widget _educationPreview(Map<String, dynamic> item) {
    final postType = item['post_type'] as String? ?? 'video';
    if (postType == 'image' && item['image_url'] != null) {
      final url = item['image_url'] as String;
      return Image.network(
        url.startsWith('http') ? url : '${BackendApi.baseUrl}$url',
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      );
    }
    return Icon(
      postType == 'video' ? Icons.play_circle_outline : Icons.article_outlined,
      color: Colors.blue,
    );
  }

  String _categoryLabel(String category) {
    if (category == 'general' || category == 'security') {
      return L.t(category);
    }
    return category.toUpperCase();
  }

  String _postTypeLabel(String postType) => switch (postType) {
        'text' => L.t('text_only'),
        'image' => L.t('image_based'),
        _ => L.t('video'),
      };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(L.t('admin_panel')),
          actions: [
            IconButton(onPressed: _refreshData, icon: const Icon(Icons.refresh))
          ],
          bottom: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: L.t('users')),
              Tab(icon: Icon(Icons.school_outlined), text: L.t('education')),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  // USERS TAB
                  ListView.builder(
                    itemCount: _users.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(user['email'] ?? L.t('user_role')),
                        subtitle: Text(
                          '${L.t('role')}: ${user['role'] == 'admin' ? L.t('admin_role') : L.t('user_role')}',
                        ),
                        trailing: Text(
                            DateFormat.yMMMd()
                                .format(DateTime.parse(user['created_at'])),
                            style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),

                  // VIDEOS TAB
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(L.t('create_education_content'),
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPostType,
                          decoration: InputDecoration(
                            labelText: L.t('post_type'),
                            prefixIcon: Icon(Icons.article_outlined),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'video',
                              child: Text(L.t('video')),
                            ),
                            DropdownMenuItem(
                              value: 'text',
                              child: Text(L.t('text_only')),
                            ),
                            DropdownMenuItem(
                              value: 'image',
                              child: Text(L.t('image_based')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedPostType = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                            controller: _titleController,
                            decoration: InputDecoration(
                                labelText: L.t('title'),
                                prefixIcon: Icon(Icons.title))),
                        if (_selectedPostType == 'video') ...[
                          const SizedBox(height: 12),
                          TextField(
                              controller: _urlController,
                              decoration: InputDecoration(
                                  labelText: L.t('video_url'),
                                  prefixIcon: Icon(Icons.link))),
                          Center(
                              child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(L.t('or')))),
                          OutlinedButton.icon(
                            onPressed: _pickVideo,
                            icon: Icon(
                                _videoFile == null
                                    ? Icons.upload_file
                                    : Icons.check_circle,
                                color:
                                    _videoFile != null ? Colors.green : null),
                            label: Text(_videoFile == null
                                ? L.t('upload_mp4_phone')
                                : L.t('file_selected')),
                          ),
                        ],
                        if (_selectedPostType == 'image') ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: Icon(
                              _imageFile == null
                                  ? Icons.image_outlined
                                  : Icons.check_circle,
                              color: _imageFile == null ? null : Colors.green,
                            ),
                            label: Text(
                              _imageFile == null
                                  ? L.t('choose_image')
                                  : L.t('image_selected'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_selectedPostType != 'video')
                          TextField(
                            controller: _descController,
                            minLines: 3,
                            maxLines: 8,
                            decoration: InputDecoration(
                              labelText: _selectedPostType == 'text'
                                  ? L.t('education_text')
                                  : L.t('caption_optional'),
                              alignLabelWithHint: true,
                              prefixIcon: const Icon(Icons.description),
                            ),
                          )
                        else
                          TextField(
                              controller: _descController,
                              decoration: InputDecoration(
                                  labelText: L.t('description'),
                                  prefixIcon: Icon(Icons.description))),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          decoration: InputDecoration(
                              labelText: L.t('category'),
                              prefixIcon: Icon(Icons.category)),
                          items: ['general', 'cbe', 'telebirr', 'security']
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(_categoryLabel(c))))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedCategory = v);
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _publishEducation,
                          child: Text(
                            _selectedPostType == 'video'
                                ? L.t('publish_video_ai')
                                : L.t('publish_post'),
                          ),
                        ),
                        const Divider(height: 60),
                        Text(L.t('manage_education'),
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (_videos.isEmpty)
                          Center(
                              child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(L.t('no_education_published'))))
                        else
                          for (final video in _videos)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(video['title']),
                                subtitle: Text(
                                  '${_postTypeLabel(video['post_type'] as String? ?? 'video')} • ${_categoryLabel(video['category'].toString())}',
                                ),
                                leading: _educationPreview(video),
                                onTap: (video['post_type'] as String? ??
                                                'video') ==
                                            'video' &&
                                        (video['video_url'] as String? ?? '')
                                            .isNotEmpty
                                    ? () => _viewVideo(video['video_url'])
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editEducation(video),
                                      tooltip: L.t('edit_post'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _deleteVideo(video['id']),
                                      tooltip: L.t('delete_post'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
