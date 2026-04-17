import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';

class FriendRequestRecordsPage extends StatefulWidget {
  const FriendRequestRecordsPage({super.key});

  @override
  State<FriendRequestRecordsPage> createState() => _FriendRequestRecordsPageState();
}

class _FriendRequestRecordsPageState extends State<FriendRequestRecordsPage> {
  List<Map<String, dynamic>>? _records;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      final list = await context.read<ContactsProvider>().loadSentRequests();
      if (!mounted) return;
      setState(() {
        _records = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '加载失败'));
      setState(() => _loading = false);
    }
  }

  Widget _buildStatusLabel(int status) {
    switch (status) {
      case 0:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('等待验证', style: TextStyle(fontSize: 12, color: Colors.orange)),
        );
      case 1:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('已同意', style: TextStyle(fontSize: 12, color: Colors.green)),
        );
      case 2:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('已拒绝', style: TextStyle(fontSize: 12, color: Colors.red)),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '今天 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('添加记录'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_records == null || _records!.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('暂无添加记录', style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = _records![index];
                    final toUser = record['toUser'] as Map<String, dynamic>? ?? {};
                    final nickname = (toUser['nickname'] ?? '未知').toString();
                    final avatarUrl = toUser['avatarUrl']?.toString();
                    final status = record['status'] is int ? record['status'] as int : 0;
                    final createdAt = record['createdAt']?.toString();

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          UserAvatar(name: nickname, url: avatarUrl, size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nickname, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(_formatTime(createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          _buildStatusLabel(status),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
