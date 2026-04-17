import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/widgets/user_avatar.dart';

class StarredFriendsPage extends StatelessWidget {
  const StarredFriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text('星标好友', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<ContactsProvider>(
        builder: (context, contacts, _) {
          final starred = contacts.friends.where((f) => f['isStarred'] == true || f['isStarred'] == 1).toList();

          if (starred.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_outline_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text('暂无星标好友', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('在好友详情页可设置星标', style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: starred.length,
            separatorBuilder: (_, _) => const Divider(height: 0.5, indent: 72, color: AppColors.divider),
            itemBuilder: (_, i) {
              final f = starred[i];
              final name = (f['remark'] ?? f['nickname'] ?? '').toString();
              return Material(
                color: Colors.white,
                child: ListTile(
                  leading: UserAvatar(name: name, url: f['avatarUrl']?.toString(), size: 42, radius: 8),
                  title: Text(name, style: const TextStyle(fontSize: 15)),
                  trailing: const Icon(Icons.star_rounded, size: 20, color: Color(0xFFFFC107)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
