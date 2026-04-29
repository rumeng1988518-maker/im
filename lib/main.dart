import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:im_client/config/app_config.dart';
import 'package:im_client/config/theme.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/services/api_client.dart';
import 'package:im_client/services/socket_service.dart';
import 'package:im_client/providers/chat_provider.dart';
import 'package:im_client/providers/contacts_provider.dart';
import 'package:im_client/providers/call_provider.dart';
import 'package:im_client/pages/landing_page.dart';
import 'package:im_client/pages/home_page.dart';
import 'package:im_client/pages/call_page.dart';
import 'package:im_client/utils/app_toast.dart';
import 'package:im_client/utils/error_message.dart';
import 'package:im_client/services/notification_service.dart';
import 'package:im_client/services/foreground_service.dart';
import 'package:im_client/utils/notification_sound.dart';
import 'package:im_client/utils/call_permission_helper.dart';
import 'package:im_client/services/push_token_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 顺序探活备用服务器，选第一个可达的地址（5s 超时）
  await AppConfig.resolveHost();

  // Initialize Firebase for Android FCM
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Firebase] init error: $e');
    }
  }
  await NotificationService().init();
  await ForegroundService.init();
  final auth = AuthService();
  await auth.init();

  // token 有效性由 ApiClient 拦截器在首次请求时自动检测：
  // 若 token 过期 → 自动 refresh → 若 refresh 失败 → 自动 logout
  // 不在此处创建额外 ApiClient，避免与主 ApiClient 并发刷新 token 导致竞态

  runApp(IMApp(auth: auth));
}

class IMApp extends StatefulWidget {
  final AuthService auth;
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const IMApp({super.key, required this.auth});

  @override
  State<IMApp> createState() => _IMAppState();
}

class _IMAppState extends State<IMApp> {
  late final SocketService _socketService;
  late final ApiClient _apiClient;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _socketService = SocketService();
    _apiClient = ApiClient(widget.auth, baseUrl: AppConfig.baseUrl);
  }

  void _connectAndLoad(BuildContext context) {
    if (_initialized) return;
    _initialized = true;
    final token = widget.auth.token;
    if (token != null) {
      _socketService.connect(token);
      context.read<ChatProvider>().loadConversations().catchError((_) {});
      context.read<ContactsProvider>().loadFriends().catchError((_) {});
      context.read<ContactsProvider>().loadFriendRequests().catchError((_) {});
      // 首次登录请求忽略电池优化
      ForegroundService.requestBatteryOptimization();
      // 检查通知权限（国产 Android 可能默认关闭）
      _checkNotificationPermission();
      // 上报 push token（iOS APNs / Android FCM）
      _uploadPushToken();
      // 监听 token 刷新/延迟到达（Android FCM refresh + iOS native push）
      PushTokenService.onTokenRefresh((newToken) {
        debugPrint('[Push] Token refresh/arrived: ${newToken.substring(0, 8)}...');
        _uploadPushTokenWithValue(newToken);
      });
    }
  }

  Future<void> _checkNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Future.delayed(const Duration(seconds: 3));
      final enabled = await NotificationService().areNotificationsEnabled();
      if (!enabled && mounted) {
        final ctx = context;
        if (!ctx.mounted) return;
        showDialog(
          context: ctx,
          builder: (c) => AlertDialog(
            title: const Text('通知权限未开启'),
            content: const Text('通知权限未开启，您可能无法收到新消息提醒。请在设置中开启通知权限。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('稍后再说')),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  NotificationService().openNotificationSettings();
                },
                child: const Text('去开启'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('[Main] check notification permission error: $e');
    }
  }

  Future<void> _uploadPushToken() async {
    try {
      final pushToken = await PushTokenService.getToken();
      if (pushToken != null && pushToken.isNotEmpty) {
        await _uploadPushTokenWithValue(pushToken);
      } else {
        debugPrint('[Push] No push token available, will rely on onTokenRefresh callback');
      }
    } catch (e) {
      debugPrint('[Push] Upload push token error: $e');
    }
  }

  Future<void> _uploadPushTokenWithValue(String pushToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('im_device_id');
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        await prefs.setString('im_device_id', deviceId);
      }
      await _apiClient.put('/users/me/push-token', data: {
        'pushToken': pushToken,
        'deviceId': deviceId,
        'platform': PushTokenService.platform,
      });
      debugPrint('[Push] Token uploaded (${PushTokenService.platform}): ${pushToken.substring(0, 8)}...');
    } catch (e) {
      debugPrint('[Push] Upload error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        Provider.value(value: _apiClient),
        Provider.value(value: _socketService),
        ChangeNotifierProvider(create: (_) => CallProvider(api: _apiClient, socket: _socketService, auth: widget.auth)),
        ChangeNotifierProvider(create: (_) => ChatProvider(api: _apiClient, socket: _socketService)),
        ChangeNotifierProvider(create: (_) => ContactsProvider(api: _apiClient, socket: _socketService)),
      ],
      child: MaterialApp(
        navigatorKey: IMApp.navigatorKey,
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => _IncomingCallGate(child: child ?? const SizedBox.shrink()),
        home: Consumer<AuthService>(
          builder: (context, auth, _) {
            if (!auth.initialized) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (auth.isLoggedIn) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _connectAndLoad(context);
              });
              return const HomePage();
            }
            // 已退出登录，重置标记以便下次登录时重新连接
            _initialized = false;
            _socketService.disconnect();
            // 清除旧会话数据，避免重新登录时显示上一个账号的数据
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try {
                context.read<ChatProvider>().clearAll();
                context.read<ContactsProvider>().clearAll();
              } catch (_) {}
            });
            return const LandingPage();
          },
        ),
      ),
    );
  }
}

