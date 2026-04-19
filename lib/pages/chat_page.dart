import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:im_client/config/app_config.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/utils/web_file_picker.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/services/socket_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/clipboard_util.dart';
import 'package:im_client/widgets/user_avatar.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/utils/time_utils.dart';
import 'package:im_client/pages/call_page.dart';
import 'package:im_client/pages/group_settings_page.dart';
import 'package:im_client/pages/chat_user_settings_page.dart';
import 'package:im_client/pages/red_packet_detail_page.dart';
import 'package:im_client/widgets/image_gallery_page.dart';
import 'package:im_client/utils/image_saver.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String title;

  const ChatPage({super.key, required this.conversationId, required this.title});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  bool _sendingText = false;
  String _inputText = '';
  String? _lastReadMessageId;
  String? _lastAutoScrollMessageKey;
  String? _lastCallId;
  bool _typingSent = false;
  Timer? _typingStopTimer;
  bool _loadingMore = false;
  bool _hasMoreHistory = true;

  // Voice recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _recordCancelled = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  Timer? _voicePlayGuardTimer;
  StreamSubscription<void>? _voiceCompleteSub;
  StreamSubscription<PlayerState>? _voiceStateSub;
  String? _playingMessageId;
  bool _voiceMode = false;
  String _webVoiceDefaultMimeType = 'audio/webm';

  // Reply
  Map<String, dynamic>? _replyingTo;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _voiceCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      _clearVoicePlayState();
    });
    _voiceStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (_playingMessageId == null) return;
      if (state == PlayerState.stopped || state == PlayerState.completed || state == PlayerState.disposed) {
        _clearVoicePlayState();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      chat.setCurrentConv(widget.conversationId);
      chat.loadMessages(widget.conversationId).then((_) {
        if (!mounted) return;
        _scrollToBottom();
        _markLatestIncomingAsRead(chat.getMessages(widget.conversationId));
      });
    });
  }

  @override
  void deactivate() {
    // 页面离开时立即清除当前会话标记，避免新消息被自动标记已读
    try {
      context.read<ChatProvider>().setCurrentConv(null);
    } catch (_) {}
    super.deactivate();
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _recordTimer?.cancel();
    _voicePlayGuardTimer?.cancel();
    _voiceCompleteSub?.cancel();
    _voiceStateSub?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _stopTyping(force: true);
    _inputController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 滚动到顶部附近时加载更多历史消息
    if (_scrollController.hasClients &&
        _scrollController.position.pixels < 100 &&
        !_loadingMore &&
        _hasMoreHistory) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMore || !_hasMoreHistory) return;
    setState(() => _loadingMore = true);

    final chat = context.read<ChatProvider>();
    // 记住当前滚动位置和内容高度，以便加载后保持视觉位置
    final oldMaxExtent = _scrollController.position.maxScrollExtent;

    final count = await chat.loadMoreMessages(widget.conversationId);
    if (count == 0) {
      if (mounted) setState(() { _hasMoreHistory = false; _loadingMore = false; });
      return;
    }

    if (!mounted) return;
    setState(() => _loadingMore = false);

    // 等待布局完成后恢复滚动位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final newMaxExtent = _scrollController.position.maxScrollExtent;
      final diff = newMaxExtent - oldMaxExtent;
      if (diff > 0) {
        _scrollController.jumpTo(_scrollController.position.pixels + diff);
      }
    });
  }

  void _onInputChanged(String value) {
    setState(() => _inputText = value);

    final hasText = value.trim().isNotEmpty;
    if (!hasText) {
      _typingStopTimer?.cancel();
      _stopTyping(force: true);
      return;
    }

    if (!_typingSent) {
      context.read<ChatProvider>().sendTyping(widget.conversationId, true);
      _typingSent = true;
    }

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(milliseconds: 1600), () {
      _stopTyping();
    });
  }

  void _stopTyping({bool force = false}) {
    if (!force && !_typingSent) return;
    if (_typingSent || force) {
      context.read<ChatProvider>().sendTyping(widget.conversationId, false);
      _typingSent = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _messageKey(Map<String, dynamic> msg) {
    final messageId = msg['messageId']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      return 'id:$messageId';
    }

    final clientMsgId = msg['clientMsgId']?.toString();
    if (clientMsgId != null && clientMsgId.isNotEmpty) {
      return 'client:$clientMsgId';
    }

    final seq = msg['seq']?.toString() ?? '';
    final createdAt = msg['createdAt']?.toString() ?? '';
    return 'fallback:$seq:$createdAt';
  }

  void _handleMessagesUpdated(List<Map<String, dynamic>> msgs) {
    if (msgs.isEmpty) return;

    final latestKey = _messageKey(msgs.last);
    final shouldAutoScroll = latestKey != _lastAutoScrollMessageKey;
    if (shouldAutoScroll) {
      _lastAutoScrollMessageKey = latestKey;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (shouldAutoScroll) {
        _scrollToBottom();
      }
      _markLatestIncomingAsRead(msgs);
    });
  }

  String _newLocalMessageId() => 'local_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sendingText) return;

    setState(() => _sendingText = true);
    _inputController.clear();
    setState(() => _inputText = '');
    _typingStopTimer?.cancel();
    _stopTyping(force: true);

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthService>();
    final localId = _newLocalMessageId();

    // Build content with optional reply reference
    Map<String, dynamic>? replyRef;
    if (_replyingTo != null) {
      final replySender = _replyingTo!['sender'] as Map<String, dynamic>?;
      replyRef = {
        'messageId': _replyingTo!['messageId'],
        'senderNickname': replySender?['nickname'] ?? '未知',
        'type': _replyingTo!['type'],
        'preview': _getReplyPreviewText(_replyingTo!),
      };
      setState(() => _replyingTo = null);
    }

    final contentMap = <String, dynamic>{'text': text};
    if (replyRef != null) contentMap['replyTo'] = replyRef;

    chat.addPendingMessage(widget.conversationId, {
      'messageId': localId,
      'clientMsgId': localId,
      'conversationId': widget.conversationId,
      'sender': {
        'userId': auth.userId,
        'nickname': auth.nickname,
        'avatarUrl': auth.avatarUrl,
      },
      'type': 1,
      'content': contentMap,
      'status': 1,
      'sendState': 'sending',
      'readState': 'unread',
      'createdAt': DateTime.now().toIso8601String(),
    });
    _scrollToBottom();

    try {
      final result = await chat.sendMessage(
        widget.conversationId,
        type: 1,
        content: contentMap,
        clientMsgId: localId,
      );

      chat.markPendingMessageSent(
        widget.conversationId,
        localId,
        result,
        content: contentMap,
      );
      _scrollToBottom();
    } catch (e) {
      chat.markPendingMessageFailed(widget.conversationId, localId);
      if (mounted) {
        final message = ErrorMessage.from(e, fallback: '发送失败，请稍后重试');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：$message'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingText = false);
    }
  }

  Future<void> _showAttachSheet() async {
    // Show a bottom sheet to let user choose image or video
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('选择图片'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('选择视频'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (kIsWeb) {
      await _pickAndSendWeb(choice);
    } else {
      await _pickAndSendNative(choice);
    }
  }

  /// Web: use native HTML FileReader (bypasses blob URL / XHR issues)
  Future<void> _pickAndSendWeb(String choice) async {
    if (choice == 'video') {
      final picked = await pickVideoFromWeb();
      if (picked == null || !mounted) return;

      if (picked.bytes.length > 200 * 1024 * 1024) {
        AppToast.show(context, '视频 ${picked.name} 超过200MB限制');
        return;
      }

      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _MediaPreviewPage(
            files: [XFile('', name: picked.name, mimeType: picked.mimeType)],
            bytesData: [picked.bytes],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;

      await _sendMediaMessageFromBytes(picked.name, picked.mimeType, picked.bytes, isVideo: true);
    } else {
      final pickedList = await pickImagesFromWeb(maxCount: 9);
      if (pickedList.isEmpty || !mounted) return;

      if (pickedList.length > 9) {
        AppToast.show(context, '最多选择9个文件');
        return;
      }

      final xfiles = pickedList.map((p) => XFile('', name: p.name, mimeType: p.mimeType)).toList();
      final allBytes = pickedList.map((p) => p.bytes).toList();

      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _MediaPreviewPage(files: xfiles, bytesData: allBytes),
        ),
      );
      if (confirmed != true || !mounted) return;

      if (pickedList.length == 1) {
        final p = pickedList.first;
        await _sendMediaMessageFromBytes(p.name, p.mimeType, p.bytes, isVideo: false);
      } else {
        await _sendMediaAlbum(xfiles, allBytes);
      }
    }
  }

  /// Non-web: use image_picker
  Future<void> _pickAndSendNative(String choice) async {
    List<XFile> files;
    if (choice == 'video') {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      files = file != null ? [file] : [];
    } else {
      try {
        files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1920);
      } catch (_) {
        final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1920);
        files = file != null ? [file] : [];
      }
    }
    if (files.isEmpty || !mounted) return;

    if (files.length > 9) {
      AppToast.show(context, '最多选择9个文件');
      return;
    }

    // Read all bytes eagerly
    final allBytes = <Uint8List>[];
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        allBytes.add(bytes);
      } catch (e) {
        debugPrint('readAsBytes failed for ${file.name}: $e');
        if (mounted) AppToast.show(context, '读取文件失败，请重试');
        return;
      }
    }
    if (!mounted) return;

    // Check video size limit (200MB)
    for (var i = 0; i < files.length; i++) {
      final mime = files[i].mimeType ?? _guessMimeType(files[i].name, choice == 'video');
      if (mime.startsWith('video') && allBytes[i].length > 200 * 1024 * 1024) {
        if (mounted) AppToast.show(context, '视频 ${files[i].name} 超过200MB限制');
        return;
      }
    }

    // Show preview before sending
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _MediaPreviewPage(files: files, bytesData: allBytes),
      ),
    );
    if (confirmed != true || !mounted) return;

    if (files.length == 1) {
      final file = files.first;
      final mime = file.mimeType ?? _guessMimeType(file.name, choice == 'video');
      final isVideo = mime.startsWith('video');
      await _sendMediaMessageFromBytes(file.name, mime, allBytes.first, isVideo: isVideo);
    } else {
      await _sendMediaAlbum(files, allBytes);
    }
  }

  Future<void> _sendMediaAlbum(List<XFile> files, List<Uint8List> allBytes) async {
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthService>();
    final api = context.read<ApiClient>();

    final localId = _newLocalMessageId();

    // Build local preview items with bytes
    final localItems = <Map<String, dynamic>>[];
    for (var i = 0; i < files.length; i++) {
      final mime = files[i].mimeType ?? _guessMimeType(files[i].name, false);
      localItems.add({
        'localBytes': allBytes[i],
        'name': files[i].name,
        'mimeType': mime,
        'mediaType': mime.startsWith('video') ? 'video' : 'image',
      });
    }

    chat.addPendingMessage(widget.conversationId, {
      'messageId': localId,
      'clientMsgId': localId,
      'conversationId': widget.conversationId,
      'sender': {
        'userId': auth.userId,
        'nickname': auth.nickname,
        'avatarUrl': auth.avatarUrl,
      },
      'type': 11,
      'content': {'items': localItems, 'uploading': true, 'uploadProgress': 0.0},
      'status': 1,
      'sendState': 'sending',
      'readState': 'unread',
      'createdAt': DateTime.now().toIso8601String(),
    });
    _scrollToBottom();

    // Upload in background
    _doUploadAlbum(localId, files, allBytes, api: api, chat: chat);
  }

  Future<void> _doUploadAlbum(String localId, List<XFile> files, List<Uint8List> allBytes, {required ApiClient api, required ChatProvider chat}) async {
    try {
      final items = <Map<String, dynamic>>[];
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final bytes = allBytes[i];
        final mime = file.mimeType ?? _guessMimeType(file.name, false);
        final isVideo = mime.startsWith('video');
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: file.name, contentType: MediaType.parse(mime)),
        });
        final uploadData = Map<String, dynamic>.from(await api.upload('/upload', formData, onSendProgress: (sent, total) {
          if (total > 0) {
            final fileProgress = sent / total;
            final overallProgress = (i + fileProgress) / files.length;
            chat.updatePendingMessageProgress(widget.conversationId, localId, overallProgress);
          }
        }));
        items.add({
          'url': uploadData['url'],
          'name': uploadData['originalName'] ?? file.name,
          'size': uploadData['size'] ?? bytes.length,
          'mimeType': uploadData['mimeType'] ?? mime,
          'mediaType': isVideo ? 'video' : 'image',
        });
      }

      final messageContent = {'items': items};
      final result = await chat.sendMessage(
        widget.conversationId,
        type: 11,
        content: messageContent,
        clientMsgId: localId,
      );

      chat.markPendingMessageSent(widget.conversationId, localId, result, content: messageContent);
      if (mounted) _scrollToBottom();
    } catch (e) {
      // Store retry info
      final msgs = chat.getMessages(widget.conversationId);
      final idx = msgs.indexWhere((m) => m['messageId'] == localId);
      if (idx >= 0) {
        final content = msgs[idx]['content'];
        if (content is Map<String, dynamic>) {
          content['uploading'] = false;
          content['retryFiles'] = files;
          content['retryAllBytes'] = allBytes;
        }
      }
      chat.markPendingMessageFailed(widget.conversationId, localId);
    }
  }

  Future<void> _sendMediaMessageFromBytes(String fileName, String mimeType, Uint8List bytes, {required bool isVideo}) async {
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthService>();
    final api = context.read<ApiClient>();

    final localId = _newLocalMessageId();

    // Store local bytes for instant preview
    chat.addPendingMessage(widget.conversationId, {
      'messageId': localId,
      'clientMsgId': localId,
      'conversationId': widget.conversationId,
      'sender': {
        'userId': auth.userId,
        'nickname': auth.nickname,
        'avatarUrl': auth.avatarUrl,
      },
      'type': isVideo ? 4 : 2,
      'content': {
        'url': '',
        'name': fileName,
        'mimeType': mimeType,
        'uploading': true,
        'uploadProgress': 0.0,
        'localBytes': bytes,
      },
      'status': 1,
      'sendState': 'sending',
      'readState': 'unread',
      'createdAt': DateTime.now().toIso8601String(),
    });
    _scrollToBottom();

    // Upload in background — don't await in caller
    _doUploadAndSend(localId, fileName, mimeType, bytes, isVideo: isVideo, api: api, chat: chat);
  }

  Future<void> _doUploadAndSend(String localId, String fileName, String mimeType, Uint8List bytes, {required bool isVideo, required ApiClient api, required ChatProvider chat}) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        ),
      });

      final uploadData = Map<String, dynamic>.from(await api.upload('/upload', formData, onSendProgress: (sent, total) {
        if (total > 0) {
          chat.updatePendingMessageProgress(widget.conversationId, localId, sent / total);
        }
      }));

      final messageContent = {
        'url': uploadData['url'],
        'name': uploadData['originalName'] ?? fileName,
        'size': uploadData['size'] ?? bytes.length,
        'mimeType': uploadData['mimeType'] ?? mimeType,
      };

      final result = await chat.sendMessage(
        widget.conversationId,
        type: isVideo ? 4 : 2,
        content: messageContent,
        clientMsgId: localId,
      );

      chat.markPendingMessageSent(
        widget.conversationId,
        localId,
        result,
        content: messageContent,
      );
      if (mounted) _scrollToBottom();
    } catch (e) {
      // Store retry info for failed messages
      final msgs = chat.getMessages(widget.conversationId);
      final idx = msgs.indexWhere((m) => m['messageId'] == localId);
      if (idx >= 0) {
        final content = msgs[idx]['content'];
        if (content is Map<String, dynamic>) {
          content['uploading'] = false;
          content['localBytes'] = bytes;
          content['retryFileName'] = fileName;
          content['retryMimeType'] = mimeType;
          content['retryIsVideo'] = isVideo;
        }
      }
      chat.markPendingMessageFailed(widget.conversationId, localId);
    }
  }

  void _retryMediaSend(Map<String, dynamic> msg) {
    final content = msg['content'];
    if (content is! Map<String, dynamic>) return;
    final bytes = content['localBytes'] as Uint8List?;
    final fileName = content['retryFileName']?.toString() ?? 'file';
    final mimeType = content['retryMimeType']?.toString() ?? 'image/jpeg';
    final isVideo = content['retryIsVideo'] == true;

    if (bytes == null) {
      if (mounted) AppToast.show(context, '文件数据已丢失，请重新选择');
      return;
    }

    final chat = context.read<ChatProvider>();
    final api = context.read<ApiClient>();
    final localId = msg['messageId']?.toString();
    if (localId == null) return;

    // Reset state
    content['uploading'] = true;
    content['uploadProgress'] = 0.0;
    msg['sendState'] = 'sending';
    chat.notifyListeners();

    _doUploadAndSend(localId, fileName, mimeType, bytes, isVideo: isVideo, api: api, chat: chat);
  }

  Future<void> _sendMediaMessage(XFile file, {required bool isVideo}) async {
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthService>();
    final api = context.read<ApiClient>();

    final localId = _newLocalMessageId();
    final mimeType = file.mimeType ?? _guessMimeType(file.name, isVideo);

    chat.addPendingMessage(widget.conversationId, {
      'messageId': localId,
      'clientMsgId': localId,
      'conversationId': widget.conversationId,
      'sender': {
        'userId': auth.userId,
        'nickname': auth.nickname,
        'avatarUrl': auth.avatarUrl,
      },
      'type': isVideo ? 4 : 2,
      'content': {
        'url': '',
        'name': file.name,
        'mimeType': mimeType,
        'uploading': true,
      },
      'status': 1,
      'sendState': 'sending',
      'readState': 'unread',
      'createdAt': DateTime.now().toIso8601String(),
    });
    _scrollToBottom();

    try {
      final bytes = await file.readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: MediaType.parse(mimeType),
        ),
      });

      final uploadData = Map<String, dynamic>.from(await api.upload('/upload', formData));
      final messageContent = {
        'url': uploadData['url'],
        'name': uploadData['originalName'] ?? file.name,
        'size': uploadData['size'] ?? bytes.length,
        'mimeType': uploadData['mimeType'] ?? mimeType,
      };

      final result = await chat.sendMessage(
        widget.conversationId,
        type: isVideo ? 4 : 2,
        content: messageContent,
        clientMsgId: localId,
      );

      chat.markPendingMessageSent(
        widget.conversationId,
        localId,
        result,
        content: messageContent,
      );
      _scrollToBottom();
    } catch (e) {
      chat.markPendingMessageFailed(widget.conversationId, localId);
      if (mounted) {
        final message = ErrorMessage.from(e, fallback: '发送失败，请稍后重试');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：$message'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  String _guessMimeType(String fileName, bool isVideo) {
    final lower = fileName.toLowerCase();
    // Always check video extensions first (iOS image_picker may return null mimeType)
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (isVideo) return 'video/mp4';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  // ——— Voice recording ———

  Future<void> _startRecording() async {
    if (_isRecording) return;
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) AppToast.show(context, '麦克风权限未授予');
      return;
    }
    if (kIsWeb) {
      final webEncoder = await _pickWebVoiceEncoder();
      await _audioRecorder.start(RecordConfig(encoder: webEncoder), path: '');
    } else {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: filePath);
    }
    setState(() {
      _isRecording = true;
      _recordCancelled = false;
      _recordSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordSeconds++);
      if (_recordSeconds >= 60) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    if (!_isRecording) return;
    final path = await _audioRecorder.stop();
    final seconds = _recordSeconds;
    setState(() => _isRecording = false);

    if (_recordCancelled || path == null || seconds < 1) return;
    await _sendVoiceMessage(path, seconds);
  }

  void _cancelRecording() {
    _recordCancelled = true;
    _stopRecording();
  }

  Future<void> _sendVoiceMessage(String filePath, int duration) async {
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthService>();
    final api = context.read<ApiClient>();

    final localId = _newLocalMessageId();
    chat.addPendingMessage(widget.conversationId, {
      'messageId': localId,
      'clientMsgId': localId,
      'conversationId': widget.conversationId,
      'sender': {'userId': auth.userId, 'nickname': auth.nickname, 'avatarUrl': auth.avatarUrl},
      'type': 3,
      'content': {'url': '', 'duration': duration},
      'status': 1,
      'sendState': 'sending',
      'readState': 'unread',
      'createdAt': DateTime.now().toIso8601String(),
    });
    _scrollToBottom();

    try {
      Uint8List bytes;
      String filename;
      String mimeType;

      if (kIsWeb) {
        final defaultMimeType = _webVoiceDefaultMimeType;
        final webData = await readBinaryFromWebUrl(
          filePath,
          defaultName: _voiceFileNameByMime(defaultMimeType),
          defaultMimeType: defaultMimeType,
        );
        if (webData == null || webData.bytes.isEmpty) {
          throw const AppException('无法读取录音数据');
        }
        bytes = webData.bytes;
        mimeType = _normalizeVoiceMimeType(webData.mimeType);
        filename = _voiceFileNameByMime(mimeType);
      } else {
        bytes = await File(filePath).readAsBytes();
        filename = 'voice.m4a';
        mimeType = 'audio/mp4';
      }

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: MediaType.parse(mimeType)),
      });
      final uploadData = Map<String, dynamic>.from(await api.upload('/upload', formData));
      final content = {'url': uploadData['url'], 'duration': duration};

      final result = await chat.sendMessage(widget.conversationId, type: 3, content: content, clientMsgId: localId);
      chat.markPendingMessageSent(widget.conversationId, localId, result, content: content);
    } catch (e) {
      chat.markPendingMessageFailed(widget.conversationId, localId);
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '语音发送失败'));
    }
  }

  Future<AudioEncoder> _pickWebVoiceEncoder() async {
    const candidates = <AudioEncoder>[
      AudioEncoder.aacLc,
      AudioEncoder.aacHe,
      AudioEncoder.aacEld,
      AudioEncoder.opus,
    ];

    for (final encoder in candidates) {
      try {
        final supported = await _audioRecorder.isEncoderSupported(encoder);
        if (!supported) continue;
        _webVoiceDefaultMimeType = _defaultWebMimeByEncoder(encoder);
        return encoder;
      } catch (_) {
        // Ignore and try next encoder.
      }
    }

    _webVoiceDefaultMimeType = 'audio/webm';
    return AudioEncoder.opus;
  }

  String _defaultWebMimeByEncoder(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacHe:
      case AudioEncoder.aacEld:
        return 'audio/mp4';
      case AudioEncoder.opus:
      default:
        return 'audio/webm';
    }
  }

  String _normalizeVoiceMimeType(String mimeType) {
    final lower = mimeType.toLowerCase();
    if (lower.contains('webm')) return 'audio/webm';
    if (lower.contains('opus')) return 'audio/webm';
    if (lower.contains('ogg')) return 'audio/ogg';
    if (lower.contains('mpeg') || lower.contains('mp3')) return 'audio/mpeg';
    if (lower.contains('mp4') || lower.contains('m4a') || lower.contains('aac')) {
      return 'audio/mp4';
    }
    return 'audio/webm';
  }

  String _voiceFileNameByMime(String mimeType) {
    switch (mimeType) {
      case 'audio/ogg':
        return 'voice.ogg';
      case 'audio/mpeg':
        return 'voice.mp3';
      case 'audio/mp4':
        return 'voice.m4a';
      case 'audio/webm':
      default:
        return 'voice.webm';
    }
  }

  Future<void> _togglePlayVoice(String? url, String messageId, {int duration = 0}) async {
    if (url == null || url.isEmpty) return;
    final resolvedUrl = AppConfig.resolveFileUrl(url);
    if (resolvedUrl.isEmpty) return;

    if (_playingMessageId == messageId) {
      await _audioPlayer.stop();
      _clearVoicePlayState();
      return;
    }

    await _audioPlayer.stop();
    setState(() => _playingMessageId = messageId);

    _voicePlayGuardTimer?.cancel();
    final guardSeconds = (duration > 0 ? duration + 3 : 20).clamp(8, 75);
    _voicePlayGuardTimer = Timer(Duration(seconds: guardSeconds), () {
      if (_playingMessageId != messageId) return;
      _audioPlayer.stop();
      _clearVoicePlayState();
    });

    try {
      if (kIsWeb) {
        await _audioPlayer.play(UrlSource(resolvedUrl));
      } else {
        // 移动端：先下载到本地再播放，避免 Content-Type 不兼容
        final localPath = await _downloadVoiceToTemp(resolvedUrl, messageId);
        await _audioPlayer.play(DeviceFileSource(localPath));
      }
    } catch (e) {
      _clearVoicePlayState();
      if (mounted) {
        final fallback = kIsWeb ? '当前浏览器暂不支持该语音格式' : '语音播放失败，格式可能不兼容';
        AppToast.show(context, ErrorMessage.from(e, fallback: fallback));        
      }
    }
  }

  /// 下载语音到临时目录并返回本地路径（带缓存）
  Future<String> _downloadVoiceToTemp(String url, String messageId) async {
    final dir = await getTemporaryDirectory();
    final uri = Uri.parse(url);
    final ext = uri.path.contains('.') ? uri.path.substring(uri.path.lastIndexOf('.')) : '.m4a';
    final file = File('${dir.path}/voice_cache_$messageId$ext');
    if (await file.exists() && (await file.length()) > 0) {
      return file.path;
    }
    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    await file.writeAsBytes(response.data!);
    return file.path;
  }

  void _clearVoicePlayState() {
    _voicePlayGuardTimer?.cancel();
    if (!mounted) {
      _playingMessageId = null;
      return;
    }
    if (_playingMessageId != null) {
      setState(() => _playingMessageId = null);
    }
  }

  void _markLatestIncomingAsRead(List<Map<String, dynamic>> msgs) {
    if (msgs.isEmpty) return;
    final myUserId = context.read<AuthService>().userId;

    for (int i = msgs.length - 1; i >= 0; i--) {
      final msg = msgs[i];
      final sender = msg['sender'] as Map<String, dynamic>?;
      final senderId = sender?['userId'];
      final msgId = msg['messageId']?.toString();

      if (msgId != null && senderId != null && senderId != myUserId) {
        if (_lastReadMessageId == msgId) return;
        _lastReadMessageId = msgId;
        context.read<ChatProvider>().markMessageRead(widget.conversationId, msgId);
        return;
      }
    }
  }

  Map<String, dynamic>? _findCurrentConversation(ChatProvider chat) {
    for (final conv in chat.conversations) {
      if (conv['conversationId']?.toString() == widget.conversationId) {
        return conv;
      }
    }
    return null;
  }

  String _buildHeaderPrimaryTitle(Map<String, dynamic>? conv) {
    if (conv == null) return widget.title;
    if (conv['type'] != 1) {
      final name = conv['name']?.toString().trim() ?? '';
      return name.isNotEmpty ? name : widget.title;
    }

    final target = conv['targetUser'];
    if (target is! Map<String, dynamic>) return widget.title;

    final nickname = (target['nickname']?.toString().trim().isNotEmpty ?? false)
        ? target['nickname'].toString().trim()
        : widget.title;
    final remark = target['remark']?.toString().trim() ?? '';
    if (remark.isEmpty) return nickname;
    return '$nickname($remark)';
  }

  String _buildHeaderSecondaryTitle(ChatProvider chat, Map<String, dynamic>? conv) {
    if (chat.isPeerTyping(widget.conversationId)) {
      return '对方正在输入中...';
    }
    if (conv == null) return '离线';
    if (conv['type'] != 1) return '群聊';
    return chat.isConversationOnline(conv) ? '在线' : '离线';
  }

  void _showGroupMenu(BuildContext ctx) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => GroupSettingsPage(conversationId: widget.conversationId),
      ),
    ).then((_) {
      if (mounted) {
        context.read<ChatProvider>().loadConversations();
      }
    });
  }

  void _onTapTitle(Map<String, dynamic>? conv) {
    if (conv == null) return;
    if (conv['type'] != 1) {
      // Group chat
      _showGroupMenu(context);
      return;
    }
    // Private chat — open user settings
    final target = conv['targetUser'];
    if (target is! Map<String, dynamic>) return;
    final targetUserId = target['userId'];
    if (targetUserId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatUserSettingsPage(
          targetUserId: targetUserId is int ? targetUserId : int.tryParse(targetUserId.toString()) ?? 0,
          conversationId: widget.conversationId,
        ),
      ),
    ).then((_) {
      if (mounted) {
        context.read<ChatProvider>().loadConversations();
      }
    });
  }

  Future<void> _onTapVoiceCall() async {
    final chat = context.read<ChatProvider>();
    final conv = _findCurrentConversation(chat);
    final target = conv?['targetUser'];

    if (conv == null || conv['type'] != 1 || target is! Map<String, dynamic>) {
      AppToast.show(context, '当前仅支持单聊通话');
      return;
    }

    final callType = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                '选择通话方式',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF0066FF).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.phone_outlined, color: Color(0xFF0066FF), size: 22),
                ),
                title: const Text('语音通话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                subtitle: const Text('仅语音，流量消耗更少', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                onTap: () => Navigator.pop(ctx, 'voice'),
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF0066FF).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.videocam_outlined, color: Color(0xFF0066FF), size: 22),
                ),
                title: const Text('视频通话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                subtitle: const Text('面对面视频，默认打开摄像头', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (callType == null || !mounted) return;
    await _startCall(conv, callType);
  }

  Future<void> _startCall(Map<String, dynamic> conv, String callType) async {
    final target = conv['targetUser'] as Map<String, dynamic>;
    final targetRaw = target['userId'];
    final targetUserId = targetRaw is int ? targetRaw : int.tryParse(targetRaw?.toString() ?? '');

    if (targetUserId == null) {
      AppToast.show(context, '对方用户信息异常，无法拨打');
      return;
    }

    final displayName = _buildHeaderPrimaryTitle(conv);

    try {
      final api = context.read<ApiClient>();
      final socket = context.read<SocketService>();
      final result = Map<String, dynamic>.from(await api.post('/calls', data: {
        'targetUserId': targetUserId,
        'callType': callType,
        'conversationId': widget.conversationId,
      }));

      final callId = result['callId']?.toString();
      _lastCallId = callId;
      if (callId == null || callId.isEmpty) {
        if (mounted) AppToast.show(context, '拨号失败，请稍后重试');
        return;
      }

      final rtcConfigRaw = result['rtcConfig'];
      final rtcConfig = rtcConfigRaw is Map
          ? Map<String, dynamic>.from(rtcConfigRaw)
          : <String, dynamic>{};

      socket.emit('call:invite', {
        'callId': callId,
        'targetUserId': targetUserId,
        'callType': callType,
      });

      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (context, animation, secondaryAnimation) => CallPage(
            callId: callId,
            peerUserId: targetUserId,
            peerName: displayName,
            peerAvatarUrl: target['avatarUrl']?.toString(),
            callType: callType,
            isCaller: true,
            rtcConfig: rtcConfig,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      // 如果已成功创建通话但后续步骤失败，主动清理占线状态
      if (_lastCallId != null) {
        try {
          final cleanupApi = mounted ? context.read<ApiClient>() : null;
          await cleanupApi?.post('/calls/$_lastCallId/hangup');
        } catch (_) {}
        _lastCallId = null;
      }
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '拨打失败，请稍后重试'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leadingWidth: 44,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Consumer<ChatProvider>(
          builder: (context, chat, _) {
            final conv = _findCurrentConversation(chat);
            final title = _buildHeaderPrimaryTitle(conv);
            final subtitle = _buildHeaderSecondaryTitle(chat, conv);
            final isTyping = subtitle == '对方正在输入中...';
            final isPrivate = conv != null && conv['type'] == 1;
            final isOnline = conv != null && chat.isConversationOnline(conv);
            final isDisturb = conv?['isDisturb'] == true;

            return GestureDetector(
              onTap: () => _onTapTitle(conv),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isDisturb)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.notifications_off_outlined, size: 16, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    if (isTyping)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppColors.primary),
                      )
                    else if (isPrivate)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF34C759) : const Color(0xFFC7C7CC),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      )
                    else
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          Consumer<ChatProvider>(
            builder: (context, chat, _) {
              final conv = _findCurrentConversation(chat);
              final isGroup = conv != null && conv['type'] != 1;
              if (isGroup) {
                return IconButton(
                  icon: const Icon(Icons.more_vert, size: 24),
                  onPressed: () => _showGroupMenu(context),
                );
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.phone_outlined), onPressed: _onTapVoiceCall),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 24),
                    onPressed: () => _onTapTitle(conv),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: AppColors.bgContent,
          child: Column(
            children: [
              // Messages
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chat, _) {
                  final msgs = chat.getMessages(widget.conversationId);
                  final conv = _findCurrentConversation(chat);
                  final notice = (conv?['type'] == 2) ? (conv?['notice']?.toString() ?? '') : '';

                  if (msgs.isEmpty && notice.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          Text('暂无消息', style: TextStyle(color: Colors.grey[400])),
                        ],
                      ),
                    );
                  }

                  _handleMessagesUpdated(msgs);

                  final headerCount = (_loadingMore || !_hasMoreHistory ? 1 : 0) + (notice.isNotEmpty ? 1 : 0);
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: msgs.length + headerCount,
                    itemBuilder: (context, index) {
                      // 加载更多指示器
                      if (index == 0 && (_loadingMore || !_hasMoreHistory)) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: _loadingMore
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text('没有更多消息了', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                          ),
                        );
                      }
                      final adjustedIndex = index - (_loadingMore || !_hasMoreHistory ? 1 : 0);
                      if (notice.isNotEmpty && adjustedIndex == 0) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF9E6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.campaign_rounded, size: 16, color: Color(0xFFE6A800)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notice,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF8B7500)),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final msgIndex = adjustedIndex - (notice.isNotEmpty ? 1 : 0);
                      return _buildMessage(context, msgs, msgIndex);
                    },
                  );
                },
              ),
            ),
            // Input bar
            _buildReplyPreview(),
            _buildInputBar(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMessage(BuildContext context, List<Map<String, dynamic>> msgs, int index) {
    final msg = msgs[index];
    final userId = context.read<AuthService>().userId;
    final sender = msg['sender'] as Map<String, dynamic>?;
    final isSelf = sender?['userId'] == userId;
    final senderName = sender?['nickname'] ?? '未知';
    final senderAvatar = sender?['avatarUrl'];
    final status = msg['status'];

    // Time divider
    Widget? timeDivider;
    if (index == 0 || _shouldShowTime(msgs, index)) {
      timeDivider = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(formatMsgTime(msg['createdAt']?.toString()), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
        ),
      );
    }

    // Revoked message
    if (status == 2 || status == 0) {
      return Column(
        children: [
          ?timeDivider,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Text('${isSelf ? "你" : senderName}撤回了一条消息', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
        ],
      );
    }

    // Call record system message
    if (msg['type'] == 9) {
      return Column(
        children: [
          ?timeDivider,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildCallRecordMessage(msg),
          ),
        ],
      );
    }

    // Message content
    // 将 content 中的 JSON 字符串解析为 Map（兼容服务端返回字符串的情况）
    _ensureContentParsed(msg);
    final content = _getMsgContent(msg);
    final msgType = _intType(msg['type']);
    // 图片、视频、相册不需要气泡背景和内边距
    final isMediaType = msgType == 2 || msgType == 4 || msgType == 11;

    return Column(
      children: [
        ?timeDivider,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isSelf) ...[
                UserAvatar(name: senderName, url: senderAvatar, size: 36, radius: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPressStart: (details) => _showMsgMenu(msg, isSelf, details.globalPosition),
                      child: Container(
                        padding: isMediaType
                            ? EdgeInsets.zero
                            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: isMediaType
                            ? null
                            : BoxDecoration(
                                color: isSelf ? AppColors.bubbleSelf : AppColors.bubbleOther,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: Radius.circular(isSelf ? 12 : 4),
                                  bottomRight: Radius.circular(isSelf ? 4 : 12),
                                ),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1)),
                                ],
                              ),
                        child: _buildMsgContentWithReply(msg, content),
                      ),
                    ),
                    if (isSelf)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 2),
                        child: _buildSelfStatus(msg),
                      ),
                  ],
                ),
              ),
              if (isSelf) ...[
                const SizedBox(width: 8),
                UserAvatar(name: senderName, url: senderAvatar, size: 36, radius: 18),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 将 type 安全转为 int（兼容服务端返回 String 的情况）
  int _intType(dynamic type) {
    if (type is int) return type;
    if (type is num) return type.toInt();
    if (type is String) return int.tryParse(type) ?? 0;
    return 0;
  }

  /// 确保 msg['content'] 是 Map（服务端有时返回 JSON 字符串）
  void _ensureContentParsed(Map<String, dynamic> msg) {
    final content = msg['content'];
    if (content is String && content.startsWith('{')) {
      try {
        msg['content'] = Map<String, dynamic>.from(
          json.decode(content) as Map,
        );
      } catch (_) {}
    }
  }

  Widget _getMsgContent(Map<String, dynamic> msg) {
    final type = _intType(msg['type']);
    if (type == 1) {
      final content = msg['content'];
      String text;
      if (content is String) {
        text = content;
      } else if (content is Map) {
        text = content['text']?.toString() ?? '';
      } else {
        text = content?.toString() ?? '';
      }
      return Text(text, style: const TextStyle(fontSize: 15, height: 1.4));
    }

    if (type == 2) {
      return _buildImageContent(msg);
    }

    if (type == 3) {
      return _buildVoiceContent(msg);
    }

    if (type == 4) {
      return _buildVideoContent(msg);
    }

    if (type == 5) {
      return _buildFileContent(msg);
    }

    if (type == 7) {
      return _buildRedPacketContent(msg);
    }

    if (type == 6) {
      return _buildLocationContent(msg);
    }

    if (type == 9) {
      return _buildCallRecordContent(msg);
    }

    if (type == 10) {
      return _buildContactCardContent(msg);
    }

    if (type == 11) {
      return _buildMediaAlbumContent(msg);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.chat, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text('[消息]', style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildLocationContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    String name = '位置';
    String address = '';
    if (content is Map<String, dynamic>) {
      name = content['name']?.toString() ?? '位置';
      address = content['address']?.toString() ?? '';
    }
    return Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 6),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(address, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Icon(Icons.map, size: 36, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallRecordContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    String text = '[通话记录]';
    String callType = 'voice';
    if (content is Map<String, dynamic>) {
      text = content['text']?.toString() ?? '[通话记录]';
      callType = content['callType']?.toString() ?? 'voice';
    } else if (content is String) {
      text = content;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          callType == 'video' ? Icons.videocam_outlined : Icons.phone_outlined,
          size: 18,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildVoiceContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    final messageId = msg['messageId']?.toString() ?? '';
    int duration = 0;
    String? url;
    if (content is Map) {
      duration = int.tryParse(content['duration']?.toString() ?? '0') ?? 0;
      url = content['url']?.toString();
    }
    final isPlaying = _playingMessageId == messageId;
    final width = 80.0 + (duration.clamp(0, 30)) * 4.0;

    return GestureDetector(
      onTap: () => _togglePlayVoice(url, messageId, duration: duration),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              size: 28,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Waveform placeholder
                  Row(
                    children: List.generate(
                      (duration.clamp(1, 15)),
                      (i) => Container(
                        width: 3,
                        height: 6.0 + (i % 3) * 4.0,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: isPlaying ? AppColors.primary : AppColors.textSecondary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text('$duration″', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    String name = '[文件]';
    String? url;
    int size = 0;
    if (content is Map) {
      name = content['name']?.toString() ?? '[文件]';
      url = content['url']?.toString();
      size = int.tryParse(content['size']?.toString() ?? '0') ?? 0;
    }

    String sizeStr;
    if (size > 1024 * 1024) {
      sizeStr = '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (size > 1024) {
      sizeStr = '${(size / 1024).toStringAsFixed(0)} KB';
    } else {
      sizeStr = '$size B';
    }

    return GestureDetector(
      onTap: () {
        final resolved = AppConfig.resolveFileUrl(url);
        if (resolved.isNotEmpty) {
          launchUrl(Uri.parse(resolved), mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.insert_drive_file, size: 36, color: Color(0xFF42A5F5)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(sizeStr, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRedPacketContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    String greeting = '恭喜发财，大吉大利';
    String? redPacketId;
    if (content is Map) {
      final g = content['greeting']?.toString().trim();
      if (g != null && g.isNotEmpty) greeting = g;
      redPacketId = content['redPacketId']?.toString();
    }

    return GestureDetector(
      onTap: () {
        if (redPacketId != null && redPacketId.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RedPacketDetailPage(redPacketId: redPacketId!)),
          );
        }
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFA5252), Color(0xFFE03131)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.redeem, color: Color(0xFFFFD43B), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    greeting,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
              ),
              child: const Text(
                '内部通红包',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCardContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    String nickname = '未知';
    String uid = '';
    String? avatarUrl;
    int? cardUserId;
    if (content is Map<String, dynamic>) {
      nickname = content['nickname']?.toString() ?? '未知';
      uid = content['uid']?.toString() ?? '';
      avatarUrl = content['avatarUrl']?.toString();
      cardUserId = content['userId'] is int ? content['userId'] : int.tryParse(content['userId']?.toString() ?? '');
    }

    return GestureDetector(
      onTap: () {
        if (cardUserId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _ContactCardProfilePage(userId: cardUserId!, nickname: nickname, avatarUrl: avatarUrl, uid: uid),
            ),
          );
        }
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(name: nickname, url: avatarUrl, size: 40, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nickname, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (uid.isNotEmpty)
                        Text('UID: $uid', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
              ),
              child: const Text('个人名片', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaAlbumContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    final sendState = msg['sendState'];
    final uploadProgress = content is Map<String, dynamic> ? (content['uploadProgress'] as num?)?.toDouble() ?? 0.0 : 0.0;
    List<Map<String, dynamic>> items = [];
    if (content is Map<String, dynamic>) {
      final rawItems = content['items'];
      if (rawItems is List) {
        items = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }

    // Local preview during upload - items have localBytes
    final hasLocalBytes = items.isNotEmpty && items.first.containsKey('localBytes');

    if (sendState == 'sending' && items.isEmpty) {
      return _buildMediaHint('相册发送中...');
    }
    if (sendState == 'failed' && !hasLocalBytes) {
      return _buildMediaHint('相册发送失败', isError: true);
    }
    if (items.isEmpty) {
      return _buildMediaHint('[相册]');
    }

    final count = items.length;
    final crossAxisCount = count <= 1 ? 1 : (count <= 4 ? 2 : 3);
    final gridWidth = crossAxisCount == 1 ? 180.0 : (crossAxisCount == 2 ? 200.0 : 240.0);

    return GestureDetector(
      onTap: sendState == 'failed' && hasLocalBytes ? () => _retryAlbumSend(msg) : null,
      child: SizedBox(
        width: gridWidth,
        child: Stack(
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: count,
              itemBuilder: (_, i) {
                final item = items[i];
                final url = AppConfig.resolveFileUrl(item['url']?.toString());
                final isVideo = item['mediaType'] == 'video';
                final localBytes = item['localBytes'] as Uint8List?;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (localBytes != null && url.isEmpty)
                        Image.memory(localBytes, fit: BoxFit.cover)
                      else
                        GestureDetector(
                          onTap: () {
                            if (url.isEmpty) return;
                            if (isVideo) {
                              _openVideoPreview(url);
                            } else {
                              _openImagePreview(url);
                            }
                          },
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFE0E0E0),
                              child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary, size: 24),
                            ),
                          ),
                        ),
                      if (isVideo)
                        const Center(
                          child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
                        ),
                    ],
                  ),
                );
              },
            ),
            // Overall progress overlay
            if (sendState == 'sending' && hasLocalBytes)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 40, height: 40,
                        child: CircularProgressIndicator(
                          value: uploadProgress > 0 ? uploadProgress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                      if (uploadProgress > 0) ...[
                        const SizedBox(height: 6),
                        Text('${(uploadProgress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
            // Retry overlay
            if (sendState == 'failed' && hasLocalBytes)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, color: Colors.white, size: 32),
                        SizedBox(height: 4),
                        Text('点击重试', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _retryAlbumSend(Map<String, dynamic> msg) {
    final content = msg['content'];
    if (content is! Map<String, dynamic>) return;
    final retryFiles = content['retryFiles'] as List<XFile>?;
    final retryAllBytes = content['retryAllBytes'] as List<Uint8List>?;
    if (retryFiles == null || retryAllBytes == null) {
      if (mounted) AppToast.show(context, '文件数据已丢失，请重新选择');
      return;
    }

    final chat = context.read<ChatProvider>();
    final api = context.read<ApiClient>();
    final localId = msg['messageId']?.toString();
    if (localId == null) return;

    content['uploading'] = true;
    content['uploadProgress'] = 0.0;
    msg['sendState'] = 'sending';
    chat.notifyListeners();

    _doUploadAlbum(localId, retryFiles, retryAllBytes, api: api, chat: chat);
  }

  Widget _buildCallRecordMessage(Map<String, dynamic> msg) {
    final content = msg['content'];

    String text = '[通话记录]';
    String callType = 'voice';
    if (content is Map<String, dynamic>) {
      final value = content['text']?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        text = value;
      }
      final type = content['callType']?.toString() ?? '';
      if (type == 'video' || type == 'voice') {
        callType = type;
      }
    } else if (content is String && content.trim().isNotEmpty) {
      text = content.trim();
    }

    final icon = callType == 'video' ? Icons.videocam_outlined : Icons.phone_outlined;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    final url = AppConfig.resolveFileUrl(content is Map<String, dynamic> ? content['url']?.toString() : null);
    final sendState = msg['sendState'];
    final localBytes = content is Map<String, dynamic> ? content['localBytes'] as Uint8List? : null;
    final uploadProgress = content is Map<String, dynamic> ? (content['uploadProgress'] as num?)?.toDouble() ?? 0.0 : 0.0;

    // Local preview during upload or after failure
    if (localBytes != null && url.isEmpty) {
      return GestureDetector(
        onTap: sendState == 'failed' ? () => _retryMediaSend(msg) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(localBytes, fit: BoxFit.cover),
                if (sendState == 'sending')
                  Container(
                    color: Colors.black38,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 48, height: 48,
                          child: CircularProgressIndicator(
                            value: uploadProgress > 0 ? uploadProgress : null,
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                        if (uploadProgress > 0) ...[
                          const SizedBox(height: 6),
                          Text('${(uploadProgress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                if (sendState == 'failed')
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, color: Colors.white, size: 32),
                          SizedBox(height: 4),
                          Text('点击重试', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (sendState == 'sending' && url.isEmpty) {
      return _buildMediaHint('图片发送中...');
    }

    if (sendState == 'failed' && url.isEmpty) {
      return _buildMediaHint('图片发送失败', isError: true);
    }

    if (url.isEmpty) {
      return _buildMediaHint('[图片]');
    }

    return GestureDetector(
      onTap: () => _openImagePreview(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 180,
          height: 180,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 180,
              height: 180,
              color: Colors.black12,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 2),
            );
          },
          errorBuilder: (_, _, _) => Container(
            width: 180,
            height: 180,
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoContent(Map<String, dynamic> msg) {
    final content = msg['content'];
    final url = AppConfig.resolveFileUrl(content is Map<String, dynamic> ? content['url']?.toString() : null);
    final name = content is Map<String, dynamic> ? (content['name']?.toString() ?? '视频') : '视频';
    final sendState = msg['sendState'];
    final localBytes = content is Map<String, dynamic> ? content['localBytes'] as Uint8List? : null;
    final uploadProgress = content is Map<String, dynamic> ? (content['uploadProgress'] as num?)?.toDouble() ?? 0.0 : 0.0;

    // Local preview during upload or after failure
    if (localBytes != null && url.isEmpty) {
      return GestureDetector(
        onTap: sendState == 'failed' ? () => _retryMediaSend(msg) : null,
        child: Container(
          width: 220,
          height: 124,
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              const Center(
                child: Icon(Icons.videocam, color: Colors.white54, size: 40),
              ),
              if (sendState == 'sending')
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 48, height: 48,
                        child: CircularProgressIndicator(
                          value: uploadProgress > 0 ? uploadProgress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                      if (uploadProgress > 0) ...[
                        const SizedBox(height: 6),
                        Text('${(uploadProgress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              if (sendState == 'failed')
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, color: Colors.white, size: 32),
                        SizedBox(height: 4),
                        Text('点击重试', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Text(
                  name,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (sendState == 'sending' && url.isEmpty) {
      return _buildMediaHint('视频发送中...');
    }

    if (sendState == 'failed' && url.isEmpty) {
      return _buildMediaHint('视频发送失败', isError: true);
    }

    return GestureDetector(
      onTap: url.isEmpty ? null : () => _openVideoPreview(url),
      child: Container(
        width: 220,
        height: 124,
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频缩略图
              _VideoThumbnail(videoUrl: url),
              // 播放按钮（半透明遮罩）
              Center(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaHint(String label, {bool isError = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isError)
          const Icon(Icons.error_outline, size: 16, color: AppColors.textSecondary)
        else
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
          ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildSelfStatus(Map<String, dynamic> msg) {
    final sendState = msg['sendState']?.toString() ?? 'sent';
    final readState = msg['readState']?.toString() ?? 'unread';
    final time = formatMsgTime(msg['createdAt']?.toString());

    String prefix;
    Color color;

    if (sendState == 'sending') {
      prefix = '发送中';
      color = AppColors.textSecondary;
    } else if (sendState == 'failed') {
      prefix = '发送失败';
      color = AppColors.danger;
    } else if (readState == 'read') {
      prefix = '已读';
      color = AppColors.textSecondary;
    } else {
      prefix = readState == 'read' ? '已读' : '未读';
      color = AppColors.textSecondary;
    }

    return Text(
      '$prefix  $time',
      style: TextStyle(fontSize: 12, color: color),
    );
  }

  bool _shouldShowTime(List<Map<String, dynamic>> msgs, int index) {
    if (index == 0) return true;
    final prev = DateTime.tryParse(msgs[index - 1]['createdAt']?.toString() ?? '');
    final curr = DateTime.tryParse(msgs[index]['createdAt']?.toString() ?? '');
    if (prev == null || curr == null) return false;
    return curr.difference(prev).inMinutes > 5;
  }

  Future<void> _showMsgMenu(Map<String, dynamic> msg, bool isSelf, Offset globalPosition) async {
    final type = msg['type'] as int? ?? 0;
    final status = msg['status'];
    if (status == 2 || status == 0) return;

    HapticFeedback.mediumImpact();

    final actions = <_ContextAction>[];

    // Reply - all non-system messages
    if (type != 9) {
      actions.add(const _ContextAction('reply', '回复', Icons.reply));
    }

    // Copy - text messages only
    if (type == 1) {
      actions.add(const _ContextAction('copy', '复制', Icons.copy));
    }

    // Save - image/video messages
    if (type == 2 || type == 4) {
      actions.add(const _ContextAction('save', '保存', Icons.download));
    }

    // Forward - most types
    if ([1, 2, 3, 4, 5, 10, 11].contains(type)) {
      actions.add(const _ContextAction('forward', '转发', Icons.shortcut));
    }

    // Delete - all
    actions.add(const _ContextAction('delete', '删除', Icons.delete_outline));

    // Revoke - self within 2 min
    if (isSelf) {
      final created = DateTime.tryParse(msg['createdAt']?.toString() ?? '');
      if (created != null && DateTime.now().difference(created).inMinutes < 2) {
        actions.add(const _ContextAction('revoke', '撤回', Icons.undo));
      }
    }

    if (actions.isEmpty) return;

    final value = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, _) {
        final screenSize = MediaQuery.of(ctx).size;
        final padding = MediaQuery.of(ctx).padding;
        const cols = 4;
        const itemW = 64.0;
        const itemH = 56.0;
        final rows = (actions.length / cols).ceil();
        final menuW = cols * itemW + 24;
        final menuH = rows * itemH + 16.0;

        var dx = globalPosition.dx - menuW / 2;
        dx = dx.clamp(12.0, screenSize.width - menuW - 12);

        // Try above the tap point; if too close to top, show below
        var dy = globalPosition.dy - menuH - 12;
        if (dy < padding.top + 8) {
          dy = globalPosition.dy + 12;
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: dx,
              top: dy,
              child: FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  alignment: Alignment.center,
                  scale: Tween(begin: 0.85, end: 1.0).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: menuW,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Wrap(
                        children: actions.map((a) {
                          return SizedBox(
                            width: itemW,
                            height: itemH,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => Navigator.pop(ctx, a.id),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(a.icon, color: Colors.white, size: 22),
                                  const SizedBox(height: 5),
                                  Text(a.label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (value == null || !mounted) return;

    switch (value) {
      case 'reply':
        setState(() => _replyingTo = msg);
        break;
      case 'copy':
        _handleCopyAction(msg);
        break;
      case 'save':
        _handleSaveAction(msg);
        break;
      case 'forward':
        _handleForwardAction(msg);
        break;
      case 'delete':
        _handleDeleteAction(msg);
        break;
      case 'revoke':
        _handleRevokeAction(msg);
        break;
    }
  }

  void _handleCopyAction(Map<String, dynamic> msg) {
    final content = msg['content'];
    String text;
    if (content is String) {
      text = content;
    } else if (content is Map) {
      text = content['text']?.toString() ?? '';
    } else {
      text = content?.toString() ?? '';
    }
    if (text.isNotEmpty) ClipboardUtil.copy(text);
    if (mounted) AppToast.show(context, '已复制');
  }

  Future<void> _handleSaveAction(Map<String, dynamic> msg) async {
    final type = _intType(msg['type']);
    final content = msg['content'];
    final url = AppConfig.resolveFileUrl(content is Map<String, dynamic> ? content['url']?.toString() : null);
    if (url.isEmpty) {
      AppToast.show(context, '无法获取文件地址');
      return;
    }
    try {
      await saveImageToDevice(url, isVideo: type == 4);
      if (mounted) AppToast.show(context, '已保存到相册');
    } catch (e) {
      if (mounted) AppToast.show(context, '保存失败');
    }
  }

  Future<void> _handleForwardAction(Map<String, dynamic> msg) async {
    final chat = context.read<ChatProvider>();
    final conversations = chat.conversations;

    final selectedConvId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (ctx, sc) {
            final filteredConvs = conversations.where((c) => c['conversationId'] != widget.conversationId).toList();
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
                  child: Text('转发到', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filteredConvs.isEmpty
                      ? const Center(child: Text('暂无其他会话', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          controller: sc,
                          itemCount: filteredConvs.length,
                          itemBuilder: (ctx, i) {
                            final conv = filteredConvs[i];
                            final name = chat.getConvDisplayName(conv);
                            final avatarUrl = chat.getConvAvatarUrl(conv);
                            return ListTile(
                              leading: UserAvatar(name: name, url: avatarUrl, size: 42, radius: 21),
                              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => Navigator.pop(ctx, conv['conversationId']?.toString()),
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

    if (selectedConvId == null || !mounted) return;

    // Confirm forward
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('转发消息'),
        content: const Text('确认转发此消息吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final fwdContent = msg['content'];
      final fwdType = msg['type'] as int? ?? 1;
      await chat.sendMessage(selectedConvId, type: fwdType, content: fwdContent);
      if (mounted) AppToast.show(context, '已转发');
    } catch (e) {
      if (mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '转发失败'));
    }
  }

  void _handleDeleteAction(Map<String, dynamic> msg) {
    final messageId = msg['messageId']?.toString();
    if (messageId == null) return;
    context.read<ChatProvider>().deleteLocalMessage(widget.conversationId, messageId);
    if (mounted) AppToast.show(context, '已删除');
  }

  Future<void> _handleRevokeAction(Map<String, dynamic> msg) async {
    try {
      await context.read<ChatProvider>().revokeMessage(msg['messageId']);
      if (!mounted) return;
      AppToast.show(context, '消息已撤回');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '撤回失败'));
    }
  }

  Widget _buildMsgContentWithReply(Map<String, dynamic> msg, Widget content) {
    final msgContent = msg['content'];
    Map<String, dynamic>? replyTo;
    if (msgContent is Map<String, dynamic> && msgContent['replyTo'] is Map) {
      replyTo = Map<String, dynamic>.from(msgContent['replyTo'] as Map);
    }
    if (replyTo == null) return content;

    final senderName = replyTo['senderNickname']?.toString() ?? '未知';
    final preview = replyTo['preview']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(4),
            border: const Border(left: BorderSide(color: AppColors.primary, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(senderName, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text(preview, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        content,
      ],
    );
  }

  String _getReplyPreviewText(Map<String, dynamic> msg) {
    final type = msg['type'] as int? ?? 0;
    switch (type) {
      case 1:
        final c = msg['content'];
        return (c is Map ? c['text'] : c)?.toString() ?? '';
      case 2: return '[图片]';
      case 3: return '[语音]';
      case 4: return '[视频]';
      case 5: return '[文件]';
      case 6: return '[位置]';
      case 7: return '[红包]';
      case 10: return '[名片]';
      case 11: return '[相册]';
      default: return '[消息]';
    }
  }

  Widget _buildReplyPreview() {
    if (_replyingTo == null) return const SizedBox.shrink();
    final sender = _replyingTo!['sender'] as Map<String, dynamic>?;
    final senderName = sender?['nickname']?.toString() ?? '未知';
    final preview = _getReplyPreviewText(_replyingTo!);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('回复 $senderName', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 1),
                Text(preview, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final canSend = _inputText.trim().isNotEmpty && !_sendingText;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Recording overlay
            if (_isRecording)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                color: const Color(0xFFFFF3F3),
                child: Column(
                  children: [
                    Icon(
                      _recordCancelled ? Icons.delete_outline : Icons.mic,
                      size: 36,
                      color: _recordCancelled ? AppColors.danger : AppColors.primary,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _recordCancelled ? '松开取消' : '$_recordSeconds″  上滑取消',
                      style: TextStyle(
                        color: _recordCancelled ? AppColors.danger : AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Voice/keyboard toggle button
                  IconButton(
                    icon: Icon(
                      _voiceMode ? Icons.keyboard_outlined : Icons.mic_none,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _voiceMode = !_voiceMode),
                  ),
                  const SizedBox(width: 4),
                  // Main input area: either text field or hold-to-talk button
                  Expanded(
                    child: _voiceMode
                        ? GestureDetector(
                            onLongPressStart: (_) => _startRecording(),
                            onLongPressMoveUpdate: (details) {
                              if (details.localOffsetFromOrigin.dy < -50) {
                                if (!_recordCancelled) setState(() => _recordCancelled = true);
                              } else {
                                if (_recordCancelled) setState(() => _recordCancelled = false);
                              }
                            },
                            onLongPressEnd: (_) {
                              if (_recordCancelled) {
                                _cancelRecording();
                              } else {
                                _stopRecording();
                              }
                            },
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: _isRecording ? AppColors.primary.withValues(alpha: 0.12) : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _isRecording ? AppColors.primary : AppColors.border,
                                  width: _isRecording ? 1.5 : 0.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _isRecording ? '松开 发送' : '按住 说话',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: _isRecording ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : TextField(
                            controller: _inputController,
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            decoration: InputDecoration(
                              hintText: '输入消息...',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(color: AppColors.border, width: 0.5),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(color: AppColors.border, width: 0.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1),
                              ),
                            ),
                            onChanged: _onInputChanged,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                  ),
                  const SizedBox(width: 4),
                  // Attach button
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: AppColors.textSecondary),
                    onPressed: _showAttachSheet,
                  ),
                  if (!_voiceMode) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: canSend ? AppColors.primary : const Color(0xFFC7C7C7),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: canSend
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: IconButton(
                        icon: _sendingText
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        onPressed: canSend ? _sendMessage : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _collectAllImageUrls() {
    final chat = context.read<ChatProvider>();
    final msgs = chat.getMessages(widget.conversationId);
    final urls = <String>[];
    for (final msg in msgs) {
      final type = msg['type'];
      final content = msg['content'];
      if (type == 2 && content is Map<String, dynamic>) {
        final url = AppConfig.resolveFileUrl(content['url']?.toString());
        if (url.isNotEmpty) urls.add(url);
      } else if (type == 11 && content is Map<String, dynamic>) {
        final items = content['items'];
        if (items is List) {
          for (final item in items) {
            if (item is Map) {
              final mediaType = item['mediaType']?.toString() ?? '';
              if (mediaType != 'video') {
                final url = AppConfig.resolveFileUrl(item['url']?.toString());
                if (url.isNotEmpty) urls.add(url);
              }
            }
          }
        }
      }
    }
    return urls;
  }

  void _openImagePreview(String imageUrl) {
    final allUrls = _collectAllImageUrls();
    int initialIndex = allUrls.indexOf(imageUrl);
    if (initialIndex < 0) {
      allUrls.insert(0, imageUrl);
      initialIndex = 0;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageGalleryPage(
          imageUrls: allUrls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _openVideoPreview(String videoUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _VideoPreviewPage(videoUrl: videoUrl)),
    );
  }
}

class _ImagePreviewPage extends StatelessWidget {
  final String imageUrl;
  const _ImagePreviewPage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 56),
          ),
        ),
      ),
    );
  }
}

class _VideoPreviewPage extends StatefulWidget {
  final String videoUrl;
  const _VideoPreviewPage({required this.videoUrl});

  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  VideoPlayerController? _controller;
  bool _hasError = false;
  String _errorDetail = '';
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _downloadAndPlay();
  }

  Future<void> _downloadAndPlay() async {
    setState(() { _downloading = true; _downloadProgress = 0; _hasError = false; _errorDetail = ''; });
    try {
      // 先下载视频到临时文件，避免 iOS CoreMedia 对 Range 请求的要求
      final dir = await getTemporaryDirectory();
      final ext = widget.videoUrl.contains('.') ? widget.videoUrl.split('.').last.split('?').first : 'mp4';
      final filePath = '${dir.path}/video_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      await Dio().download(
        widget.videoUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() { _downloadProgress = received / total; });
          }
        },
      );
      
      if (!mounted) return;
      _localPath = filePath;
      setState(() { _downloading = false; });
      
      final controller = VideoPlayerController.file(File(filePath));
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() {});
      controller.play();
    } catch (e) {
      debugPrint('[VideoPreview] download/init error: $e');
      if (mounted) {
        setState(() {
          _downloading = false;
          _hasError = true;
          _errorDetail = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              try {
                await saveImageToDevice(widget.videoUrl, isVideo: true);
                if (context.mounted) AppToast.show(context, '已保存到相册');
              } catch (_) {
                if (context.mounted) AppToast.show(context, '保存失败');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: _downloading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 60, height: 60,
                    child: CircularProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      color: Colors.white70,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _downloadProgress > 0 ? '${(_downloadProgress * 100).toInt()}%' : '加载中...',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              )
            : _hasError
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                  const SizedBox(height: 12),
                  const Text('视频加载失败', style: TextStyle(color: Colors.white54, fontSize: 15)),
                  if (_errorDetail.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(_errorDetail, style: const TextStyle(color: Colors.white24, fontSize: 11), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      _controller?.dispose();
                      _controller = null;
                      _downloadAndPlay();
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    label: const Text('重试', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              )
            : (controller != null && controller.value.isInitialized)
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                      // 进度条 + 控制
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          children: [
                            VideoProgressIndicator(controller, allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.white,
                                bufferedColor: Colors.white24,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatDuration(controller.value.position),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                const Spacer(),
                                IconButton(
                                  iconSize: 42,
                                  color: Colors.white,
                                  icon: Icon(controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                                  onPressed: () {
                                    if (controller.value.isPlaying) {
                                      controller.pause();
                                    } else {
                                      controller.play();
                                    }
                                  },
                                ),
                                const Spacer(),
                                Text(
                                  _formatDuration(controller.value.duration),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

/// 视频缩略图组件：从网络视频 URL 获取首帧
class _VideoThumbnail extends StatefulWidget {
  final String videoUrl;
  const _VideoThumbnail({required this.videoUrl});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  Uint8List? _thumb;
  bool _failed = false;

  // 全局缓存避免重复生成
  static final Map<String, Uint8List> _cache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.videoUrl.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final cached = _cache[widget.videoUrl];
    if (cached != null) {
      if (mounted) setState(() => _thumb = cached);
      return;
    }
    try {
      final data = await vt.VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 440,
        quality: 50,
      );
      if (data != null && data.isNotEmpty) {
        _cache[widget.videoUrl] = data;
        if (mounted) setState(() => _thumb = data);
      } else {
        if (mounted) setState(() => _failed = true);
      }
    } catch (e) {
      debugPrint('[VideoThumbnail] error: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumb != null) {
      return Image.memory(_thumb!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    if (_failed) {
      return Container(
        color: const Color(0xFF1F1F1F),
        child: const Center(child: Icon(Icons.videocam, color: Colors.white38, size: 36)),
      );
    }
    return Container(
      color: const Color(0xFF1F1F1F),
      child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38))),
    );
  }
}

class _ContactCardProfilePage extends StatefulWidget {
  final int userId;
  final String nickname;
  final String? avatarUrl;
  final String uid;

  const _ContactCardProfilePage({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    required this.uid,
  });

  @override
  State<_ContactCardProfilePage> createState() => _ContactCardProfilePageState();
}

class _ContactCardProfilePageState extends State<_ContactCardProfilePage> {
  bool _isFriend = false;
  bool _loading = true;
  Map<String, dynamic>? _userInfo;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/users/${widget.userId}');
      final friends = context.read<ContactsProvider>().friends;
      final found = friends.any((f) => f['userId'] == widget.userId);
      if (!mounted) return;
      setState(() {
        _userInfo = data is Map<String, dynamic> ? data : null;
        _isFriend = found;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nickname = _userInfo?['nickname']?.toString() ?? widget.nickname;
    final avatarUrl = _userInfo?['avatarUrl']?.toString() ?? widget.avatarUrl;
    final uid = _userInfo?['uid']?.toString() ?? widget.uid;
    final signature = _userInfo?['signature']?.toString() ?? '';
    final gender = _userInfo?['gender'];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('个人名片', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      UserAvatar(name: nickname, url: avatarUrl, size: 72, radius: 36),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(nickname, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          if (gender == 1)
                            const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.male, color: Colors.blue, size: 18)),
                          if (gender == 2)
                            const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.female, color: Colors.pink, size: 18)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('UID: $uid', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      if (signature.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(signature, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (_isFriend) {
                          // Already a friend, open chat
                          try {
                            final api = context.read<ApiClient>();
                            final result = await api.post('/conversations', data: {
                              'type': 1,
                              'targetUserId': widget.userId,
                            });
                            if (!context.mounted) return;
                            final convId = result['conversationId']?.toString();
                            if (convId != null) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(conversationId: convId, title: nickname),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) AppToast.show(context, ErrorMessage.from(e, fallback: '操作失败'));
                          }
                        } else {
                          // Send friend request
                          try {
                            await context.read<ContactsProvider>().sendFriendRequest(widget.userId, '通过名片添加');
                            if (!context.mounted) return;
                            AppToast.show(context, '好友申请已发送');
                          } catch (e) {
                            if (!context.mounted) return;
                            AppToast.show(context, ErrorMessage.from(e, fallback: '发送好友申请失败'));
                          }
                        }
                      },
                      icon: Icon(_isFriend ? Icons.chat_bubble_outline : Icons.person_add_alt_outlined, size: 20),
                      label: Text(_isFriend ? '发送消息' : '添加好友', style: const TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MediaPreviewPage extends StatefulWidget {
  final List<XFile> files;
  final List<Uint8List> bytesData;
  const _MediaPreviewPage({required this.files, required this.bytesData});

  @override
  State<_MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<_MediaPreviewPage> {
  VideoPlayerController? _videoController;
  bool _videoError = false;

  bool get _isSingleVideo {
    if (widget.files.length != 1) return false;
    final file = widget.files.first;
    final mime = file.mimeType ?? '';
    final name = file.name.toLowerCase();
    return mime.startsWith('video') || name.endsWith('.mp4') || name.endsWith('.mov');
  }

  @override
  void initState() {
    super.initState();
    if (_isSingleVideo && !kIsWeb) {
      final path = widget.files.first.path;
      if (path.isNotEmpty) {
        _videoController = VideoPlayerController.file(File(path))
          ..initialize().then((_) {
            if (mounted) setState(() {});
          }).catchError((e) {
            if (mounted) setState(() => _videoError = true);
          });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text('已选择 ${widget.files.length} 个文件', style: const TextStyle(fontSize: 17)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isSingleVideo && _videoController != null
                ? _buildVideoPreview()
                : _buildGrid(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.send_rounded, size: 20),
                  label: Text('发送 (${widget.files.length})', style: const TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    final controller = _videoController;
    if (_videoError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam, color: Colors.white54, size: 48),
            const SizedBox(height: 8),
            Text(widget.files.first.name, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
        });
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              if (!controller.value.isPlaying)
                const Icon(Icons.play_circle_fill, color: Colors.white70, size: 56),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.files.length == 1 ? 1 : 3,
        crossAxisSpacing: 3,
        mainAxisSpacing: 3,
      ),
      itemCount: widget.files.length,
      itemBuilder: (_, i) {
        final file = widget.files[i];
        final mime = file.mimeType ?? '';
        final isVideo = mime.startsWith('video') || file.name.toLowerCase().endsWith('.mp4') || file.name.toLowerCase().endsWith('.mov');
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!isVideo)
                Image.memory(widget.bytesData[i], fit: BoxFit.cover)
              else
                Container(
                  color: const Color(0xFF222222),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.videocam, color: Colors.white54, size: 36),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(file.name, style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              if (isVideo)
                const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40)),
            ],
          ),
        );
      },
    );
  }
}

class _ContextAction {
  final String id;
  final String label;
  final IconData icon;
  const _ContextAction(this.id, this.label, this.icon);
}
