import 'package:flutter/foundation.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/services/socket_service.dart';
import 'package:im_client/services/notification_service.dart';

class IncomingCallInvite {
  final String callId;
  final int callerId;
  final String callerName;
  final String? callerAvatarUrl;
  final String callType;

  const IncomingCallInvite({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerAvatarUrl,
    required this.callType,
  });
}

class CallLaunchPayload {
  final String callId;
  final int peerUserId;
  final String peerName;
  final String? peerAvatarUrl;
  final String callType;
  final Map<String, dynamic> rtcConfig;
  final bool isCaller;

  const CallLaunchPayload({
    required this.callId,
    required this.peerUserId,
    required this.peerName,
    required this.peerAvatarUrl,
    required this.callType,
    required this.rtcConfig,
    required this.isCaller,
  });
}

class CallProvider extends ChangeNotifier {
  final ApiClient api;
  final SocketService socket;
  final AuthService auth;

  IncomingCallInvite? _incomingCall;
  bool _inCall = false;
  bool _handlingIncoming = false;
  int _callPageCount = 0;

  CallProvider({
    required this.api,
    required this.socket,
    required this.auth,
  }) {
    socket.on('call:incoming', _onIncomingCall);
    socket.on('call:ended', _onCallEnded);
    socket.on('call:rejected', _onCallEnded);
    socket.on('call:timeout', _onCallEnded);
  }

  IncomingCallInvite? get incomingCall => _incomingCall;
  bool get inCall => _inCall;
  bool get handlingIncoming => _handlingIncoming;

  void setInCall(bool value) {
    if (_inCall == value) return;
    _inCall = value;
    if (value) {
      _incomingCall = null;
    }
    notifyListeners();
  }

  void callPageDidMount() {
    _callPageCount++;
  }

  void callPageDidDispose() {
    _callPageCount = (_callPageCount - 1).clamp(0, 99);
    if (_callPageCount == 0) {
      _inCall = false;
    }
  }

  Future<CallLaunchPayload> acceptIncomingCall() async {
    final invite = _incomingCall;
    if (invite == null) {
      throw StateError('没有可接听的来电');
    }

    _handlingIncoming = true;
    notifyListeners();

    try {
      final raw = await api.post('/calls/${invite.callId}/answer');
      final result = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final peerUserId = _asInt(result['peerUserId']) ?? invite.callerId;

      socket.emit('call:accept', {
        'callId': invite.callId,
        'callerId': invite.callerId,
      });

      _incomingCall = null;
      _handlingIncoming = false;
      _inCall = true;
      NotificationService().cancelCallNotification();
      notifyListeners();

      return CallLaunchPayload(
        callId: invite.callId,
        peerUserId: peerUserId,
        peerName: invite.callerName,
        peerAvatarUrl: invite.callerAvatarUrl,
        callType: invite.callType,
        rtcConfig: _normalizeRtcConfig(result['rtcConfig']),
        isCaller: false,
      );
    } catch (_) {
      _handlingIncoming = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> rejectIncomingCall() async {
    final invite = _incomingCall;
    if (invite == null) return;

    _handlingIncoming = true;
    notifyListeners();

    try {
      await api.post('/calls/${invite.callId}/reject');
      socket.emit('call:reject', {
        'callId': invite.callId,
        'callerId': invite.callerId,
      });
    } finally {
      _incomingCall = null;
      _handlingIncoming = false;
      NotificationService().cancelCallNotification();
      notifyListeners();
    }
  }

  void clearIncomingCall() {
    if (_incomingCall == null) return;
    _incomingCall = null;
    NotificationService().cancelCallNotification();
    notifyListeners();
  }

  void _onIncomingCall(dynamic data) {
    if (data is! Map) return;
    final callId = data['callId']?.toString() ?? '';
    final callerId = _asInt(data['callerId']);
    if (callId.isEmpty || callerId == null) return;

    // 未登录或正在处理其他来电 → 直接拒绝
    if (!auth.isLoggedIn || _handlingIncoming) {
      socket.emit('call:reject', {
        'callId': callId,
        'callerId': callerId,
      });
      return;
    }

    // 如果标记为通话中，检查是否真正有 CallPage 存在
    if (_inCall) {
      if (_callPageCount > 0) {
        // 真正在通话中，拒绝新来电
        socket.emit('call:reject', {
          'callId': callId,
          'callerId': callerId,
        });
        return;
      }
      // 没有 CallPage → 残留状态，重置
      _inCall = false;
    }

    final callerName = data['callerNickname']?.toString().trim();
    final type = data['callType']?.toString().trim();
    final resolvedName = (callerName == null || callerName.isEmpty) ? '未知用户' : callerName;
    final resolvedType = (type == 'video' || type == 'voice') ? type! : 'voice';
    _incomingCall = IncomingCallInvite(
      callId: callId,
      callerId: callerId,
      callerName: resolvedName,
      callerAvatarUrl: data['callerAvatarUrl']?.toString(),
      callType: resolvedType,
    );
    // 发送来电通知
    NotificationService().showCallNotification(
      callerName: resolvedName,
      callType: resolvedType,
    );
    notifyListeners();
  }

  void _onCallEnded(dynamic data) {
    if (data is! Map) return;
    final callId = data['callId']?.toString();
    if (callId == null) return;

    if (_incomingCall?.callId == callId) {
      _incomingCall = null;
    }
    // 取消来电通知
    NotificationService().cancelCallNotification();
    // 通话已结束/拒绝/超时，确保清除占线状态
    _inCall = false;
    _callPageCount = 0;
    _handlingIncoming = false;
    notifyListeners();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic> _normalizeRtcConfig(dynamic rawConfig) {
    final fallback = {
      'iceServers': [
        {'urls': ['stun:stun.l.google.com:19302']},
      ],
    };

    if (rawConfig is! Map) return fallback;
    final source = Map<String, dynamic>.from(rawConfig);
    final rawIceServers = source['iceServers'];
    if (rawIceServers is! List || rawIceServers.isEmpty) return fallback;

    final iceServers = <Map<String, dynamic>>[];
    for (final item in rawIceServers) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final urls = map['urls'];
      if (urls == null) continue;

      if (urls is String) {
        map['urls'] = [urls];
      } else if (urls is List) {
        map['urls'] = urls.map((e) => e.toString()).toList();
      } else {
        continue;
      }

      iceServers.add(map);
    }

    if (iceServers.isEmpty) return fallback;
    return {'iceServers': iceServers};
  }

  @override
  void dispose() {
    socket.off('call:incoming');
    socket.off('call:ended');
    socket.off('call:rejected');
    socket.off('call:timeout');
    super.dispose();
  }
}
