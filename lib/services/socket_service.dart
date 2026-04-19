import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:im_client/config/app_config.dart';

class SocketService {
  io.Socket? _socket;
  String? _token;
  bool _connecting = false;
  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(seconds: 15);

  final Map<String, List<Function(dynamic)>> _listeners = {};

  bool get isConnected => _socket?.connected ?? false;
  bool get isConnecting => _connecting;

  /// 确保连接存活，如果断线则重新连接
  void ensureConnected(String token) {
    _token = token;
    if (isConnected) return;
    if (_socket != null) {
      // socket.io 可能正在自动重连，但国产 ROM 可能导致重连卡死
      // 检查是否长时间未连接成功，若超过 30 秒则强制重建连接
      final lastDisconnect = _lastDisconnectTime;
      if (lastDisconnect != null &&
          DateTime.now().difference(lastDisconnect).inSeconds > 30) {
        debugPrint('[WS] ensureConnected: stale socket, force reconnect');
        connect(token);
        return;
      }
      if (!_connecting) {
        _socket!.connect();
      }
    } else {
      connect(token);
    }
  }

  DateTime? _lastDisconnectTime;

  void connect(String token) {
    if (_token == token && (isConnected || _connecting)) {
      return;
    }

    _token = token;
    disconnect();
    _connecting = true;

    final opts = io.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .setAuth({'token': token})
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .build();

    _socket = io.io(AppConfig.wsUrl, opts);

    _socket!.onConnect((_) {
      _connecting = false;
      _lastDisconnectTime = null;
      debugPrint('[WS] connected');
      _startHeartbeat();
      _emitLocal('connect', null);
    });

    _socket!.onConnectError((err) {
      _connecting = false;
      debugPrint('[WS] connect error: $err');
      final errStr = err.toString();
      if (errStr.contains('令牌无效') || errStr.contains('已过期') || errStr.contains('认证失败')) {
        debugPrint('[WS] auth failed, stopping reconnection');
        _stopHeartbeat();
        _socket?.disconnect();
        _emitLocal('auth:kicked', {'reason': '登录已过期，请重新登录'});
      }
    });

    _socket!.onError((err) {
      debugPrint('[WS] error: $err');
    });

    _socket!.onDisconnect((_) {
      _connecting = false;
      _lastDisconnectTime = DateTime.now();
      debugPrint('[WS] disconnected');
      _stopHeartbeat();
      _emitLocal('disconnect', null);
    });

    // Listen for message events
    _socket!.on('message:new', (data) => _emitLocal('message:new', data));
    _socket!.on('message:revoked', (data) => _emitLocal('message:revoked', data));
    _socket!.on('message:read', (data) => _emitLocal('message:read', data));
    _socket!.on('typing:start', (data) => _emitLocal('typing:start', data));
    _socket!.on('typing:stop', (data) => _emitLocal('typing:stop', data));
    _socket!.on('friend:request', (data) => _emitLocal('friend:request', data));
    _socket!.on('friend:request-new', (data) => _emitLocal('friend:request-new', data));
    _socket!.on('friend:added', (data) => _emitLocal('friend:added', data));
    _socket!.on('friend:request-rejected', (data) => _emitLocal('friend:request-rejected', data));
    _socket!.on('friend:status', (data) => _emitLocal('friend:status', data));
    _socket!.on('conversation:created', (data) => _emitLocal('conversation:created', data));
    _socket!.on('conversation:updated', (data) => _emitLocal('conversation:updated', data));
    _socket!.on('conversation:removed', (data) => _emitLocal('conversation:removed', data));
    _socket!.on('conversation:member-added', (data) => _emitLocal('conversation:member-added', data));
    _socket!.on('conversation:member-removed', (data) => _emitLocal('conversation:member-removed', data));
    _socket!.on('conversation:dismissed', (data) => _emitLocal('conversation:dismissed', data));
    _socket!.on('conversation:owner-transferred', (data) => _emitLocal('conversation:owner-transferred', data));
    _socket!.on('red_packet:claimed', (data) => _emitLocal('red_packet:claimed', data));
    _socket!.on('call:incoming', (data) => _emitLocal('call:incoming', data));
    _socket!.on('call:accepted', (data) => _emitLocal('call:accepted', data));
    _socket!.on('call:rejected', (data) => _emitLocal('call:rejected', data));
    _socket!.on('call:ended', (data) => _emitLocal('call:ended', data));
    _socket!.on('call:timeout', (data) => _emitLocal('call:timeout', data));
    _socket!.on('call:sdp', (data) => _emitLocal('call:sdp', data));
    _socket!.on('call:ice-candidate', (data) => _emitLocal('call:ice-candidate', data));
    _socket!.on('auth:kicked', (data) => _emitLocal('auth:kicked', data));
  }

  void disconnect() {
    _connecting = false;
    _stopHeartbeat();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!isConnected && _token != null) {
        debugPrint('[WS] heartbeat: disconnected, attempting reconnect');
        ensureConnected(_token!);
      } else if (isConnected) {
        // 发送 ping 保持连接活跃，防止被国产 ROM 网络管理断开
        _socket?.emit('ping');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void on(String event, Function(dynamic) callback) {
    _listeners.putIfAbsent(event, () => []).add(callback);
  }

  void off(String event, [Function(dynamic)? callback]) {
    if (callback != null) {
      _listeners[event]?.remove(callback);
    } else {
      _listeners.remove(event);
    }
  }

  void _emitLocal(String event, dynamic data) {
    final cbs = _listeners[event];
    if (cbs != null) {
      for (final cb in List.from(cbs)) {
        cb(data);
      }
    }
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }
}
