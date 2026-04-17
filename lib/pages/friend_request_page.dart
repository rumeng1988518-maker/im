import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';

class FriendRequestPage extends StatefulWidget {
  const FriendRequestPage({super.key});

  @override
  State<FriendRequestPage> createState() => _FriendRequestPageState();
}

class _FriendRequestPageState extends State<FriendRequestPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ContactsProvider>();
      provider.clearPendingCount();
      provider.loadFriendRequests();
    });
  }

  Future<void> _handleRequest(ContactsProvider contacts, int requestId, String action) async {
    try {
      await contacts.handleFriendRequest(requestId, action);
      if (!mounted) return;
      AppToast.show(context, action == 'accept' ? '已同意' : '已拒绝');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '处理失败，请稍后重试'));
    }
  }

  Widget _buildActionArea(Map<String, dynamic> req, ContactsProvider contacts) {
    final status = req['status'];
    final requestId = req['requestId'] is int
        ? req['requestId'] as int
        : int.tryParse(req['requestId']?.toString() ?? '') ?? 0;

    if (status == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: () => _handleRequest(contacts, requestId, 'reject'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: const Text('拒绝', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _handleRequest(contacts, requestId, 'accept'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('同意', style: TextStyle(fontSize: 13)),
          ),
        ],
      );
    }

    if (status == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('已同意', style: TextStyle(fontSize: 12, color: Colors.green)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('已拒绝', style: TextStyle(fontSize: 12, color: Colors.red)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('新的朋友'),
      ),
      body: Consumer<ContactsProvider>(
        builder: (context, contacts, _) {
          final requests = contacts.friendRequests;
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('暂无好友申请', style: TextStyle(color: Colors.grey[400])),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final req = requests[index];
              final fromUser = req['fromUser'] as Map<String, dynamic>? ?? {};
              final nickname = (fromUser['nickname'] ?? '未知').toString();
              final avatarUrl = fromUser['avatarUrl']?.toString();
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
                          Text(nickname, style: const TextStyle(fontWeight: FontWeight.w500)),
                          if (req['message'] != null && req['message'].toString().isNotEmpty)
                            Text(req['message'].toString(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildActionArea(req, contacts),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