class _IncomingCallGate extends StatefulWidget {
  final Widget child;

  const _IncomingCallGate({required this.child});

  @override
  State<_IncomingCallGate> createState() => _IncomingCallGateState();
}

class _IncomingCallGateState extends State<_IncomingCallGate> with WidgetsBindingObserver {
  bool _acting = false;
  bool _kickHandled = false;
  bool _ringing = false;
  DateTime? _lastPaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 监听被踢下线事件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenKick();
      _listenAuthLogout();
    });
    // 注册前台服务心跳回调，后台时每 15 秒检查 socket 连接
    ForegroundService.onKeepAliveTick = _onKeepAliveTick;
  }

  /// 监听 AuthService logout —— 当 API 拦截器因 token 失效调用 logout 时跳转登录页
  void _listenAuthLogout() {
    try {
      final auth = context.read<AuthService>();
      auth.addListener(_onAuthChanged);
    } catch (_) {}
  }

  void _onAuthChanged() {
    try {
      final auth = context.read<AuthService>();
      if (!auth.isLoggedIn && auth.initialized) {
        // token 被清除（API 401 触发的 logout）
        final nav = IMApp.navigatorKey.currentState;
        if (nav != null) {
          nav.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LandingPage()),
            (_) => false,
          );
        }
      }
    } catch (_) {}
  }

  void _listenKick() {
    try {
      final socket = context.read<SocketService>();
      socket.on('auth:kicked', _onKicked);
      // 重新连接时重置踢下线标记，以便再次被踢时能正常处理
      socket.on('connect', _onSocketConnect);
    } catch (_) {}
  }

  void _onSocketConnect(dynamic _) {
    _kickHandled = false;
  }

  void _onKicked(dynamic data) async {
    if (_kickHandled) return;
    _kickHandled = true;

    final reason = (data is Map ? data['reason'] : null) ?? '您的账号已在其他设备登录';

    // 断开 socket 并清除登录态
    try {
      final socket = context.read<SocketService>();
      socket.disconnect();
    } catch (_) {}

    try {
      final auth = context.read<AuthService>();
      await auth.logout();
    } catch (_) {}

    // auth.logout() 触发 Consumer 重建，同时显式导航到 LandingPage 确保界面切换
    final nav = IMApp.navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (_) => false,
      );
      // 短暂延迟确保页面切换完成后再弹提示
      await Future.delayed(const Duration(milliseconds: 300));
      final ctx = nav.context;
      if (ctx.mounted) {
        showDialog(
          context: ctx,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('下线通知'),
            content: Text(reason),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ForegroundService.onKeepAliveTick = null;
    try {
      context.read<AuthService>().removeListener(_onAuthChanged);
    } catch (_) {}
    try {
      final socket = context.read<SocketService>();
      socket.off('auth:kicked');
      socket.off('connect', _onSocketConnect);
    } catch (_) {}
    super.dispose();
  }

  /// 前台服务每 15 秒触发一次，在后台时检查并恢复 socket 连接
  void _onKeepAliveTick() {
    try {
      final auth = context.read<AuthService>();
      if (!auth.isLoggedIn) return;
      final token = auth.token;
      if (token == null) return;
      final socket = context.read<SocketService>();
      if (!socket.isConnected) {
        debugPrint('[KeepAlive] socket disconnected, reconnecting...');
        socket.ensureConnected(token);
      }
      // 后台轮询：通过 API 检查新消息并弹本地通知（Android + iOS 都需要）
      // Android 即使有前台服务，socket 也可能被国产 ROM 网络管理断开导致丢消息
      context.read<ChatProvider>().pollAndNotify().catchError((_) {});
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _lastPaused = DateTime.now();
      // 通知服务端用户进入后台（服务端对后台用户也发推送）
      try {
        final socket = context.read<SocketService>();
        if (socket.isConnected) {
          socket.emit('user:background', {});
        }
      } catch (_) {}
      // 进入后台：启动保活（iOS 预热过的播放器只需 resume，很快）
      _startBackgroundService();
    } else if (state == AppLifecycleState.resumed) {
      // 通知服务端用户回到前台
      try {
        final socket = context.read<SocketService>();
        if (socket.isConnected) {
          socket.emit('user:foreground', {});
        }
      } catch (_) {}
      // 先恢复连接和数据，再停止后台保活
      _reconnectAndRefresh();
      ForegroundService.stop();
    }
  }

  /// 异步启动后台保活服务（iOS 上 await 确保音频播放器真正 resume 后再继续）
  Future<void> _startBackgroundService() async {
    try {
      await ForegroundService.start();
    } catch (e) {
      debugPrint('[KeepAlive] start background service error: $e');
    }
  }

  void _reconnectAndRefresh() {
    try {
      final auth = context.read<AuthService>();
      if (!auth.isLoggedIn) return;
      final token = auth.token;
      if (token == null) return;

      // 确保 WebSocket 连接
      final socket = context.read<SocketService>();
      socket.ensureConnected(token);

      // 如果后台超过 3 秒，主动刷新数据（弥补可能丢失的推送）
      final paused = _lastPaused;
      if (paused != null && DateTime.now().difference(paused).inSeconds > 3) {
        final chatProvider = context.read<ChatProvider>();
        chatProvider.loadConversations(force: true).catchError((_) {});
        context.read<ContactsProvider>().loadFriends().catchError((_) {});
        // 如果用户正在查看某个会话，也刷新该会话的消息
        final currentConv = chatProvider.currentConvId;
        if (currentConv != null) {
          chatProvider.loadMessages(currentConv, force: true).catchError((_) {});
        }
      }
    } catch (_) {}
  }

  Future<void> _accept(CallProvider callProvider) async {
    if (_acting) return;
    setState(() => _acting = true);

    try {
      final callType = callProvider.incomingCall?.callType ?? 'voice';
      final hasPermission =
          await CallPermissionHelper.requestCallPermissions(context, callType);
      if (!mounted) return;
      if (!hasPermission) {
        setState(() => _acting = false);
        return;
      }

      final payload = await callProvider.acceptIncomingCall();
      if (!mounted) return;

      final nav = IMApp.navigatorKey.currentState;
      if (nav == null) return;

      await nav.push(
        MaterialPageRoute(
          builder: (_) => CallPage(
            callId: payload.callId,
            peerUserId: payload.peerUserId,
            peerName: payload.peerName,
            peerAvatarUrl: payload.peerAvatarUrl,
            callType: payload.callType,
            isCaller: payload.isCaller,
            rtcConfig: payload.rtcConfig,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '接听失败，请稍后重试'));
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  Future<void> _reject(CallProvider callProvider) async {
    if (_acting) return;
    setState(() => _acting = true);

    try {
      await callProvider.rejectIncomingCall();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, ErrorMessage.from(e, fallback: '拒绝失败，请稍后重试'));
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, callProvider, _) {
        final incoming = callProvider.incomingCall;
        if (incoming == null) {
          if (_ringing) {
            _ringing = false;
            NotificationSound.stopRingtone();
          }
          return widget.child;
        }

        if (!_ringing) {
          _ringing = true;
          NotificationSound.playRingtone();
        }

        return Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.42),
                alignment: Alignment.center,
                child: Container(
                  width: 312,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        incoming.callType == 'video' ? '视频来电' : '语音来电',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        incoming.callerName,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _acting ? null : () => _reject(callProvider),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                              child: const Text('拒绝'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _acting ? null : () => _accept(callProvider),
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                              child: _acting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('接听'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
