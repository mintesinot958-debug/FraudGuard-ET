import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
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
  File? _videoFile;

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
          SnackBar(content: Text('Failed to load data: $e')),
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

  Future<void> _viewVideo(String url) async {
    final uri = url.startsWith('http')
        ? Uri.parse(url)
        : Uri.parse('${BackendApi.baseUrl}$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this video.')),
        );
      }
    }
  }

  Future<void> _deleteVideo(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Video?'),
        content: const Text(
            'Are you sure you want to remove this educational video?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
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
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _addVideo() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter a title')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Video published successfully!'),
            backgroundColor: Colors.green));
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add video: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Panel'),
          actions: [
            IconButton(onPressed: _refreshData, icon: const Icon(Icons.refresh))
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Users'),
              Tab(icon: Icon(Icons.video_library), text: 'Videos'),
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
                        title: Text(user['email'] ?? 'User'),
                        subtitle: Text('Role: ${user['role']}'),
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
                        const Text('Post New Educational Video',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        TextField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                                labelText: 'Title',
                                prefixIcon: Icon(Icons.title))),
                        const SizedBox(height: 12),
                        TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                                labelText: 'Video URL',
                                prefixIcon: Icon(Icons.link))),
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('OR'))),
                        OutlinedButton.icon(
                          onPressed: _pickVideo,
                          icon: Icon(
                              _videoFile == null
                                  ? Icons.upload_file
                                  : Icons.check_circle,
                              color: _videoFile != null ? Colors.green : null),
                          label: Text(_videoFile == null
                              ? 'Upload MP4 from Phone'
                              : 'File Selected'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                            controller: _descController,
                            decoration: const InputDecoration(
                                labelText: 'Description',
                                prefixIcon: Icon(Icons.description))),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(
                              labelText: 'Category',
                              prefixIcon: Icon(Icons.category)),
                          items: ['general', 'cbe', 'telebirr', 'security']
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(c.toUpperCase())))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedCategory = v);
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                            onPressed: _addVideo,
                            child: const Text('PUBLISH WITH AI SUMMARY')),
                        const Divider(height: 60),
                        const Text('Manage Existing Videos',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        if (_videos.isEmpty)
                          const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('No videos published yet.')))
                        else
                          for (final video in _videos)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(video['title']),
                                subtitle: Text(
                                    video['category'].toString().toUpperCase()),
                                leading: IconButton(
                                  icon: const Icon(Icons.play_circle_outline,
                                      color: Colors.blue),
                                  onPressed: () =>
                                      _viewVideo(video['video_url']),
                                  tooltip: 'Watch/Preview',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _deleteVideo(video['id']),
                                  tooltip: 'Delete Video',
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
