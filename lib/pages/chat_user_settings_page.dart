import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:im_client/config/app_config.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/utils/clipboard_util.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';
import 'package:im_client/widgets/image_gallery_page.dart';
import 'package:im_client/pages/chat_page.dart';

class ChatUserSettingsPage extends StatefulWidget {
  final int targetUserId;
  final String conversationId;

  const ChatUserSettingsPage({
    super.key,
    required this.targetUserId,
    required this.conversationId,
  });

  @override
  State<ChatUserSettingsPage> createState() => _ChatUserSettingsPageState();
}

class _ChatUserSettingsPageState extends State<ChatUserSettingsPage> {
  Map<String, dynamic>? _userInfo;
  bool _loading = true;
  bool _isBlocked = false;
  String _remark = '';
  List<Map<String, dynamic>> _mediaFiles = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadMediaFiles();
  }

  Future<void> _loadUserInfo() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/users/${widget.targetUserId}');
      if (!mounted) return;

      // Check block status from friends list
      final friends = context.read<ContactsProvider>().friends;
      final friend = friends.where((f) => f['userId'] == widget.targetUserId).firstOrNull;

      setState(() {
        _userInfo = Map<String, dynamic>.from(data ?? {});
        _remark = friend?['remark']?.toString() ?? '';
        _isBlocked = _userInfo?['isBlocked'] == true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, ErrorMessage.from(e, fallback: '加载失败'));
      }
    }
  }

  Future<void> _loadMediaFiles() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/messages/media', params: {
        'conversationId': widget.conversationId,
        'limit': '200',
      });
      final list = List<Map<String, dynamic>>.from(data is List ? data : (data?['list'] ?? []));
      // Filter media messages (type 2=image, 4=video, 5=file, 11=album)
      final media = <Map<String, dynamic>>[];
      for (final m in list) {
        final type = m['type'];
        if (type == 11) {
          // Expand album items into individual media entries
          final content = m['content'];
          if (content is Map<String, dynamic>) {
            final items = content['items'];
            if (items is List) {
              for (final item in items) {
                if (item is Map) {
                  final mediaType = (item['mediaType']?.toString() ?? 'image');
                  final syntheticType = mediaType == 'video' ? 4 : 2;
                  media.add({
                    ...m,
                    'type': syntheticType,
                    'content': Map<String, dynamic>.from(item),
                  });
                }
              }
            }
          }
        } else if (type == 2 || type == 4 || type == 5) {
          media.add(m);
        }
      }
      if (mounted) {
        setState(() {
          _mediaFiles = media;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPanel,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        title: const Text('聊天详情', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildUserCard(),
                const SizedBox(height: 10),
                _buildSettingsSection(),
                const SizedBox(height: 10),
                _buildMediaSection(),
                const SizedBox(height: 10),
                _buildDangerSection(),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _buildUserCard() {
    final nickname = _userInfo?['nickname']?.toString() ?? '未知';
    final avatarUrl = _userInfo?['avatarUrl']?.toString();
    final uid = _userInfo?['uid']?.toString() ?? '';
    final signature = _userInfo?['signature']?.toString() ?? '';
    final gender = _userInfo?['gender'];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: nickname, url: avatarUrl, size: 56, radius: 8),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _remark.isNotEmpty ? '$nickname（$_remark）' : nickname,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (gender == 1)
                      const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.male, color: Colors.blue, size: 18)),
                    if (gender == 2)
                      const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.female, color: Colors.pink, size: 18)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              conversationId: widget.conversationId,
                              title: _remark.isNotEmpty ? _remark : nickname,
                            ),
                          ),
                        );
                      },
                      child: const Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () async {
                    if (uid.isNotEmpty) {
                      await ClipboardUtil.copy(uid);
                      if (context.mounted) AppToast.show(context, '已复制 UID');
                    }
                  },
                  child: Text('UID: $uid', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
                if (signature.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(signature, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _settingTile(Icons.edit_outlined, '设置备注', subtitle: _remark.isEmpty ? '未设置' : _remark, onTap: _showRemarkDialog),
          _divider(),
          _settingTile(Icons.share_outlined, '分享名片', onTap: _shareContactCard),
          _divider(),
          _settingTile(Icons.search, '搜索聊天记录', onTap: _searchMessages),
        ],
      ),
    );
  }

  Widget _buildMediaSection() {
    final images = _mediaFiles.where((m) => m['type'] == 2).toList();
    final videos = _mediaFiles.where((m) => m['type'] == 4).toList();
    final files = _mediaFiles.where((m) => m['type'] == 5).toList();

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _settingTile(Icons.photo_outlined, '图片', trailing: '${images.length}', onTap: () => _showMediaView('图片', images)),
          _divider(),
          _settingTile(Icons.videocam_outlined, '视频', trailing: '${videos.length}', onTap: () => _showMediaView('视频', videos)),
          _divider(),
          _settingTile(Icons.folder_outlined, '文件', trailing: '${files.length}', onTap: () => _showMediaView('文件', files)),
        ],
      ),
    );
  }

  Widget _buildDangerSection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _settingTile(
            _isBlocked ? Icons.check_circle_outline : Icons.block,
            _isBlocked ? '取消拉黑' : '拉黑用户',
            iconColor: _isBlocked ? AppColors.primary : AppColors.danger,
            textColor: _isBlocked ? AppColors.primary : AppColors.danger,
            onTap: _toggleBlock,
          ),
          _divider(),
          _settingTile(
            Icons.delete_outline,
            '删除好友',
            iconColor: AppColors.danger,
            textColor: AppColors.danger,
            onTap: _deleteFriend,
          ),
        ],
      ),
    );
  }

  Widget _settingTile(IconData icon, String label, {
    String? subtitle,
    String? trailing,
    Color? iconColor,
    Color? textColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 22, color: iconColor ?? AppColors.textPrimary),
      title: Text(label, style: TextStyle(fontSize: 15, color: textColor ?? AppColors.textPrimary)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textLight),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _divider() => const Divider(height: 0.5, indent: 56, color: AppColors.divider);

  // ——— Actions ———

  void _showRemarkDialog() {
    final ctrl = TextEditingController(text: _remark);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('设置备注', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('给好友设置一个备注名，方便识别', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 20,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: '请输入备注名',
                hintStyle: const TextStyle(color: AppColors.textLight),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: AppColors.textLight),
                  onPressed: () => ctrl.clear(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final newRemark = ctrl.text.trim();
                      Navigator.pop(ctx);
                      try {
                        final api = context.read<ApiClient>();
                        await api.put('/friends/${widget.targetUserId}/remark', data: {'remark': newRemark});
                        setState(() => _remark = newRemark);
                        if (mounted) {
                          AppToast.show(context, '备注已更新');
                          context.read<ContactsProvider>().loadFriends();
                          context.read<ChatProvider>().loadConversations();
                        }
                      } catch (e) {
                        if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '设置备注失败'));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text('保存', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _shareContactCard() {
    final nickname = _userInfo?['nickname']?.toString() ?? '未知';
    final avatarUrl = _userInfo?['avatarUrl']?.toString() ?? '';
    final uid = _userInfo?['uid']?.toString() ?? '';
    final userId = widget.targetUserId;

    final chat = context.read<ChatProvider>();
    final conversations = chat.conversations;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                children: [
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 12),
                  Text('分享 $nickname 的名片', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('选择要发送到的会话', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Divider(height: 0.5),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: conversations.length,
                separatorBuilder: (_, _) => const Divider(height: 0.5, indent: 72),
                itemBuilder: (_, i) {
                  final conv = conversations[i];
                  final convName = chat.getConvDisplayName(conv);
                  final convAvatar = chat.getConvAvatarUrl(conv);
                  final convId = conv['conversationId']?.toString() ?? '';
                  return ListTile(
                    leading: UserAvatar(name: convName, url: convAvatar, size: 44, radius: 22),
                    title: Text(convName, style: const TextStyle(fontSize: 15)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await chat.sendMessage(
                          convId,
                          type: 10,
                          content: {
                            'userId': userId,
                            'nickname': nickname,
                            'avatarUrl': avatarUrl,
                            'uid': uid,
                          },
                        );
                        if (mounted) AppToast.show(context, '名片已发送');
                      } catch (e) {
                        if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '分享失败'));
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _searchMessages() {
    final searchCtrl = TextEditingController();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SearchMessagesPage(
        conversationId: widget.conversationId,
        searchController: searchCtrl,
      ),
    ));
  }

  Future<void> _toggleBlock() async {
    final action = _isBlocked ? '取消拉黑' : '拉黑';
    final api = context.read<ApiClient>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action用户'),
        content: Text('确定要$action该用户吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定', style: TextStyle(color: _isBlocked ? AppColors.primary : AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (_isBlocked) {
        await api.delete('/friends/${widget.targetUserId}/block');
      } else {
        await api.post('/friends/${widget.targetUserId}/block');
      }
      setState(() => _isBlocked = !_isBlocked);
      if (mounted) {
        AppToast.show(context, '$action成功');
      }
    } catch (e) {
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '$action失败'));
    }
  }

  Future<void> _deleteFriend() async {
    final api = context.read<ApiClient>();
    final contacts = context.read<ContactsProvider>();
    final chat = context.read<ChatProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除好友'),
        content: const Text('删除后将清除聊天记录，且对方将从你的通讯录中移除，确定要删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await api.delete('/friends/${widget.targetUserId}');
      if (mounted) {
        AppToast.show(context, '已删除好友');
        contacts.loadFriends();
        chat.loadConversations();
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '删除失败'));
    }
  }

  void _showMediaView(String title, List<Map<String, dynamic>> items) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MediaListPage(title: title, items: items),
    ));
  }
}

