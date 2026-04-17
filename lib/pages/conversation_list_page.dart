import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/pages/add_friend_page.dart';
import 'package:im_client/pages/chat_page.dart';
import 'package:im_client/pages/create_group_page.dart';
import 'package:im_client/pages/scan_add_friend_page.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/utils/time_utils.dart';
import 'package:im_client/widgets/user_avatar.dart';

class ConversationListPage extends StatefulWidget {
  const ConversationListPage({super.key});

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _searching = false;
  List<Map<String, dynamic>> _searchMatches = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadConversations();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  PopupMenuItem<String> _buildPopupItem(IconData icon, String label, String value) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final keyword = value.trim();

    if (keyword.isEmpty) {
      setState(() {
        _searching = false;
        _searchMatches = [];
      });
      return;
    }

    setState(() {
      _searching = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      await _runSearch(keyword);
    });
  }

  Future<void> _runSearch(String keyword) async {
    try {
      final result = await context.read<ChatProvider>().searchConversationEntries(keyword);
      if (!mounted) return;
      if (_searchController.text.trim() != keyword) return;
      setState(() {
        _searchMatches = result;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = ErrorMessage.from(e, fallback: '搜索失败，请稍后重试');
      AppToast.show(context, message);
      if (_searchController.text.trim() == keyword) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  Future<void> _refreshSearchResults() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    await _runSearch(keyword);
  }

  Future<void> _handleQuickAction(String action) async {
    if (action == 'create_group') {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(builder: (_) => const CreateGroupPage()),
      );
      if (!mounted || result == null) return;
      final convId = result['conversationId']?.toString();
      if (convId == null) return;
      final title = result['name']?.toString() ?? '群聊';
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatPage(conversationId: convId, title: title)),
      );
      return;
    }

    if (action == 'add_friend') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddFriendPage()));
      return;
    }

    if (action == 'scan_add_friend') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanAddFriendPage()));
    }
  }

  Future<void> _togglePin(Map<String, dynamic> conv, ChatProvider chat) async {
    final convId = conv['conversationId']?.toString();
    if (convId == null) return;
    final isPinned = conv['isPinned'] == true;
    try {
      await chat.updateConversationSettings(convId, isPinned: !isPinned);
      if (!mounted) return;
      AppToast.show(context, isPinned ? '已取消置顶' : '已置顶');
      await _refreshSearchResults();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败，请稍后重试'));
    }
  }

  Future<void> _deleteConversation(Map<String, dynamic> conv, ChatProvider chat) async {
    final convId = conv['conversationId']?.toString();
    if (convId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('删除后会话将从列表隐藏，后续有新消息时会再次出现。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await chat.deleteConversation(convId);
      if (!mounted) return;
      setState(() {
        _searchMatches.removeWhere((m) => m['conversation']?['conversationId']?.toString() == convId);
      });
      AppToast.show(context, '会话已删除');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '删除失败，请稍后重试'));
    }
  }

  Future<void> _refreshList() async {
    await context.read<ChatProvider>().loadConversations();
    await _refreshSearchResults();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E5E5)),
        ),
        title: Consumer<ChatProvider>(
          builder: (context, chat, _) {
            final totalUnread = chat.conversations.fold<int>(
              0,
              (sum, c) => sum + ((c['unreadCount'] as num?)?.toInt() ?? 0),
            );
            return Text(
              totalUnread > 0 ? '内部通($totalUnread)' : '内部通(在线)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add, size: 24),
            color: const Color(0xFF4A4A4A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            onSelected: _handleQuickAction,
            itemBuilder: (_) => [
              _buildPopupItem(Icons.chat_bubble_outline, '发起群聊', 'create_group'),
              _buildPopupItem(Icons.person_add_alt_outlined, '添加朋友', 'add_friend'),
              _buildPopupItem(Icons.qr_code_scanner, '扫一扫添加好友', 'scan_add_friend'),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEDEDED),
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: '搜索',
                  hintStyle: TextStyle(color: AppColors.textLight, fontSize: 14),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textLight),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          if (_searching)
            const LinearProgressIndicator(
              minHeight: 1,
              color: AppColors.primary,
              backgroundColor: Colors.transparent,
            ),
          const SizedBox(height: 4),
          // Conversation list
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chat, _) {
                if (chat.loading && chat.conversations.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                final keyword = _searchController.text.trim();
                final searching = keyword.isNotEmpty;

                final display = searching
                    ? _searchMatches
                    : chat.conversations
                        .map((c) => <String, dynamic>{'conversation': c})
                        .toList();

                if (display.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          searching ? '没有匹配的联系人或聊天记录' : '暂无会话',
                          style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refreshList,
                  child: ListView.separated(
                    itemCount: display.length,
                    separatorBuilder: (_, _) => const Divider(height: 0.5, indent: 76, endIndent: 0, color: Color(0xFFEEEEEE)),
                    itemBuilder: (context, index) {
                      final entry = display[index];
                      final conv = Map<String, dynamic>.from(entry['conversation'] as Map<String, dynamic>);
                      return _buildConvTile(
                        context,
                        conv,
                        chat,
                        matchedType: entry['matchedType']?.toString(),
                        matchedText: entry['matchedText']?.toString(),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConvTile(
    BuildContext context,
    Map<String, dynamic> conv,
    ChatProvider chat, {
    String? matchedType,
    String? matchedText,
  }) {
    final convId = conv['conversationId']?.toString();
    final name = chat.getConvDisplayName(conv);
    final avatarUrl = chat.getConvAvatarUrl(conv);
    final lastMsg = chat.getLastMsgPreview(conv);
    final isTyping = convId != null && chat.isPeerTyping(convId);
    final isOnline = chat.isConversationOnline(conv);
    final isPrivateConv = conv['type'] == 1;
    final subtitle = matchedType == 'message' && (matchedText?.trim().isNotEmpty ?? false)
        ? '聊天记录：${matchedText!.trim()}'
        : lastMsg;
    final time = formatTime(conv['updatedAt']?.toString());
    final unread = (conv['unreadCount'] as num?)?.toInt() ?? 0;
    final isPinned = conv['isPinned'] == true;
    final isDisturb = conv['isDisturb'] == true;

    return Slidable(
      key: ValueKey('conv-$convId'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.42,
        children: [
          SlidableAction(
            onPressed: (_) => _togglePin(conv, chat),
            backgroundColor: const Color(0xFFEDB95E),
            foregroundColor: Colors.white,
            icon: isPinned ? Icons.push_pin_outlined : Icons.vertical_align_top,
            label: isPinned ? '取消置顶' : '置顶',
          ),
          SlidableAction(
            onPressed: (_) => _deleteConversation(conv, chat),
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: '删除',
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          if (convId != null) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ChatPage(conversationId: convId, title: name)),
            );
          }
        },
        child: Container(
          color: isPinned ? const Color(0xFFFFFBF2) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(name: name, url: avatarUrl, size: 48, radius: 24),
                  if (unread > 0 && isDisturb)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  if (unread > 0 && !isDisturb)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: const BoxConstraints(minWidth: 18),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (isPrivateConv)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF34C759) : const Color(0xFFC7C7CC),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.4),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isPinned) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE7B3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '置顶',
                              style: TextStyle(fontSize: 10, color: Color(0xFF9A6A00), fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                          ),
                        ),
                        if (isDisturb)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.notifications_off_outlined, size: 14, color: AppColors.textSecondary),
                          ),
                        const SizedBox(width: 8),
                        Text(time, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTyping ? '对方正在输入中...' : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isTyping
                            ? AppColors.primary
                            : matchedType == 'message'
                                ? AppColors.primary
                                : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
