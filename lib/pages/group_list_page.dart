import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/pages/chat_page.dart';

class GroupListPage extends StatefulWidget {
  const GroupListPage({super.key});

  @override
  State<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends State<GroupListPage> {
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _loading = true);
    final chat = context.read<ChatProvider>();
    if (chat.conversations.isEmpty) await chat.loadConversations();
    if (!mounted) return;
    setState(() {
      _groups = chat.conversations.where((c) => c['type'] == 2).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text('群组', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadGroups,
                  child: ListView.separated(
                    itemCount: _groups.length,
                    separatorBuilder: (_, _) => const Divider(height: 0.5, indent: 72, color: AppColors.divider),
                    itemBuilder: (_, i) => _buildGroupTile(_groups[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('暂无群组', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group) {
    final name = group['name']?.toString() ?? '群聊';
    final memberCount = group['memberCount'] ?? 0;
    final convId = group['conversationId']?.toString() ?? '';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(
            conversationId: convId,
            title: name,
          )));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.people_alt_rounded, size: 24, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text('$memberCount 名成员', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}
