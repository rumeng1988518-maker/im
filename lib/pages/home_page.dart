import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/pages/conversation_list_page.dart';
import 'package:im_client/pages/contacts_page.dart';
import 'package:im_client/pages/moments_page.dart';
import 'package:im_client/pages/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final _pages = const [
    ConversationListPage(),
    ContactsPage(),
    MomentsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Consumer2<ChatProvider, ContactsProvider>(
        builder: (context, chat, contacts, _) {
          final totalUnread = chat.conversations.fold<int>(
            0,
            (sum, c) => sum + ((c['unreadCount'] as num?)?.toInt() ?? 0),
          );
          final pendingFriends = contacts.pendingRequestCount;
          return Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE5E5E5), width: 0.5)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (i) => setState(() => _currentIndex = i),
                type: BottomNavigationBarType.fixed,
                backgroundColor: const Color(0xFFF7F7F7),
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.textSecondary,
                selectedFontSize: 11,
                unselectedFontSize: 11,
                iconSize: 24,
                elevation: 0,
                enableFeedback: false,
                items: [
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: totalUnread > 0,
                    label: Text(totalUnread > 99 ? '99+' : '$totalUnread', style: const TextStyle(fontSize: 10)),
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: totalUnread > 0,
                    label: Text(totalUnread > 99 ? '99+' : '$totalUnread', style: const TextStyle(fontSize: 10)),
                    child: const Icon(Icons.chat_bubble),
                  ),
                  label: '内部通',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: pendingFriends > 0,
                    label: Text(pendingFriends > 99 ? '99+' : '$pendingFriends', style: const TextStyle(fontSize: 10)),
                    child: const Icon(Icons.contacts_outlined),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: pendingFriends > 0,
                    label: Text(pendingFriends > 99 ? '99+' : '$pendingFriends', style: const TextStyle(fontSize: 10)),
                    child: const Icon(Icons.contacts),
                  ),
                  label: '通讯录',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.explore_outlined),
                  activeIcon: Icon(Icons.explore),
                  label: '动态',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: '我',
                ),
              ],
              ),
            ),
          );
        },
      ),
    );
  }
}
