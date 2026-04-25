import 'dart:async';

import 'package:flutter/material.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/socket_service.dart';
import 'package:im_client/services/notification_service.dart';
import 'package:im_client/utils/notification_sound.dart';

class ChatProvider extends ChangeNotifier {
  final ApiClient api;
  final SocketService socket;

  List<Map<String, dynamic>> _conversations = [];
  final Map<String, List<Map<String, dynamic>>> _messages = {};
  final Map<String, bool> _peerTyping = {};
  final Map<String, Timer> _typingTimers = {};
  String? _currentConvId;
  bool _loading = false;
  Timer? _loadDebounce;
  /// 最近已读的会话 ID（用于 loadConversations 合并时强制清零，防止服务端旧数据覆盖）
  final Set<String> _recentlyReadConvIds = {};
  /// 并发锁 + 节流：避免重复请求
  Future<void>? _loadConvFuture;
  DateTime? _lastLoadConvTime;

  ChatProvider({required this.api, required this.socket}) {
    socket.on('message:new', _onNewMessage);
    socket.on('message:revoked', _onMessageRevoked);
    socket.on('message:read', _onMessageRead);
    socket.on('typing:start', _onTypingStart);
    socket.on('typing:stop', _onTypingStop);
    socket.on('friend:status', _onFriendStatus);
    socket.on('conversation:created', _onConversationCreated);
    socket.on('conversation:removed', _onConversationRemoved);
    socket.on('conversation:dismissed', _onConversationRemoved);
    socket.on('conversation:member-removed', _onMemberRemoved);
    socket.on('conversation:updated', _onConversationUpdated);
    // WebSocket 重连后自动刷新数据（弥补断线期间可能丢失的推送）
    socket.on('connect', _onSocketReconnect);
  }

  List<Map<String, dynamic>> get conversations => _conversations;
  List<Map<String, dynamic>> getMessages(String convId) => _messages[convId] ?? [];
  String? get currentConvId => _currentConvId;
  bool get loading => _loading;
  bool isPeerTyping(String convId) => _peerTyping[convId] == true;

  void clearAll() {
    _conversations = [];
    _messages.clear();
    _peerTyping.clear();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _currentConvId = null;
    _loading = false;
    notifyListeners();
  }

  void setCurrentConv(String? id) {
    _currentConvId = id;
    // 进入会话时：清除该会话的通知栏通知，并刷新角标
    if (id != null) {
      NotificationService().cancelConversationNotification(id);
      // 延迟一点刷新角标（等 markRead 完成）
      Future.delayed(const Duration(milliseconds: 300), () {
        _updateAppBadge();
      });
    }
    notifyListeners();
  }

  void sendTyping(String convId, bool typing) {
    socket.emit(typing ? 'typing:start' : 'typing:stop', {
      'conversationId': convId,
    });
  }

  bool isConversationOnline(Map<String, dynamic> conv) {
    if (conv['type'] != 1) return false;
    final target = conv['targetUser'];
    if (target is! Map) return false;
    return target['onlineStatus'] == 'online';
  }

  /// 防抖加载会话列表（1.5秒内多次调用只执行最后一次）
  void _debouncedLoadConversations() {
    _loadDebounce?.cancel();
    _loadDebounce = Timer(const Duration(milliseconds: 1500), () {
      loadConversations().catchError((_) {});
    });
  }

  /// 加载会话列表（带并发锁和 2 秒节流）
  Future<void> loadConversations({bool force = false}) async {
    // 如果已有请求在进行中，复用同一个 Future
    if (_loadConvFuture != null) return _loadConvFuture!;
    // 2 秒内不重复请求（除非 force）
    if (!force && _lastLoadConvTime != null &&
        DateTime.now().difference(_lastLoadConvTime!).inSeconds < 2) {
      return;
    }
    _loadConvFuture = _doLoadConversations();
    try {
      await _loadConvFuture;
    } finally {
      _loadConvFuture = null;
    }
  }

