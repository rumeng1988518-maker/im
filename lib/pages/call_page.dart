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

class _CallPageState extends State<CallPage> with WidgetsBindingObserver {
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
  // 主叫方收到对方接听确认后置 true，用于过滤竞态残留的 call:timeout
  bool _callAccepted = false;
  final Completer<void> _audioReady = Completer<void>();
  Map<String, dynamic>? _pendingRemoteSdp;
  String _statusText = '正在拨号...';
  Timer? _durationTimer;
  Timer? _offerDelayTimer;
  int _durationSeconds = 0;

  // ── 弱网检测与 ICE 重启 ──
  Timer? _statsTimer;
  Timer? _iceRestartTimer;
  bool _iceRestarting = false;
  bool _networkPoor = false;
  int _consecutivePoorCount = 0;  // 连续差网计数
  int _prevBytesReceived = 0;
  int _prevPacketsReceived = 0;
  int _prevPacketsLost = 0;
  Timer? _trackCheckTimer;
  static const int _poorThreshold = 3;       // 连续3次检测差则显示提示
  static const int _iceRestartDelaySec = 5;   // 断连后5秒尝试 ICE 重启
  static const int _iceRestartTimeoutSec = 15; // ICE 重启15秒超时

  late final Function(dynamic) _onAcceptedHandler;
  late final Function(dynamic) _onRejectedHandler;
  late final Function(dynamic) _onEndedHandler;
  late final Function(dynamic) _onTimeoutHandler;
  late final Function(dynamic) _onSdpHandler;
  late final Function(dynamic) _onIceHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

      // 语音通话默认听筒，视频通话默认扬声器
      if (!kIsWeb) {
        final useSpeaker = widget.callType == 'video';
        try {
          await Helper.setSpeakerphoneOn(useSpeaker);
          _speakerEnabled = useSpeaker;
        } catch (_) {}
      }

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

    // 部分安卓设备只触发 onAddStream，不触发 onTrack；
    // 另一种场景：onTrack 对音频触发时流里还没有视频轨，onTrack 对视频触发时
    // event.streams 为空，导致 _remoteStream 有值但 _remoteHasVideo=false，
    // 此时 onAddStream 带着完整流来，不能因为 _remoteStream != null 就跳过。
    // 规则：只要 _remoteHasVideo 尚未为 true，就用 onAddStream 的流覆盖更新。
    // ignore: deprecated_member_use
    peer.onAddStream = (stream) {
      if (_remoteStream != null && _remoteHasVideo) return; // 已有完整流，跳过
      _remoteStream = stream;
      _remoteRenderer.srcObject = stream;
      final hasVideo = stream.getVideoTracks().isNotEmpty;
      if (mounted) {
        setState(() {
          _remoteHasVideo = hasVideo;
        });
      }
    };

    // 远程流移除时清理
    // ignore: deprecated_member_use
    peer.onRemoveStream = (stream) {
      if (mounted) {
        setState(() {
          _remoteHasVideo = false;
        });
      }
    };

    peer.onConnectionState = (state) {
      if (!mounted) return;
      debugPrint('[CallPage] connectionState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _cancelPendingIceRestart();
        _onIceRecovered();
        _markConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // 连接彻底失败，尝试一次 ICE 重启
        _attemptIceRestart();
        setState(() => _statusText = '连接失败，正在重试...');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _scheduleIceRestart();
        setState(() => _statusText = '网络波动，恢复中...');
      }
    };

    // 监听 ICE 连接状态（比 connectionState 更早触发）
    peer.onIceConnectionState = (state) {
      if (!mounted) return;
      debugPrint('[CallPage] iceConnectionState: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _scheduleIceRestart();
        if (_connected) {
          setState(() => _statusText = '网络波动，恢复中...');
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _attemptIceRestart();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _cancelPendingIceRestart();
        _onIceRecovered();
      }
    };

    _peer = peer;
  }

  Future<void> _openLocalAudio() async {
    final constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStream = stream;

    for (final track in stream.getAudioTracks()) {
      _audioTrack = track;
      await _peer?.addTrack(track, stream);
    }
    if (!_audioReady.isCompleted) _audioReady.complete();
  }

