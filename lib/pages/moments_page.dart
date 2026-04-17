import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/app_config.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/utils/time_utils.dart';
import 'package:im_client/utils/web_file_picker.dart';
import 'package:im_client/widgets/user_avatar.dart';

class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _moments = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadMoments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMoments() async {
    setState(() { _loading = true; _page = 1; });
    try {
      final api = context.read<ApiClient>();
      final results = await Future.wait([
        api.get('/moments', params: {'page': '1', 'pageSize': '20'}),
        api.get('/moments/notifications', params: {'limit': '10'}),
      ]);
      if (!mounted) return;
      final data = results[0];
      final notifData = results[1];
      setState(() {
        _moments = List<Map<String, dynamic>>.from(data['list'] ?? []);
        _total = data['pagination']?['total'] ?? 0;
        _notifications = notifData is List
            ? List<Map<String, dynamic>>.from(notifData)
            : List<Map<String, dynamic>>.from(notifData['data'] ?? notifData['list'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _moments.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final api = context.read<ApiClient>();
      final nextPage = _page + 1;
      final data = await api.get('/moments', params: {'page': '$nextPage', 'pageSize': '20'});
      if (!mounted) return;
      setState(() {
        _moments.addAll(List<Map<String, dynamic>>.from(data['list'] ?? []));
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleLike(int index) async {
    final moment = _moments[index];
    final momentId = moment['momentId'];
    final currentUserId = context.read<AuthService>().userId;
    final currentUser = context.read<AuthService>().user ?? {};

    // Optimistic update
    final wasLiked = moment['isLiked'] == true;
    setState(() {
      _moments[index] = {
        ...moment,
        'isLiked': !wasLiked,
        'likeCount': (moment['likeCount'] ?? 0) + (wasLiked ? -1 : 1),
        'likes': wasLiked
            ? (moment['likes'] as List).where((l) => l['userId'] != currentUserId).toList()
            : [...(moment['likes'] as List? ?? []), {'userId': currentUserId, 'nickname': currentUser['nickname']}],
      };
    });

    try {
      await context.read<ApiClient>().post('/moments/$momentId/like');
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() => _moments[index] = moment);
        AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
      }
    }
  }

  Future<void> _addComment(int index, {int? replyUserId, String? replyNickname, int? replyCommentId}) async {
    final moment = _moments[index];
    final controller = TextEditingController();
    final hint = replyNickname != null ? '回复 $replyNickname' : '写评论...';

    final content = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: hint,
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.primary)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) Navigator.pop(ctx, text);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                child: const Text('发送', style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty || !mounted) return;

    try {
      final api = context.read<ApiClient>();
      final result = await api.post('/moments/${moment['momentId']}/comments', data: {
        'content': content,
        'replyUserId': replyUserId,
        'replyCommentId': replyCommentId,
      });
      if (!mounted) return;
      setState(() {
        final comments = List<Map<String, dynamic>>.from(moment['comments'] ?? []);
        comments.add(Map<String, dynamic>.from(result));
        _moments[index] = {
          ...moment,
          'comments': comments,
          'commentCount': (moment['commentCount'] ?? 0) + 1,
        };
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '评论失败'));
    }
  }

  Future<void> _deleteComment(int momentIndex, int commentId) async {
    try {
      final api = context.read<ApiClient>();
      await api.delete('/moments/comments/$commentId');
      if (!mounted) return;
      final moment = _moments[momentIndex];
      setState(() {
        final comments = List<Map<String, dynamic>>.from(moment['comments'] ?? []);
        comments.removeWhere((c) => c['commentId'] == commentId);
        _moments[momentIndex] = {
          ...moment,
          'comments': comments,
          'commentCount': (moment['commentCount'] ?? 0) - 1,
        };
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '删除失败'));
    }
  }

  Future<void> _deleteMoment(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('确定删除该条动态？'),
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
      final api = context.read<ApiClient>();
      await api.delete('/moments/${_moments[index]['momentId']}');
      if (!mounted) return;
      setState(() => _moments.removeAt(index));
      AppToast.show(context, '已删除');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '删除失败'));
    }
  }