  Future<void> _doLoadConversations() async {
    try {
      _loading = true;
      notifyListeners();

      // 记录当前本地的未读数，用于在服务端数据较旧时保留本地更高值
      final localUnread = <String, int>{};
      for (final c in _conversations) {
        final id = c['conversationId']?.toString();
        if (id != null) {
          localUnread[id] = (c['unreadCount'] as num?)?.toInt() ?? 0;
        }
      }

      final data = await api.get('/conversations', params: {
        'page': 1,
        'pageSize': 100,
      });
      _conversations = List<Map<String, dynamic>>.from(data?['list'] ?? data ?? []);

      // 合并未读数：取服务端和本地的较大值（防止异步加载覆盖本地实时增量）
      for (final c in _conversations) {
        final id = c['conversationId']?.toString();
        if (id == null) continue;
        final serverUnread = (c['unreadCount'] as num?)?.toInt() ?? 0;
        final clientUnread = localUnread[id] ?? 0;
        if (clientUnread > serverUnread) {
          c['unreadCount'] = clientUnread;
        }
      }

      // 如果用户正在查看某个会话，强制清零该会话的未读数
      if (_currentConvId != null) {
        final curIdx = _conversations.indexWhere((c) => c['conversationId']?.toString() == _currentConvId);
        if (curIdx >= 0) {
          _conversations[curIdx]['unreadCount'] = 0;
        }
      }
      // 最近已读的会话也强制清零（防止离开会话后 debounced load 覆盖回旧值）
      if (_recentlyReadConvIds.isNotEmpty) {
        for (final readId in _recentlyReadConvIds) {
          final ri = _conversations.indexWhere((c) => c['conversationId']?.toString() == readId);
          if (ri >= 0) {
            final serverVal = (_conversations[ri]['unreadCount'] as num?)?.toInt() ?? 0;
            if (serverVal > 0) _conversations[ri]['unreadCount'] = 0;
          }
        }
        _recentlyReadConvIds.clear();
      }
      _sortConversations();
      _loading = false;
      _lastLoadConvTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateConversationSettings(
    String convId, {
    bool? isPinned,
    bool? isDisturb,
  }) async {
    final payload = <String, dynamic>{};
    if (isPinned != null) payload['isPinned'] = isPinned;
    if (isDisturb != null) payload['isDisturb'] = isDisturb;
    if (payload.isEmpty) return;

    await api.put('/conversations/$convId/settings', data: payload);

    final idx = _conversations.indexWhere((c) => c['conversationId']?.toString() == convId);
    if (idx >= 0) {
      if (isPinned != null) _conversations[idx]['isPinned'] = isPinned;
      if (isDisturb != null) _conversations[idx]['isDisturb'] = isDisturb;
      _conversations[idx]['updatedAt'] = DateTime.now().toIso8601String();
      _sortConversations();
      notifyListeners();
    }
  }

  Future<void> deleteConversation(String convId) async {
    await api.delete('/conversations/$convId');
    _conversations.removeWhere((c) => c['conversationId']?.toString() == convId);
    _messages.remove(convId);
    notifyListeners();
  }

  Future<Map<String, dynamic>> createGroupConv({
    required String name,
    required List<int> memberIds,
  }) async {
    final data = await api.post('/conversations/group', data: {
      'name': name,
      'memberIds': memberIds,
    });
    await loadConversations();
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> searchConversationEntries(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    final lower = q.toLowerCase();
    final convById = <String, Map<String, dynamic>>{};
    final matches = <String, Map<String, dynamic>>{};

    for (final conv in _conversations) {
      final convId = conv['conversationId']?.toString();
      if (convId == null) continue;
      convById[convId] = conv;

      final name = getConvDisplayName(conv).toLowerCase();
      if (name.contains(lower)) {
        matches[convId] = {
          'conversation': conv,
          'matchedType': 'name',
          'matchedText': '匹配会话名称',
        };
      }
    }

    final data = await api.get('/messages/search', params: {
      'keyword': q,
      'page': 1,
      'pageSize': 100,
    });
    final msgList = List<Map<String, dynamic>>.from(data?['list'] ?? data ?? []);

    for (final msg in msgList) {
      final convId = msg['conversationId']?.toString();
      if (convId == null) continue;
      final conv = convById[convId];
      if (conv == null) continue;

      final existing = matches[convId];
      if (existing != null && existing['matchedType'] == 'message') {
        continue;
      }

      matches[convId] = {
        'conversation': conv,
        'matchedType': 'message',
        'matchedText': _messageSearchSnippet(msg),
      };
    }

    final result = <Map<String, dynamic>>[];
    for (final conv in _conversations) {
      final convId = conv['conversationId']?.toString();
      if (convId == null) continue;
      final match = matches[convId];
      if (match != null) result.add(match);
    }

    return result;
  }

  /// 消息加载时间缓存：会话 ID → 上次加载时间
  final Map<String, DateTime> _messagesLoadTime = {};

  Future<void> loadMessages(String convId, {bool force = false}) async {
    // 30 秒内不重复加载同一会话的消息（除非 force）
    if (!force && _messages.containsKey(convId) && _messages[convId]!.isNotEmpty) {
      final lastLoad = _messagesLoadTime[convId];
      if (lastLoad != null && DateTime.now().difference(lastLoad).inSeconds < 30) {
        return;
      }
    }
    try {
      final data = await api.get('/messages', params: {'conversationId': convId, 'limit': 50});
      final list = List<Map<String, dynamic>>.from(data is List ? data : (data?['list'] ?? []));

      // 保留本地 pending/failed 消息，防止 reload 时覆盖掉尚未收到服务端确认的消息
      final serverMsgIds = list.map((m) => m['messageId']?.toString()).whereType<String>().toSet();
      final serverClientIds = list.map((m) => m['clientMsgId']?.toString()).whereType<String>().toSet();
      final pendingMsgs = (_messages[convId] ?? []).where((m) {
        final state = m['sendState']?.toString();
        if (state != 'sending' && state != 'failed') return false;
        final mid = m['messageId']?.toString();
        final cid = m['clientMsgId']?.toString();
        if (mid != null && serverMsgIds.contains(mid)) return false;
        if (cid != null && serverClientIds.contains(cid)) return false;
        return true;
      }).toList();

      _messages[convId] = [...list, ...pendingMsgs];
      _messagesLoadTime[convId] = DateTime.now();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// 断线重连后补拉当前会话断线期间丢失的消息（增量同步，不替换现有列表）
  Future<void> _syncMissedMessages(String convId) async {
    final msgs = _messages[convId];
    if (msgs == null || msgs.isEmpty) return;
    int maxSeq = 0;
    for (final m in msgs) {
      final seq = (m['seq'] as num?)?.toInt() ?? 0;
      if (seq > maxSeq) maxSeq = seq;
    }
    if (maxSeq == 0) return;
    try {
      final data = await api.get('/messages/sync', params: {
        'conversationId': convId,
        'afterSeq': maxSeq,
        'limit': 100,
      });
      final newMsgs = List<Map<String, dynamic>>.from(data is List ? data : []);
      if (newMsgs.isEmpty) return;
      final existing = _messages[convId] ?? [];
      final existingIds = existing.map((m) => m['messageId']?.toString()).whereType<String>().toSet();
      final toAdd = newMsgs.where((m) => !existingIds.contains(m['messageId']?.toString())).toList();
      if (toAdd.isEmpty) return;
      _messages[convId] = [...existing, ...toAdd];
      notifyListeners();
    } catch (_) {}
  }

  /// 加载更早的历史消息（分页），返回加载的条数（0 表示没有更多）
  Future<int> loadMoreMessages(String convId) async {
    final existing = _messages[convId];
    if (existing == null || existing.isEmpty) return 0;

    // 取当前最早消息的 seq 作为游标
    final firstMsg = existing.first;
    final beforeSeq = firstMsg['seq'];
    if (beforeSeq == null) return 0;

    try {
      final data = await api.get('/messages', params: {
        'conversationId': convId,
        'beforeSeq': beforeSeq,
        'limit': 50,
      });
      final older = List<Map<String, dynamic>>.from(data is List ? data : (data?['list'] ?? []));
      if (older.isEmpty) return 0;

      // 去重：排除 seq 已存在的消息
      final existingSeqs = existing.map((m) => m['seq']).toSet();
      final newMsgs = older.where((m) => !existingSeqs.contains(m['seq'])).toList();
      if (newMsgs.isEmpty) return 0;

      _messages[convId] = [...newMsgs, ...existing];
      notifyListeners();
      return newMsgs.length;
    } catch (e) {
      debugPrint('[ChatProvider] loadMoreMessages error: $e');
      rethrow; // 让 UI 层区分"网络错误"和"没有更多消息"
    }
  }

  Future<Map<String, dynamic>> sendMessage(
    String convId, {
    required int type,
    required dynamic content,
    String? clientMsgId,
  }) async {
    final result = await api.post('/messages', data: {
      'conversationId': convId,
      'clientMsgId': clientMsgId,
      'type': type,
      'content': content,
    });
    return Map<String, dynamic>.from(result);
  }

  void addPendingMessage(String convId, Map<String, dynamic> msg) {
    _messages.putIfAbsent(convId, () => []);
    _messages[convId]!.add(msg);
    notifyListeners();
  }

  void markPendingMessageSent(
    String convId,
    String localId,
    Map<String, dynamic> result, {
    dynamic content,
  }) {
    final msgs = _messages[convId];
    if (msgs == null) return;

    var idx = msgs.indexWhere((m) => m['messageId'] == localId);
    // _onNewMessage 可能已将 messageId 改为服务端 ID，用 clientMsgId 兜底
    if (idx < 0) {
      idx = msgs.indexWhere((m) => m['clientMsgId'] == localId);
    }
    if (idx < 0) return;

    msgs[idx]['messageId'] = result['messageId'];
    msgs[idx]['clientMsgId'] = result['clientMsgId'] ?? localId;
    msgs[idx]['seq'] = result['seq'];
    msgs[idx]['createdAt'] = result['createdAt'] ?? msgs[idx]['createdAt'];
    msgs[idx]['sendState'] = 'sent';
    msgs[idx]['readState'] = 'unread';
    msgs[idx]['status'] = 1;
    if (content != null) {
      msgs[idx]['content'] = content;
    }

    notifyListeners();
    _debouncedLoadConversations();
  }

  void markPendingMessageFailed(String convId, String localId) {
    final msgs = _messages[convId];
    if (msgs == null) return;

    var idx = msgs.indexWhere((m) => m['messageId'] == localId);
    if (idx < 0) {
      idx = msgs.indexWhere((m) => m['clientMsgId'] == localId);
    }
    if (idx < 0) return;
    // 如果 WS 广播已将消息标记为 sent，不要覆盖为 failed
    if (msgs[idx]['sendState'] == 'sent') return;
    msgs[idx]['sendState'] = 'failed';
    notifyListeners();
  }

  void updatePendingMessageProgress(String convId, String localId, double progress) {
    final msgs = _messages[convId];
    if (msgs == null) return;
    var idx = msgs.indexWhere((m) => m['messageId'] == localId);
    if (idx < 0) {
      idx = msgs.indexWhere((m) => m['clientMsgId'] == localId);
    }
    if (idx < 0) return;
    final content = msgs[idx]['content'];
    if (content is Map<String, dynamic>) {
      content['uploadProgress'] = progress;
    }
    notifyListeners();
  }

  Future<void> markMessageRead(String convId, String messageId) async {
    // 立即在本地清除未读数
    final idx = _conversations.indexWhere((c) => c['conversationId']?.toString() == convId);
    if (idx >= 0 && ((_conversations[idx]['unreadCount'] as num?)?.toInt() ?? 0) > 0) {
      _conversations[idx]['unreadCount'] = 0;
      _updateAppBadge();
      notifyListeners();
    }
    // 记录已读会话，防止 loadConversations 用旧数据覆盖
    _recentlyReadConvIds.add(convId);

    socket.emit('message:read', {
      'conversationId': convId,
      'messageId': messageId,
    });

    try {
      final msg = _messages[convId]?.firstWhere(
        (m) => m['messageId'] == messageId,
        orElse: () => <String, dynamic>{},
      );
      final seq = msg?['seq'];
      if (seq != null) {
        await api.post('/messages/read', data: {
          'conversationId': convId,
          'lastReadSeq': seq,
        });
      }
    } catch (_) {
      // Ignore read sync errors for chat UI continuity.
    }
  }

  void addLocalMessage(String convId, Map<String, dynamic> msg) {
    _messages.putIfAbsent(convId, () => []);
    if (!_messages[convId]!.any((m) => m['messageId'] == msg['messageId'])) {
      _messages[convId]!.add(msg);
      notifyListeners();
    }
  }

  void deleteLocalMessage(String convId, String messageId) {
    if (_messages.containsKey(convId)) {
      _messages[convId]!.removeWhere((m) => m['messageId']?.toString() == messageId);
      notifyListeners();
    }
  }

  void clearLocalMessages(String convId) {
    if (_messages.containsKey(convId)) {
      _messages[convId]!.clear();
      notifyListeners();
    }
  }

  Future<void> revokeMessage(String messageId) async {
    await api.post('/messages/$messageId/revoke');
  }

  Future<Map<String, dynamic>> createPrivateConv(int targetUserId) async {
    final data = await api.post('/conversations/private', data: {'targetUserId': targetUserId});
    await loadConversations(force: true);
    return Map<String, dynamic>.from(data);
  }

  bool _firstConnect = true;
  void _onSocketReconnect(dynamic _) {
    // 首次连接由 _connectAndLoad 处理，仅处理重连
    if (_firstConnect) {
      _firstConnect = false;
      return;
    }
    debugPrint('[ChatProvider] socket reconnected, refreshing data');
    loadConversations().catchError((_) {});
    // 补拉当前会话断线期间丢失的消息
    if (_currentConvId != null) {
      _syncMissedMessages(_currentConvId!).catchError((_) {});
    }
  }

  void _onNewMessage(dynamic data) {
    if (data is! Map) return;
    final msg = Map<String, dynamic>.from(data);
    final convId = msg['conversationId']?.toString();
    if (convId == null) return;

    _typingTimers.remove(convId)?.cancel();
    _peerTyping[convId] = false;

    _messages.putIfAbsent(convId, () => []);

    // 去重：检查 messageId 以及 clientMsgId（防止 socket 推送与本地 pending 消息重复）
    final msgId = msg['messageId']?.toString();
    final clientMsgId = msg['clientMsgId']?.toString();
    final list = _messages[convId]!;
    final alreadyExists = list.any((m) {
      if (m['messageId']?.toString() == msgId) return true;
      if (clientMsgId != null && clientMsgId.isNotEmpty && m['clientMsgId']?.toString() == clientMsgId) return true;
      return false;
    });
    if (alreadyExists) {
      // 如果是 pending/failed 消息，用服务端数据更新它（HTTP超时但WS广播到达时恢复）
      final pendingIdx = list.indexWhere((m) =>
        clientMsgId != null && clientMsgId.isNotEmpty &&
        m['clientMsgId']?.toString() == clientMsgId &&
        (m['sendState'] == 'sending' || m['sendState'] == 'failed'));
      if (pendingIdx >= 0) {
        list[pendingIdx]['messageId'] = msgId;
        list[pendingIdx]['sendState'] = 'sent';
        list[pendingIdx]['status'] = 1;
        list[pendingIdx]['seq'] = msg['seq'];
        list[pendingIdx]['createdAt'] = msg['createdAt'] ?? list[pendingIdx]['createdAt'];
        // 同步服务端返回的 content（含真实 url），防止本地 content 停留在 uploading 状态
        if (msg['content'] != null) {
          list[pendingIdx]['content'] = msg['content'];
        }
        notifyListeners();
      }
      return;
    }
    list.add(msg);

    // 即时更新会话列表的 lastMessage，避免需要等 loadConversations
    final convIdx = _conversations.indexWhere((c) => c['conversationId']?.toString() == convId);
    if (convIdx >= 0) {
      _conversations[convIdx]['lastMessage'] = msg;
      _conversations[convIdx]['updatedAt'] = msg['createdAt'] ?? DateTime.now().toIso8601String();
      // 如果用户正在查看该会话，不增加未读数
      if (_currentConvId != convId) {
        _conversations[convIdx]['unreadCount'] = ((_conversations[convIdx]['unreadCount'] as num?)?.toInt() ?? 0) + 1;
        // 如果未开启免打扰，播放提示音并发送系统通知
        final isDisturb = _conversations[convIdx]['isDisturb'] == true;
        if (!isDisturb) {
          NotificationSound.play();
          // 提取发送者名称（服务端格式: sender: {nickname, avatarUrl, userId}）
          final sender = msg['sender'];
          final senderName = (sender is Map ? sender['nickname']?.toString() : null)
              ?? msg['senderNickname']?.toString()
              ?? msg['senderName']?.toString()
              ?? '新消息';
          // 通知正文：根据消息类型生成（1=文本, 2=图片, 3=语音, ...）
          String body;
          final msgType = msg['type'];
          switch (msgType) {
            case 2: body = '[图片]'; break;
            case 3: body = '[语音]'; break;
            case 4: body = '[视频]'; break;
            case 5: body = '[文件]'; break;
            case 6: body = '[位置]'; break;
            case 7: body = '[红包]'; break;
            case 9: body = '[通话记录]'; break;
            case 10: body = '[名片]'; break;
            case 11: body = '[相册]'; break;
            default:
              // type=1 文字消息或其他，提取 content.text
              final content = msg['content'];
              if (content is Map) {
                body = content['text']?.toString() ?? '你收到一条新消息';
              } else if (content is String) {
                body = content.isNotEmpty ? content : '你收到一条新消息';
              } else {
                body = '你收到一条新消息';
              }
          }
          try {
            NotificationService().showMessageNotification(
              senderName: senderName,
              body: body,
              conversationId: convId,
            );
          } catch (e) {
            debugPrint('[ChatProvider] notification error: $e');
          }
        }
      }
      _sortConversations();
    }

    // 已读标记由 ChatPage UI 层（_markLatestIncomingAsRead）在消息可见时触发，
    // 这里不再自动标记，避免用户未实际查看就发送已读回执

    // 延迟同步服务端数据（避免连续消息导致竞态覆盖本地未读数）
    _debouncedLoadConversations();
    notifyListeners();
  }

  void _onMessageRevoked(dynamic data) {
    if (data == null) return;
    final convId = data['conversationId']?.toString();
    final msgId = data['messageId'];
    if (convId == null || msgId == null) return;
    final msgs = _messages[convId];
    if (msgs != null) {
      final idx = msgs.indexWhere((m) => m['messageId'] == msgId);
      if (idx >= 0) {
        msgs[idx]['status'] = 2;
        notifyListeners();
      }
    }
  }

  void _onMessageRead(dynamic data) {
    if (data == null) return;
    final convId = data['conversationId']?.toString();
    final msgId = data['messageId'];
    if (convId == null || msgId == null) return;

    final msgs = _messages[convId];
    if (msgs == null) return;

    // 找到被读的消息的 seq，所有 seq <= 该值的自己发的消息都应标记为已读
    final readMsg = msgs.firstWhere(
      (m) => m['messageId'] == msgId,
      orElse: () => <String, dynamic>{},
    );
    final readSeq = readMsg['seq'];

    if (readSeq != null) {
      for (final m in msgs) {
        final mSeq = m['seq'];
        if (mSeq != null && mSeq is num && readSeq is num && mSeq <= readSeq) {
          m['readState'] = 'read';
        }
      }
    } else {
      // 找不到 seq 时回退到只标记单条
      final idx = msgs.indexWhere((m) => m['messageId'] == msgId);
      if (idx >= 0) {
        msgs[idx]['readState'] = 'read';
      }
    }
    notifyListeners();
  }

  void _onTypingStart(dynamic data) {
    if (data is! Map) return;
    final convId = data['conversationId']?.toString();
    if (convId == null || convId.isEmpty) return;

    _peerTyping[convId] = true;
    _typingTimers[convId]?.cancel();
    _typingTimers[convId] = Timer(const Duration(seconds: 6), () {
      _peerTyping[convId] = false;
      notifyListeners();
    });
    notifyListeners();
  }

  void _onTypingStop(dynamic data) {
    if (data is! Map) return;
    final convId = data['conversationId']?.toString();
    if (convId == null || convId.isEmpty) return;

    _typingTimers.remove(convId)?.cancel();
    _peerTyping[convId] = false;
    notifyListeners();
  }

  void _onFriendStatus(dynamic data) {
    if (data is! Map) return;
    final userId = data['userId'];
    final isOnline = data['isOnline'] == true;
    if (userId == null) return;

    var changed = false;
    for (final conv in _conversations) {
      if (conv['type'] != 1) continue;
      final target = conv['targetUser'];
      if (target is! Map<String, dynamic>) continue;
      if (target['userId'] != userId) continue;
      target['onlineStatus'] = isOnline ? 'online' : 'offline';
      changed = true;
    }

    if (changed) notifyListeners();
  }

  void _onConversationCreated(dynamic data) {
    // 有新的群会话被创建，刷新会话列表
    _debouncedLoadConversations();
  }

  void _onConversationRemoved(dynamic data) {
    if (data is! Map) return;
    final convId = data['conversationId']?.toString();
    if (convId == null) return;
    _conversations.removeWhere((c) => c['conversationId'] == convId);
    _messages.remove(convId);
    notifyListeners();
  }

  void _onMemberRemoved(dynamic data) {
    // 有成员被移除/退出，刷新会话列表以更新成员数等信息
    _debouncedLoadConversations();
  }

  void _onConversationUpdated(dynamic data) {
    if (data is! Map) return;
    final convId = data['conversationId']?.toString();
    if (convId == null) return;
    final idx = _conversations.indexWhere((c) => c['conversationId'] == convId);
    if (idx != -1) {
      if (data['name'] != null) _conversations[idx]['name'] = data['name'];
      if (data['notice'] != null) _conversations[idx]['notice'] = data['notice'];
      if (data['avatarUrl'] != null) _conversations[idx]['avatarUrl'] = data['avatarUrl'];
      notifyListeners();
    }
  }

  String _messageSearchSnippet(Map<String, dynamic> message) {
    final type = message['type'];
    final content = message['content'];

    if (type == 1) {
      if (content is Map<String, dynamic>) {
        final text = content['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
      return '[文本消息]';
    }

    const types = {
      2: '[图片消息]',
      3: '[语音消息]',
      4: '[视频消息]',
      5: '[文件消息]',
      6: '[位置消息]',
      7: '[红包消息]',
      9: '[通话记录]',
      10: '[名片]',
      11: '[相册]',
    };
    return types[type] ?? '[消息]';
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      final aPinned = a['isPinned'] == true;
      final bPinned = b['isPinned'] == true;
      if (aPinned != bPinned) return aPinned ? -1 : 1;

      final aTime = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    _updateAppBadge();
  }

  /// 更新桌面图标上的未读消息数量角标 (iOS + Android)
  void _updateAppBadge() {
    int total = 0;
    for (final conv in _conversations) {
      final unread = conv['unreadCount'];
      if (unread is int) total += unread;
    }
    try {
      final ns = NotificationService();
      if (total > 0) {
        ns.updateBadge(total);
      } else {
        ns.clearBadge();
      }
    } catch (_) {}
  }

  /// 后台轮询：获取会话列表，如果发现未读数增加，弹本地通知
  bool _polling = false;
  Future<void> pollAndNotify() async {
    if (_polling) return; // 防止重入
    _polling = true;
    try {
      // 记录轮询前每个会话的未读数
      final oldUnread = <String, int>{};
      for (final c in _conversations) {
        final id = c['conversationId']?.toString();
        if (id != null) {
          oldUnread[id] = (c['unreadCount'] as num?)?.toInt() ?? 0;
        }
      }

      // 直接从服务端获取最新会话列表（不走 loadConversations 的合并逻辑）
      final data = await api.get('/conversations', params: {'page': 1, 'pageSize': 100});
      final serverConvs = List<Map<String, dynamic>>.from(data?['list'] ?? data ?? []);

      // 对比未读数，对增加的会话弹通知
      final ns = NotificationService();
      bool hasNewMessage = false;
      for (final c in serverConvs) {
        final id = c['conversationId']?.toString();
        if (id == null || id == _currentConvId) continue;
        final newUnread = (c['unreadCount'] as num?)?.toInt() ?? 0;
        final prevUnread = oldUnread[id] ?? 0;
        if (newUnread > prevUnread) {
          hasNewMessage = true;
          final lastMsg = c['lastMessage'] as Map<String, dynamic>?;
          final convName = c['name']?.toString() ?? c['targetNickname']?.toString() ?? '新消息';
          String body = '你收到 ${newUnread - prevUnread} 条新消息';
          if (lastMsg != null) {
            final msgType = lastMsg['type'];
            switch (msgType) {
              case 2: body = '[图片]'; break;
              case 3: body = '[语音]'; break;
              case 4: body = '[视频]'; break;
              case 5: body = '[文件]'; break;
              case 9: body = '[通话记录]'; break;
              default:
                final content = lastMsg['content'];
                if (content is Map && content['text'] != null) {
                  body = content['text'].toString();
                } else if (content is String && content.isNotEmpty) {
                  body = content;
                }
            }
          }
          try {
            ns.showMessageNotification(
              senderName: convName,
              body: body,
              conversationId: id,
            );
          } catch (_) {}
        }
      }
      if (hasNewMessage) {
        try { NotificationSound.play(); } catch (_) {}
      }

      // 更新本地会话列表（取较大未读数）
      for (final sc in serverConvs) {
        final id = sc['conversationId']?.toString();
        if (id == null) continue;
        final idx = _conversations.indexWhere((c) => c['conversationId']?.toString() == id);
        if (idx >= 0) {
          final localUnread = (_conversations[idx]['unreadCount'] as num?)?.toInt() ?? 0;
          final serverUnread = (sc['unreadCount'] as num?)?.toInt() ?? 0;
          _conversations[idx]['lastMessage'] = sc['lastMessage'];
          _conversations[idx]['updatedAt'] = sc['updatedAt'];
          if (serverUnread > localUnread) {
            _conversations[idx]['unreadCount'] = serverUnread;
          }
        } else {
          _conversations.add(sc);
        }
      }
      _sortConversations();
      notifyListeners();
    } catch (e) {
      debugPrint('[ChatProvider] pollAndNotify error: $e');
    } finally {
      _polling = false;
    }
  }

  String getConvDisplayName(Map<String, dynamic> conv) {
    if (conv['type'] == 1 && conv['targetUser'] != null) {
      final remark = conv['targetUser']['remark']?.toString() ?? '';
      if (remark.isNotEmpty) return remark;
      return conv['targetUser']['nickname']?.toString() ?? '未知';
    }
    return conv['name']?.toString() ?? '群聊';
  }

  String? getConvAvatarUrl(Map<String, dynamic> conv) {
    if (conv['type'] == 1 && conv['targetUser'] != null) {
      return conv['targetUser']['avatarUrl']?.toString();
    }
    return conv['avatarUrl']?.toString();
  }

  String getLastMsgPreview(Map<String, dynamic> conv) {
    final msg = conv['lastMessage'];
    if (msg == null) return '';
    final type = msg['type'];

    if (type == 9) {
      final content = msg['content'];
      if (content is Map<String, dynamic>) {
        final text = content['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
      return '[通话记录]';
    }

    if (type != 1) {
      const types = {2: '[图片]', 3: '[语音]', 4: '[视频]', 5: '[文件]', 6: '[位置]', 7: '[红包]', 9: '[通话记录]', 10: '[名片]', 11: '[相册]'};
      return types[type] ?? '[消息]';
    }

    final content = msg['content'];
    if (content is String) {
      final text = content.trim();
      return text.isEmpty ? '[消息]' : text;
    }
    if (content is Map) {
      final text = content['text']?.toString().trim() ?? '';
      return text.isEmpty ? '[消息]' : text;
    }

    final text = content?.toString().trim() ?? '';
    return text.isEmpty ? '[消息]' : text;
  }

  @override
  void dispose() {
    socket.off('message:new');
    socket.off('message:revoked');
    socket.off('message:read');
    socket.off('typing:start');
    socket.off('typing:stop');
    socket.off('friend:status');
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