  Future<void> _createAndSendOffer({bool force = false, bool iceRestart = false}) async {
    if (_peer == null) return;
    if (!force && !iceRestart && _initialOfferSent) return;
    // 等待本地音频就绪（首次授权可能有延迟）
    await _audioReady.future;
    if (!force && !iceRestart) {
      _initialOfferSent = true;
    }
    final offer = await _peer!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
      if (iceRestart) 'iceRestart': true,
    });
    if (offer.sdp == null || offer.sdp!.isEmpty) return;

    // 优化 SDP：启用 Opus FEC/DTX 提升弱网音频质量
    final optimizedOffer = RTCSessionDescription(
      _optimizeSdpForWeakNetwork(offer.sdp!),
      offer.type,
    );
    await _peer!.setLocalDescription(optimizedOffer);
    _socket.emit('call:sdp', {
      'callId': widget.callId,
      'targetUserId': widget.peerUserId,
      'sdpType': 'offer',
      'sdp': optimizedOffer.sdp,
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

    // 优化 SDP：启用 Opus FEC/DTX 提升弱网音频质量
    final optimizedAnswer = RTCSessionDescription(
      _optimizeSdpForWeakNetwork(answer.sdp!),
      answer.type,
    );
    await _peer!.setLocalDescription(optimizedAnswer);
    _socket.emit('call:sdp', {
      'callId': widget.callId,
      'targetUserId': widget.peerUserId,
      'sdpType': 'answer',
      'sdp': optimizedAnswer.sdp,
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
      _networkPoor = false;
    });

    _durationTimer?.cancel();
    _durationSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _durationSeconds += 1;
      });
    });

    // 启动网络质量监控
    _startStatsMonitor();
    // 启动远程音频轨道健康监控
    _startTrackHealthMonitor();

    // ── 修复4：视频通话连接后重新确认扬声器路由 ──
    // 部分国产安卓 ROM 在系统弹出权限弹窗期间会重置音频路由，
    // 导致视频通话接通后声音仍走听筒，用户以为没有声音。
    if (!kIsWeb && widget.callType == 'video') {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted || !_connected) return;
        try {
          Helper.setSpeakerphoneOn(true);
          if (mounted) setState(() => _speakerEnabled = true);
        } catch (_) {}
      });
    }

    // ── 修复5：连接后 6 秒内检测视频是否就绪 ──
    // 若视频通话连接后超过 6 秒仍无远端视频画面，说明流信息未能正常更新，
    // 尝试重新同步 renderer（处理 onTrack/onAddStream 未触发的边缘情况）。
    if (widget.callType == 'video') {
      Timer(const Duration(seconds: 6), () {
        if (!mounted || !_connected) return;
        if (!_remoteHasVideo) {
          final stream = _remoteStream;
          if (stream != null && stream.getVideoTracks().isNotEmpty) {
            debugPrint('[CallPage] Post-connect video sync: stream has video tracks but _remoteHasVideo=false, fixing');
            _remoteRenderer.srcObject = stream;
            if (mounted) setState(() => _remoteHasVideo = true);
          } else if (stream != null) {
            // 流存在但确实无视频轨道，提示用户对方未开启摄像头
            debugPrint('[CallPage] Post-connect: no remote video tracks in stream');
          }
        }
      });
    }
  }

  // ── 网络质量监控 ──

  void _startStatsMonitor() {
    _statsTimer?.cancel();
    _prevBytesReceived = 0;
    _prevPacketsReceived = 0;
    _prevPacketsLost = 0;
    _consecutivePoorCount = 0;

    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _peer == null) return;
      _checkNetworkQuality();
    });
  }

  Future<void> _checkNetworkQuality() async {
    if (_peer == null) return;
    try {
      final stats = await _peer!.getStats();
      int totalBytesReceived = 0;
      int totalPacketsReceived = 0;
      int totalPacketsLost = 0;
      double? currentRtt;

      for (final report in stats) {
        final values = report.values;
        // 入站 RTP 音频统计
        if (report.type == 'inbound-rtp' || values['type'] == 'inbound-rtp') {
          final kind = values['kind']?.toString() ?? values['mediaType']?.toString() ?? '';
          if (kind != 'audio') continue;
          totalBytesReceived += (values['bytesReceived'] as num?)?.toInt() ?? 0;
          totalPacketsReceived += (values['packetsReceived'] as num?)?.toInt() ?? 0;
          totalPacketsLost += (values['packetsLost'] as num?)?.toInt() ?? 0;
        }
        // RTT 从 candidate-pair
        if (report.type == 'candidate-pair' || values['type'] == 'candidate-pair') {
          final rtt = values['currentRoundTripTime'];
          if (rtt is num && rtt > 0) {
            currentRtt = rtt.toDouble();
          }
        }
      }

      // 计算增量
      final deltaPacketsReceived = totalPacketsReceived - _prevPacketsReceived;
      final deltaPacketsLost = totalPacketsLost - _prevPacketsLost;
      final deltaBytesReceived = totalBytesReceived - _prevBytesReceived;

      _prevBytesReceived = totalBytesReceived;
      _prevPacketsReceived = totalPacketsReceived;
      _prevPacketsLost = totalPacketsLost;

      // 判断网络是否差：
      // 1. 丢包率 > 15%
      // 2. 或 RTT > 400ms
      // 3. 或完全没有收到数据
      bool isPoor = false;
      if (deltaPacketsReceived + deltaPacketsLost > 0) {
        final lossRate = deltaPacketsLost / (deltaPacketsReceived + deltaPacketsLost);
        if (lossRate > 0.15) isPoor = true;
      }
      if (currentRtt != null && currentRtt > 0.4) isPoor = true;
      if (_connected && deltaBytesReceived == 0 && _prevBytesReceived > 0) isPoor = true;

      if (isPoor) {
        _consecutivePoorCount++;
      } else {
        _consecutivePoorCount = 0;
      }

      if (!mounted) return;
      final shouldShowPoor = _consecutivePoorCount >= _poorThreshold;
      if (shouldShowPoor != _networkPoor) {
        setState(() => _networkPoor = shouldShowPoor);
      }
    } catch (e) {
      debugPrint('[CallPage] getStats error: $e');
    }
  }

  // ── ICE 重启与恢复 ──

  /// 取消尚未触发的 ICE 重启定时器（ICE 自然恢复时调用）
  void _cancelPendingIceRestart() {
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
  }

  void _scheduleIceRestart() {
    if (_iceRestarting || _hangingUp) return;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = Timer(Duration(seconds: _iceRestartDelaySec), () {
      if (!mounted || _hangingUp) return;
      _attemptIceRestart();
    });
  }

  void _attemptIceRestart() {
    if (_iceRestarting || _hangingUp || _peer == null) return;
    _iceRestarting = true;
    debugPrint('[CallPage] Attempting ICE restart...');

    // 设置超时：若 ICE 重启后仍无法恢复，提示用户
    _iceRestartTimer?.cancel();
    _iceRestartTimer = Timer(Duration(seconds: _iceRestartTimeoutSec), () {
      if (!mounted) return;
      if (_iceRestarting) {
        setState(() => _statusText = '网络恢复失败');
      }
    });

    // 发起 ICE restart offer
    _createAndSendOffer(force: true, iceRestart: true).catchError((e) {
      debugPrint('[CallPage] ICE restart failed: $e');
    });
  }

  void _onIceRecovered() {
    if (!_iceRestarting) return;
    _iceRestarting = false;
    _iceRestartTimer?.cancel();
    debugPrint('[CallPage] ICE connection recovered');
    if (mounted && _connected) {
      setState(() {
        _statusText = '通话中';
        _networkPoor = false;
      });
      _consecutivePoorCount = 0;
    }
  }

  // ── 远程音频轨道健康检查 ──

  void _startTrackHealthMonitor() {
    _trackCheckTimer?.cancel();
    _trackCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_connected) return;
      _checkRemoteAudioHealth();
    });
  }

  void _checkRemoteAudioHealth() {
    final stream = _remoteStream;
    if (stream == null) return;

    final audioTracks = stream.getAudioTracks();
    if (audioTracks.isEmpty) {
      debugPrint('[CallPage] Remote audio track missing');
    } else {
      for (final track in audioTracks) {
        // 如果远程音频轨道被意外禁用（部分安卓设备弱网后出现），重新启用
        if (!track.enabled) {
          debugPrint('[CallPage] Remote audio track disabled, re-enabling');
          track.enabled = true;
        }
      }
    }

    // 检查远程视频轨道（部分安卓设备在弱网恢复后视频轨道可能被禁用）
    if (widget.callType == 'video') {
      final videoTracks = stream.getVideoTracks();
      for (final track in videoTracks) {
        if (!track.enabled) {
          debugPrint('[CallPage] Remote video track disabled, re-enabling');
          track.enabled = true;
          if (mounted && !_remoteHasVideo) {
            setState(() => _remoteHasVideo = true);
          }
        }
      }
    }

    // 确保本地音频轨道仍然活跃（未被系统中断）
    if (_audioTrack != null && !_muted && !_audioTrack!.enabled) {
      debugPrint('[CallPage] Local audio track unexpectedly disabled, re-enabling');
      _audioTrack!.enabled = true;
    }
  }

  // ── 应用生命周期处理 ──

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台回来，检查音频轨道和连接状态
      _checkRemoteAudioHealth();
      // 确保音频路由未改变
      if (!kIsWeb && _connected) {
        try {
          Helper.setSpeakerphoneOn(_speakerEnabled);
        } catch (_) {}
      }
      // 检查 ICE 连接状态，如果断了则触发重启
      if (_peer != null && _connected) {
        _peer!.getConnectionState().then((connState) {
          if (!mounted) return;
          if (connState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              connState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _attemptIceRestart();
          }
        }).catchError((_) {});
      }
    }
  }

  // ── SDP 优化：启用 Opus FEC 和 DTX 以增强弱网抗丢包能力 ──

  String _optimizeSdpForWeakNetwork(String sdp) {
    // 在 Opus codec 的 fmtp 行中添加:
    //   useinbandfec=1  → 前向纠错，接收端可从后续包恢复丢失的音频帧
    //   usedtx=1        → 静音时不传输，节省带宽
    //   maxaveragebitrate=24000 → 限制平均码率为24kbps，减少弱网压力
    //   stereo=0        → 单声道，通话不需要立体声
    final lines = sdp.split('\r\n');
    final result = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      result.add(line);

      // 找到 Opus 的 fmtp 行
      if (line.startsWith('a=fmtp:') && i > 0) {
        // 检查前面是否有 opus rtpmap
        final fmtpPt = RegExp(r'^a=fmtp:(\d+)').firstMatch(line)?.group(1);
        if (fmtpPt != null) {
          // 查找对应的 rtpmap 确认是 opus
          final isOpus = lines.any((l) =>
              l.toLowerCase().contains('a=rtpmap:$fmtpPt opus/'));
          if (isOpus) {
            // 在 fmtp 行末尾追加参数（如果不存在）
            final idx = result.length - 1;
            var fmtpLine = result[idx];
            if (!fmtpLine.contains('useinbandfec')) {
              fmtpLine += ';useinbandfec=1';
            }
            if (!fmtpLine.contains('usedtx')) {
              fmtpLine += ';usedtx=1';
            }
            if (!fmtpLine.contains('stereo')) {
              fmtpLine += ';stereo=0';
            }
            if (!fmtpLine.contains('maxaveragebitrate')) {
              fmtpLine += ';maxaveragebitrate=24000';
            }
            result[idx] = fmtpLine;
          }
        }
      }
    }
    return result.join('\r\n');
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

    // 对方已接听，后续到来的 call:timeout 属于竞态残留，应忽略
    _callAccepted = true;

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

    // 被叫方进入 CallPage 时已完成接听，收到超时事件属于竞态残留，忽略
    if (!widget.isCaller) return;
    // 主叫方：若已收到接听确认则忽略（服务端竞态：超时与接听同时发生）
    if (_callAccepted) return;

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
      // syncApi=false 表示初始化阶段（非用户手动点击），给出更友好的引导提示
      final msg = syncApi
          ? ErrorMessage.from(e, fallback: '开启摄像头失败')
          : '摄像头启动失败，通话将以语音模式继续\n可点击「开启摄像头」按钮重试';
      AppToast.show(context, msg, duration: const Duration(seconds: 4));
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
    if (_connected && !_iceRestarting) {
      final mm = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
      final ss = (_durationSeconds % 60).toString().padLeft(2, '0');
      return '通话中  $mm:$ss';
    }
    return _statusText;
  }

  Map<String, dynamic> _normalizeRtcConfig(Map<String, dynamic> source) {
    final rawIceServers = source['iceServers'];
    List<Map<String, dynamic>> iceServers;

    if (rawIceServers is! List || rawIceServers.isEmpty) {
      iceServers = _fallbackIceServers;
    } else {
      iceServers = <Map<String, dynamic>>[];
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
        iceServers = _fallbackIceServers;
      }
    }

    return {
      'iceServers': iceServers,
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceCandidatePoolSize': 1,
    };
  }

  /// 客户端兜底 ICE 服务器列表（服务端未下发或解析失败时使用）
  /// 同时包含国内可访问的 STUN 和国际 STUN，ICE 框架会并行探测所有候选。
  static const List<Map<String, dynamic>> _fallbackIceServers = [
    // 国内可达 STUN（腾讯、小米）
    {'urls': ['stun:stun.qq.com:3478']},
    {'urls': ['stun:stun.miwifi.com:3478']},
    // 国际 STUN（对未被墙的网络）
    {'urls': ['stun:stun.l.google.com:19302']},
    {'urls': ['stun:stun1.l.google.com:19302']},
  ];

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
                // 弱网提示横幅
                if (_networkPoor)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xCCFF8800),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.signal_cellular_connected_no_internet_0_bar, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('当前网络环境不佳', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
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
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _offerDelayTimer?.cancel();
    _statsTimer?.cancel();
    _iceRestartTimer?.cancel();
    _trackCheckTimer?.cancel();
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