// ——— Search Messages Page ———
class _SearchMessagesPage extends StatefulWidget {
  final String conversationId;
  final TextEditingController searchController;

  const _SearchMessagesPage({required this.conversationId, required this.searchController});

  @override
  State<_SearchMessagesPage> createState() => _SearchMessagesPageState();
}

class _SearchMessagesPageState extends State<_SearchMessagesPage> {
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  Future<void> _doSearch(String keyword) async {
    if (keyword.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/messages/search', params: {
        'conversationId': widget.conversationId,
        'keyword': keyword.trim(),
      });
      if (mounted) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(data?['list'] ?? data ?? []);
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPanel,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: TextField(
          controller: widget.searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索聊天记录',
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
          onSubmitted: _doSearch,
        ),
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? const Center(child: Text('暂无结果', style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final msg = _results[i];
                    final sender = msg['sender'] as Map<String, dynamic>? ?? {};
                    final content = msg['content'];
                    final text = content is String ? content : (content is Map ? (content['text'] ?? '[消息]') : '[消息]');
                    return ListTile(
                      leading: UserAvatar(name: sender['nickname'], url: sender['avatarUrl'], size: 36),
                      title: Text(sender['nickname']?.toString() ?? '', style: const TextStyle(fontSize: 14)),
                      subtitle: Text(text.toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      trailing: Text(
                        msg['createdAt']?.toString().substring(0, 10) ?? '',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    );
                  },
                ),
    );
  }
}