  void _openPostPage() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const _PostMomentPage())).then((result) {
      if (result == true) _loadMoments();
    });
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
        title: const Text('朋友圈', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E5E5)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, size: 24),
            onPressed: _openPostPage,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMoments,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Notification bar
            if (_notifications.isNotEmpty)
              SliverToBoxAdapter(child: _buildNotificationBar()),
            // Moments list
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_moments.isEmpty)
              SliverFillRemaining(child: _buildEmpty())
            else ...[
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildMomentCard(i),
                  childCount: _moments.length,
                ),
              ),
              if (_loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                ),
              if (!_loadingMore && _moments.length >= _total && _moments.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('— 没有更多了 —', style: TextStyle(color: AppColors.textLight, fontSize: 13))),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBar() {
    // Show the most recent notification as a summary bar
    final first = _notifications.first;
    final nickname = first['nickname']?.toString() ?? '';
    final text = first['text']?.toString() ?? '';
    final avatarUrl = first['avatarUrl']?.toString();
    final count = _notifications.length;
    final resolvedAvatar = avatarUrl != null && avatarUrl.isNotEmpty ? AppConfig.resolveFileUrl(avatarUrl) : null;

    return GestureDetector(
      onTap: () => _showAllNotifications(),
      child: Container(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar with red dot
            Stack(
              children: [
                if (resolvedAvatar != null && resolvedAvatar.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(resolvedAvatar, width: 40, height: 40, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.notifications_outlined, size: 20, color: AppColors.primary),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.notifications_outlined, size: 20, color: AppColors.primary),
                  ),
                if (count > 1)
                  Positioned(
                    top: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(8)),
                      child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: nickname, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF576B95))),
                      TextSpan(text: ' $text', style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (count > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('等 $count 条新互动', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showAllNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          expand: false,
          builder: (ctx, sc) {
            return Column(
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('最近互动', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _notifications.isEmpty
                      ? const Center(child: Text('暂无互动', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.separated(
                          controller: sc,
                          itemCount: _notifications.length,
                          separatorBuilder: (_, _) => const Divider(height: 0.5, indent: 68),
                          itemBuilder: (ctx, i) {
                            final n = _notifications[i];
                            final nick = n['nickname']?.toString() ?? '';
                            final txt = n['text']?.toString() ?? '';
                            final type = n['type']?.toString() ?? '';
                            final content = n['content']?.toString() ?? '';
                            final createdAt = n['createdAt']?.toString() ?? '';
                            final avUrl = n['avatarUrl']?.toString();
                            final resolvedAv = avUrl != null && avUrl.isNotEmpty ? AppConfig.resolveFileUrl(avUrl) : null;

                            IconData icon;
                            Color iconColor;
                            switch (type) {
                              case 'like':
                                icon = Icons.favorite;
                                iconColor = const Color(0xFFE53935);
                                break;
                              case 'comment':
                                icon = Icons.chat_bubble;
                                iconColor = AppColors.primary;
                                break;
                              default:
                                icon = Icons.dynamic_feed;
                                iconColor = const Color(0xFF43A047);
                            }

                            return ListTile(
                              leading: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  UserAvatar(name: nick, url: resolvedAv, size: 42, radius: 21),
                                  Positioned(
                                    bottom: -2, right: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                      child: Icon(icon, size: 14, color: iconColor),
                                    ),
                                  ),
                                ],
                              ),
                              title: Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: nick, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF576B95), fontSize: 14)),
                                  TextSpan(text: ' $txt', style: const TextStyle(fontSize: 14)),
                                ]),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (content.isNotEmpty)
                                    Text(content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                  Text(formatTime(createdAt), style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dynamic_feed_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text('暂无动态', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openPostPage,
            child: const Text('发布第一条动态', style: TextStyle(color: AppColors.primary, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildMomentCard(int index) {
    final m = _moments[index];
    final currentUserId = context.read<AuthService>().userId;
    final isOwn = m['userId'] == currentUserId;
    final likes = List<Map<String, dynamic>>.from(m['likes'] ?? []);
    final comments = List<Map<String, dynamic>>.from(m['comments'] ?? []);
    final media = List<dynamic>.from(m['media'] ?? []);

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          UserAvatar(name: m['nickname'], url: m['avatarUrl'], size: 42, radius: 6),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nickname
                Text((m['nickname'] ?? '').toString(), style: const TextStyle(color: Color(0xFF576B95), fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                // Text content
                if (m['content'] != null && m['content'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(m['content'].toString(), style: const TextStyle(fontSize: 15, height: 1.4)),
                  ),
                // Media grid
                if (media.isNotEmpty) _buildMediaGrid(media),
                // Location
                if (m['location'] != null && m['location'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textLight),
                        const SizedBox(width: 2),
                        Text(m['location'].toString(), style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                // Time + actions row
                Row(
                  children: [
                    Text(formatTime(m['createdAt']?.toString()), style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                    const Spacer(),
                    if (isOwn)
                      GestureDetector(
                        onTap: () => _deleteMoment(index),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text('删除', style: TextStyle(color: Color(0xFF576B95), fontSize: 12)),
                        ),
                      ),
                    const SizedBox(width: 4),
                    _buildLikeButton(index),
                    const SizedBox(width: 4),
                    _buildCommentButton(index),
                  ],
                ),
                // Likes + Comments section
                if (likes.isNotEmpty || comments.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (likes.isNotEmpty) _buildLikesRow(likes),
                        if (likes.isNotEmpty && comments.isNotEmpty)
                          const Divider(height: 0.5, color: Color(0xFFE0E0E0)),
                        if (comments.isNotEmpty) _buildCommentsSection(index, comments),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 0.5, color: Color(0xFFEEEEEE)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<dynamic> media) {
    final count = media.length;
    final size = count == 1 ? 200.0 : (count <= 4 ? 120.0 : 90.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: media.map((item) {
          final url = item is Map ? (item['url'] ?? '') : item.toString();
          return GestureDetector(
            onTap: () => _showFullImage(context, url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                _fullUrl(url),
                width: size,
                height: size,
                fit: count == 1 ? BoxFit.contain : BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: size,
                  height: size,
                  color: const Color(0xFFF0F0F0),
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.textLight),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fullUrl(String url) {
    if (url.startsWith('http')) return url;
    final baseUrl = context.read<ApiClient>().baseUrl;
    final serverUrl = baseUrl.replaceAll('/api/v1', '');
    return '$serverUrl$url';
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(_fullUrl(url), fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  Widget _buildLikeButton(int index) {
    final isLiked = _moments[index]['isLiked'] == true;
    return GestureDetector(
      onTap: () => _toggleLike(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          size: 20,
          color: isLiked ? const Color(0xFFE53935) : const Color(0xFF576B95),
        ),
      ),
    );
  }

  Widget _buildCommentButton(int index) {
    return GestureDetector(
      onTap: () => _addComment(index),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF576B95)),
      ),
    );
  }

  Widget _buildLikesRow(List<Map<String, dynamic>> likes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.favorite, size: 14, color: Color(0xFF576B95)),
          const SizedBox(width: 4),
          Expanded(
            child: Wrap(
              children: likes.asMap().entries.map((e) {
                final i = e.key;
                final l = e.value;
                return Text.rich(
                  TextSpan(children: [
                    TextSpan(text: l['nickname'] ?? '', style: const TextStyle(color: Color(0xFF576B95), fontSize: 13, fontWeight: FontWeight.w500)),
                    if (i < likes.length - 1) const TextSpan(text: ', ', style: TextStyle(color: Color(0xFF576B95), fontSize: 13)),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(int momentIndex, List<Map<String, dynamic>> comments) {
    final currentUserId = context.read<AuthService>().userId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: comments.map((c) {
          final isOwn = c['userId'] == currentUserId;
          return GestureDetector(
            onTap: () {
              if (c['userId'] != currentUserId) {
                _addComment(momentIndex, replyUserId: c['userId'], replyNickname: c['nickname'], replyCommentId: c['commentId']);
              }
            },
            onLongPress: isOwn ? () => _deleteComment(momentIndex, c['commentId']) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: c['nickname'] ?? '', style: const TextStyle(color: Color(0xFF576B95), fontSize: 13, fontWeight: FontWeight.w500)),
                  if (c['replyNickname'] != null) ...[
                    const TextSpan(text: ' 回复 ', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    TextSpan(text: c['replyNickname'], style: const TextStyle(color: Color(0xFF576B95), fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                  const TextSpan(text: ': ', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                  TextSpan(text: c['content'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 发布动态页面
class _PostMomentPage extends StatefulWidget {
  const _PostMomentPage();

  @override
  State<_PostMomentPage> createState() => _PostMomentPageState();
}

class _PostMomentPageState extends State<_PostMomentPage> {
  final TextEditingController _textController = TextEditingController();
  final List<PickedFileData> _images = [];
  int _visibility = 0;
  bool _posting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = 9 - _images.length;
    if (remaining <= 0) return;

    if (kIsWeb) {
      final files = await pickImagesFromWeb(maxCount: remaining);
      if (files.isNotEmpty && mounted) {
        setState(() => _images.addAll(files));
      }
    } else {
      final picker = ImagePicker();
      List<XFile> files;
      try {
        files = await picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
      } catch (_) {
        final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920);
        files = file != null ? [file] : [];
      }
      if (files.isEmpty || !mounted) return;
      final picked = <PickedFileData>[];
      for (final f in files.take(remaining)) {
        final bytes = await f.readAsBytes();
        final ext = f.name.split('.').last.toLowerCase();
        final mime = ['png', 'gif', 'webp'].contains(ext) ? 'image/$ext' : 'image/jpeg';
        picked.add(PickedFileData(name: f.name, bytes: bytes, mimeType: mime));
      }
      if (picked.isNotEmpty && mounted) {
        setState(() => _images.addAll(picked));
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _post() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _images.isEmpty) {
      AppToast.show(context, '请输入内容或选择图片');
      return;
    }

    setState(() => _posting = true);
    try {
      final api = context.read<ApiClient>();

      // Upload images
      List<Map<String, dynamic>> media = [];
      for (final img in _images) {
        final bytes = img.bytes;
        final ext = img.name.split('.').last.toLowerCase();
        final mime = ['png', 'gif', 'webp'].contains(ext) ? 'image/$ext' : 'image/jpeg';
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: img.name, contentType: MediaType.parse(mime)),
        });
        final uploadResult = Map<String, dynamic>.from(await api.upload('/upload', formData));
        media.add({'url': uploadResult['url'], 'type': 'image'});
      }

      await api.post('/moments', data: {
        'content': text,
        'type': media.isNotEmpty ? 2 : 1,
        'media': media.isNotEmpty ? media : null,
        'visibility': _visibility,
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      AppToast.show(context, ErrorMessage.from(e, fallback: '发布失败'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _posting ? null : _post,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: _posting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('发表'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Text input
          TextField(
            controller: _textController,
            maxLines: 6,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: '这一刻的想法...',
              hintStyle: TextStyle(color: AppColors.textLight, fontSize: 16),
              border: InputBorder.none,
              counterText: '',
            ),
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 12),
          // Image grid
          _buildImageGrid(),
          const SizedBox(height: 20),
          const Divider(height: 0.5),
          // Visibility
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.visibility_outlined, color: AppColors.textSecondary),
            title: const Text('谁可以看', style: TextStyle(fontSize: 15)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _visibility == 0 ? '公开' : _visibility == 1 ? '好友可见' : '仅自己',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
              ],
            ),
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.public),
                        title: const Text('公开'),
                        trailing: _visibility == 0 ? const Icon(Icons.check, color: AppColors.primary) : null,
                        onTap: () { setState(() => _visibility = 0); Navigator.pop(ctx); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.people_outline),
                        title: const Text('好友可见'),
                        trailing: _visibility == 1 ? const Icon(Icons.check, color: AppColors.primary) : null,
                        onTap: () { setState(() => _visibility = 1); Navigator.pop(ctx); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('仅自己'),
                        trailing: _visibility == 2 ? const Icon(Icons.check, color: AppColors.primary) : null,
                        onTap: () { setState(() => _visibility = 2); Navigator.pop(ctx); },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._images.asMap().entries.map((e) {
          final i = e.key;
          final img = e.value;
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(img.bytes, width: 100, height: 100, fit: BoxFit.cover),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => _removeImage(i),
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        }),
        if (_images.length < 9)
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 28, color: AppColors.textLight),
                  SizedBox(height: 4),
                  Text('添加图片', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
