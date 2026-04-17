import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:im_client/providers/call_provider.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/socket_service.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/widgets/user_avatar.dart';
import 'package:provider/provider.dart';

class CallPage extends StatefulWidget {
  final String callId;
  final int peerUserId;
  final String peerName;
  final String? peerAvatarUrl;
  final String callType;
  final bool isCaller;
  final Map<String, dynamic> rtcConfig;

  const CallPage({
    super.key,
    required this.callId,
    required this.peerUserId,
    required this.peerName,
    required this.peerAvatarUrl,
    required this.callType,
    required this.isCaller,
    required this.rtcConfig,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  late final CallProvider _callProvider;
  late final SocketService _socket;
  late final ApiClient _api;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStreamTrack? _audioTrack;
  MediaStreamTrack? _videoTrack;

  final List<RTCIceCandidate> _pendingCandidates = [];

  bool _cameraEnabled = false;
  bool _speakerEnabled = false;
  bool _muted = false;
  bool _hangingUp = false;
  bool _connected = false;
  bool _remoteHasVideo = false;
  bool _initialOfferSent = false;
  bool _remoteDescriptionReady = false;
  bool _pendingOfferAfterInit = false;
  final Completer<void> _audioReady = Completer<void>();
  Map<String, dynamic>? _pendingRemoteSdp;
  String _statusText = '正在拨号...';
  Timer? _durationTimer;
  Timer? _offerDelayTimer;
  int _durationSeconds = 0;

  late final Function(dynamic) _onAcceptedHandler;
  late final Function(dynamic) _onRejectedHandler;
  late final Function(dynamic) _onEndedHandler;
  late final Function(dynamic) _onTimeoutHandler;
  late final Function(dynamic) _onSdpHandler;
  late final Function(dynamic) _onIceHandler;

  @override
  void initState() {
    super.initState();
    _callProvider = context.read<CallProvider>();
    _socket = context.read<SocketService>();
    _api = context.read<ApiClient>();

    _callProvider.callPageDidMount();
    _callProvider.setInCall(true);
    _statusText = widget.isCaller ? '等待对方接听...' : '连接中...';
    _cameraEnabled = widget.callType == 'video';

    _onAcceptedHandler = _onCallAccepted;
    _onRejectedHandler = _onCallRejected;
    _onEndedHandler = _onCallEnded;
    _onTimeoutHandler = _onCallTimeout;
    _onSdpHandler = _onRemoteSdp;
    _onIceHandler = _onRemoteIceCandidate;

    _socket.on('call:accepted', _onAcceptedHandler);
    _socket.on('call:rejected', _onRejectedHandler);
    _socket.on('call:ended', _onEndedHandler);
    _socket.on('call:timeout', _onTimeoutHandler);
    _socket.on('call:sdp', _onSdpHandler);
    _socket.on('call:ice-candidate', _onIceHandler);

    unawaited(_initCall());
  }

  Future<void> _initCall() async {
    try {
      await _remoteRenderer.initialize();
      await _localRenderer.initialize();
      await _createPeer();
      await _openLocalAudio();

      if (_cameraEnabled) {
        await _enableVideoTrack(syncApi: false);
      }

      final cachedSdp = _pendingRemoteSdp;
      if (cachedSdp != null) {
        _pendingRemoteSdp = null;
        await _onRemoteSdp(cachedSdp);
      }

      if (_pendingOfferAfterInit) {
        _pendingOfferAfterInit = false;
        await _createAndSendOffer();
      }

      if (widget.isCaller) {
        setState(() => _statusText = '等待对方接听...');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '初始化通话失败'));
      await _safePop();
    }
  }

  Future<void> _createPeer() async {
    final config = _normalizeRtcConfig(widget.rtcConfig);
    final peer = await createPeerConnection(config, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    peer.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _socket.emit('call:ice-candidate', {
        'callId': widget.callId,
        'targetUserId': widget.peerUserId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    peer.onTrack = (event) {
      if (event.streams.isEmpty) return;
      final stream = event.streams.first;
      _remoteStream = stream;
      _remoteRenderer.srcObject = stream;
      final hasVideo = stream.getVideoTracks().isNotEmpty;
      if (mounted) {
        setState(() {
          _remoteHasVideo = hasVideo;
        });
      }
    };

    peer.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _statusText = '连接失败');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        setState(() => _statusText = '连接中断');
      }
    };

    _peer = peer;
  }

  Future<void> _openLocalAudio() async {
    final constraints = kIsWeb
        ? {
            'audio': {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            },
            'video': false,
          }
        : {'audio': true, 'video': false};
    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStream = stream;

    for (final track in stream.getAudioTracks()) {
      _audioTrack = track;
      await _peer?.addTrack(track, stream);
    }
    if (!_audioReady.isCompleted) _audioReady.complete();
  }

  Future<void> _createAndSendOffer({bool force = false}) async {
    if (_peer == null) return;
    if (!force && _initialOfferSent) return;
    // 等待本地音频就绪（首次授权可能有延迟）
    await _audioReady.future;
    if (!force) {
      _initialOfferSent = true;
    }
    final offer = await _peer!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    if (offer.sdp == null || offer.sdp!.isEmpty) return;

    await _peer!.setLocalDescription(offer);
    _socket.emit('call:sdp', {
      'callId': widget.callId,
      'targetUserId': widget.peerUserId,
      'sdpType': 'offer',
      'sdp': offer.sdp,
    });

    if (!mounted) return;
    setState(() => _statusText = '连接中...');
  }

  Future<void> _createAndSendAnswer() async {
    if (_peer == null) return;
    // 等待本地音频就绪（首次授权可能有延迟）
    await _audioReady.future;
    final answer = await _peer!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    if (answer.sdp == null || answer.sdp!.isEmpty) return;

    await _peer!.setLocalDescription(answer);
    _socket.emit('call:sdp', {
      'callId': widget.callId,
      'targetUserId': widget.peerUserId,
      'sdpType': 'answer',
      'sdp': answer.sdp,
    });

    if (!mounted) return;
    _markConnected();
  }

  void _markConnected() {
    if (!mounted) return;
    if (_connected) {
      setState(() => _statusText = '通话中');
      return;
    }

    setState(() {
      _connected = true;
      _statusText = '通话中';
    });

    _durationTimer?.cancel();
    _durationSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _durationSeconds += 1;
      });
    });
  }

  Future<void> _flushPendingCandidates() async {
    if (!_remoteDescriptionReady || _peer == null || _pendingCandidates.isEmpty) return;
    for (final candidate in _pendingCandidates) {
      await _peer!.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  void _onCallAccepted(dynamic data) {
    if (!widget.isCaller || data is! Map) return;
    final callId = data['callId']?.toString();
    if (callId != widget.callId) return;

    if (_peer == null) {
      _pendingOfferAfterInit = true;
      return;
    }

    _offerDelayTimer?.cancel();
    _offerDelayTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      unawaited(_createAndSendOffer());
    });
  }

  void _onCallRejected(dynamic data) {
    if (data is! Map) return;
    final callId = data['callId']?.toString();
    if (callId != widget.callId || !mounted) return;

    AppToast.show(context, '对方已拒绝');
    unawaited(_safePop());
  }

  void _onCallEnded(dynamic data) {
    if (data is! Map) return;
    final callId = data['callId']?.toString();
    if (callId != widget.callId || !mounted) return;

    AppToast.show(context, '通话已结束');
    unawaited(_safePop());
  }

  void _onCallTimeout(dynamic data) {
    if (data is! Map) return;
    final callId = data['callId']?.toString();
    if (callId != widget.callId || !mounted) return;

    AppToast.show(context, '对方暂未接听');
    unawaited(_safePop());
  }

  Future<void> _onRemoteSdp(dynamic data) async {
    if (data is! Map) return;
    final callId = data['callId']?.toString();
    if (callId != widget.callId) return;

    if (_peer == null) {
      _pendingRemoteSdp = Map<String, dynamic>.from(data);
      return;
    }

    final sdp = data['sdp']?.toString();
    final sdpType = data['sdpType']?.toString();
    if (sdp == null || sdp.isEmpty || sdpType == null || sdpType.isEmpty || _peer == null) return;

    try {
      await _peer!.setRemoteDescription(RTCSessionDescription(sdp, sdpType));
      _remoteDescriptionReady = true;
      await _flushPendingCandidates();

      if (sdpType == 'offer') {
        await _createAndSendAnswer();
      } else if (sdpType == 'answer' && mounted) {
        _markConnected();
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '通话协商失败'));
    }
  }

  Future<void> _onRemoteIceCandidate(dynamic data) async {
    if (data is! Map) return;
    final callId = data['callId']?.toString();
    if (callId != widget.callId) return;

    final rawCandidate = data['candidate'];
    if (rawCandidate is! Map) return;

    final candidate = rawCandidate['candidate']?.toString();
    final sdpMid = rawCandidate['sdpMid']?.toString();
    final sdpMLineIndex = rawCandidate['sdpMLineIndex'] is int
        ? rawCandidate['sdpMLineIndex'] as int
        : int.tryParse(rawCandidate['sdpMLineIndex']?.toString() ?? '');

    if (candidate == null || candidate.isEmpty) return;

    final rtcCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
    if (_remoteDescriptionReady && _peer != null) {
      await _peer!.addCandidate(rtcCandidate);
    } else {
      _pendingCandidates.add(rtcCandidate);
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);

    _audioTrack?.enabled = !next;
    try {
      await _api.post('/calls/${widget.callId}/mute', data: {'isMuted': next});
    } catch (e) {
      if (!mounted) return;
      setState(() => _muted = !next);
      _audioTrack?.enabled = next;
      AppToast.show(context, ErrorMessage.from(e, fallback: '切换静音失败'));
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerEnabled;
    try {
      if (!kIsWeb) {
        await Helper.setSpeakerphoneOn(next);
      }
      if (!mounted) return;
      setState(() => _speakerEnabled = next);
    } catch (e) {
      if (!mounted) return;
      // 即使报错也切换 UI 状态，避免按钮卡死
      setState(() => _speakerEnabled = next);
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameraEnabled) {
      await _disableVideoTrack();
    } else {
      await _enableVideoTrack(syncApi: true);
    }
  }

  Future<void> _enableVideoTrack({required bool syncApi}) async {
    try {
      if (_videoTrack == null) {
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': 'user',
            'width': {'ideal': 720},
            'height': {'ideal': 1280},
          },
        });

        final tracks = stream.getVideoTracks();
        if (tracks.isNotEmpty) {
          _videoTrack = tracks.first;
          final local = _localStream;
          if (local != null) {
            local.addTrack(_videoTrack!);
            _localRenderer.srcObject = local;
            await _peer?.addTrack(_videoTrack!, local);
          }
        }
      }

      _videoTrack?.enabled = true;
      if (mounted) {
        setState(() => _cameraEnabled = true);
      }

      if (syncApi) {
        await _api.post('/calls/${widget.callId}/video-toggle', data: {'isVideoOff': false});
      }

      if (_connected) {
        await _createAndSendOffer(force: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraEnabled = false);
      AppToast.show(context, ErrorMessage.from(e, fallback: '开启摄像头失败'));
    }
  }

  Future<void> _disableVideoTrack() async {
    final track = _videoTrack;
    if (track == null) {
      setState(() => _cameraEnabled = false);
      return;
    }

    try {
      track.enabled = false;
      await _api.post('/calls/${widget.callId}/video-toggle', data: {'isVideoOff': true});
      if (!mounted) return;
      setState(() => _cameraEnabled = false);

      if (_connected) {
        await _createAndSendOffer(force: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraEnabled = true);
      AppToast.show(context, ErrorMessage.from(e, fallback: '关闭摄像头失败'));
    }
  }

  Future<void> _hangup() async {
    if (_hangingUp) return;
    setState(() => _hangingUp = true);
    try {
      await _api.post('/calls/${widget.callId}/hangup');
    } catch (_) {}

    _socket.emit('call:hangup', {
      'callId': widget.callId,
      'targetUserIds': [widget.peerUserId],
    });

    if (!mounted) return;
    await _safePop();
  }

  Future<void> _safePop() async {
    if (!mounted) return;
    _durationTimer?.cancel();
    _callProvider.setInCall(false);

    // 如果不是由 _hangup 触发的退出，主动清理后端占线状态
    if (!_hangingUp) {
      try {
        await _api.post('/calls/${widget.callId}/hangup');
      } catch (_) {}
      _socket.emit('call:hangup', {
        'callId': widget.callId,
        'targetUserIds': [widget.peerUserId],
      });
    }

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  String _buildStatusText() {
    if (_connected) {
      final mm = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
      final ss = (_durationSeconds % 60).toString().padLeft(2, '0');
      return '通话中  $mm:$ss';
    }
    return _statusText;
  }

  Map<String, dynamic> _normalizeRtcConfig(Map<String, dynamic> source) {
    final rawIceServers = source['iceServers'];
    if (rawIceServers is! List || rawIceServers.isEmpty) {
      return {
        'iceServers': [
          {'urls': ['stun:stun.l.google.com:19302']},
        ],
      };
    }

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

    if (iceServers.isEmpty) {
      return {
        'iceServers': [
          {'urls': ['stun:stun.l.google.com:19302']},
        ],
      };
    }

    return {'iceServers': iceServers};
  }

  Widget _buildVoiceCenter() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.03),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Center(
              child: UserAvatar(
                name: widget.peerName,
                url: widget.peerAvatarUrl,
                size: 130,
                radius: 65,
              ),
            ),
          ),
          const SizedBox(height: 26),
          const _VoiceWaveAnimation(),
        ],
      ),
    );
  }

  Widget _buildVideoCenter() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _remoteHasVideo && _remoteRenderer.srcObject != null
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: false,
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF18202D), Color(0xFF090D13)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UserAvatar(name: widget.peerName, url: widget.peerAvatarUrl, size: 84, radius: 42),
                          const SizedBox(height: 10),
                          const Text('对方视频连接中...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
          ),
          if (_cameraEnabled && _localRenderer.srcObject != null)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                width: 116,
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RTCVideoView(
                    _localRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: true,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showVideoCanvas = _cameraEnabled || _remoteHasVideo;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF090C13),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              children: [
                Text(
                  widget.peerName,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  _buildStatusText(),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: showVideoCanvas ? _buildVideoCenter() : _buildVoiceCenter(),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallControlButton(
                      icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                      label: _cameraEnabled ? '关闭摄像头' : '开启摄像头',
                      active: _cameraEnabled,
                      onTap: _toggleCamera,
                    ),
                    if (!kIsWeb)
                      _CallControlButton(
                        icon: _speakerEnabled ? Icons.volume_up : Icons.volume_down,
                        label: _speakerEnabled ? '关闭免提' : '免提',
                        active: _speakerEnabled,
                        onTap: _toggleSpeaker,
                      ),
                    _CallControlButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      label: _muted ? '取消静音' : '静音',
                      active: _muted,
                      onTap: _toggleMute,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _hangingUp ? null : _hangup,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE94B52),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: _hangingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.call_end),
                    label: Text(_hangingUp ? '挂断中...' : '挂断'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _offerDelayTimer?.cancel();
    _callProvider.callPageDidDispose();
    _callProvider.setInCall(false);

    _socket.off('call:accepted', _onAcceptedHandler);
    _socket.off('call:rejected', _onRejectedHandler);
    _socket.off('call:ended', _onEndedHandler);
    _socket.off('call:sdp', _onSdpHandler);
    _socket.off('call:ice-candidate', _onIceHandler);
    _socket.off('call:timeout', _onTimeoutHandler);

    _audioTrack?.stop();
    _videoTrack?.stop();
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peer?.close();
    _peer?.dispose();

    _localRenderer.dispose();
    _remoteRenderer.dispose();

    super.dispose();
  }
}

class _CallControlButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_CallControlButton> createState() => _CallControlButtonState();
}

class _CallControlButtonState extends State<_CallControlButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 94,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => _setPressed(true),
            onTapCancel: () => _setPressed(false),
            onTapUp: (_) => _setPressed(false),
            behavior: HitTestBehavior.opaque,
            child: AnimatedScale(
              scale: _pressed ? 0.92 : 1,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: widget.active ? 0.24 : 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: widget.active ? 0.48 : 0.2),
                    width: 1,
                  ),
                ),
                child: Icon(widget.icon, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.active ? Colors.white : Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceWaveAnimation extends StatefulWidget {
  const _VoiceWaveAnimation();

  @override
  State<_VoiceWaveAnimation> createState() => _VoiceWaveAnimationState();
}

class _VoiceWaveAnimationState extends State<_VoiceWaveAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _barHeight(int index, double t) {
    final shifted = (t + index * 0.16) % 1.0;
    final value = Curves.easeInOut.transform(shifted);
    return 14 + value * 28;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 44,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(5, (index) {
              return Container(
                width: 7,
                height: _barHeight(index, t),
                decoration: BoxDecoration(
                  color: const Color(0xFF3ED67D).withValues(alpha: 0.52 + index * 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