// ——— Media List Page ———
class _MediaListPage extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;

  const _MediaListPage({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPanel,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text('$title（${items.length}）', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: items.isEmpty
          ? Center(child: Text('暂无$title', style: const TextStyle(color: AppColors.textSecondary)))
          : title == '文件'
              ? _buildFileList()
              : _buildMediaGrid(context),
    );
  }

  Widget _buildMediaGrid(BuildContext context) {
    // Collect all image urls for gallery
    final allImageUrls = <String>[];
    for (final msg in items) {
      final content = msg['content'];
      if (content is Map<String, dynamic>) {
        final url = content['url']?.toString() ?? content['thumbnailUrl']?.toString() ?? '';
        final resolved = AppConfig.resolveFileUrl(url);
        if (resolved.isNotEmpty) allImageUrls.add(resolved);
      }
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final msg = items[i];
        final content = msg['content'];
        String url = '';
        if (content is Map<String, dynamic>) {
          url = content['url']?.toString() ?? content['thumbnailUrl']?.toString() ?? '';
        }
        final resolvedUrl = AppConfig.resolveFileUrl(url);
        return GestureDetector(
          onTap: () {
            int idx = allImageUrls.indexOf(resolvedUrl);
            if (idx < 0) idx = 0;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ImageGalleryPage(
                imageUrls: allImageUrls,
                initialIndex: idx,
              ),
            ));
          },
          child: CachedNetworkImage(
            imageUrl: resolvedUrl,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(
              color: const Color(0xFFE0E0E0),
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final msg = items[i];
        final content = msg['content'];
        String name = '文件';
        String size = '';
        if (content is Map<String, dynamic>) {
          name = content['name']?.toString() ?? '文件';
          final bytes = content['size'];
          if (bytes is num) {
            if (bytes > 1024 * 1024) {
              size = '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
            } else if (bytes > 1024) {
              size = '${(bytes / 1024).toStringAsFixed(1)} KB';
            } else {
              size = '$bytes B';
            }
          }
        }
        final sender = msg['sender'] as Map<String, dynamic>? ?? {};
        return ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined, size: 36, color: AppColors.primary),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            '${sender['nickname'] ?? ''} · $size',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          trailing: Text(
            msg['createdAt']?.toString().substring(0, 10) ?? '',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        );
      },
    );
  }
}
