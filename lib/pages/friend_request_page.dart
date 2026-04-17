import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/contacts_provider.dart';
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
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final req = requests[index];
              final fromUser = req['fromUser'] as Map<String, dynamic>? ?? {};
              final nickname = (fromUser['nickname'] ?? '未知').toString();
              final avatarUrl = fromUser['avatarUrl']?.toString();
              final requestId = req['requestId'] is int ? req['requestId'] as int : int.tryParse(req['requestId']?.toString() ?? '') ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                    if (req['status'] == 0)
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            await contacts.handleFriendRequest(requestId, 'accept');
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已接受')));
                          } catch (e) {
                            if (!context.mounted) return;
                            final message = ErrorMessage.from(e, fallback: '处理好友申请失败，请稍后重试');
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                          }
                        },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                        child: const Text('接受', style: TextStyle(fontSize: 13)),
                      )
                    else
                      Text(req['status'] == 1 ? '已接受' : '已拒绝', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
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
