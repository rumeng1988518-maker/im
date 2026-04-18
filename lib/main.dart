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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await ForegroundService.init();
  final auth = AuthService();
  await auth.init();

  // 启动时验证本地 token 是否仍有效
  if (auth.isLoggedIn) {
    try {
      final api = ApiClient(auth, baseUrl: AppConfig.baseUrl);
      await api.get('/users/profile');
    } catch (_) {
      // ApiClient 拦截器会在 token 失效(40101/40102/40103)时自动 logout
      // 网络超时等非认证错误不清除登录态，保留离线可用性
    }
  }

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
    });
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
    try {
      final socket = context.read<SocketService>();
      socket.off('auth:kicked');
      socket.off('connect', _onSocketConnect);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _lastPaused = DateTime.now();
      // 进入后台：启动 Android 前台服务保持进程存活
      ForegroundService.start();
    } else if (state == AppLifecycleState.resumed) {
      // 回到前台：停止前台服务
      ForegroundService.stop();
      // 恢复 WebSocket 连接并刷新数据
      _reconnectAndRefresh();
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
        context.read<ChatProvider>().loadConversations().catchError((_) {});
        context.read<ContactsProvider>().loadFriends().catchError((_) {});
      }
    } catch (_) {}
  }

  Future<void> _accept(CallProvider callProvider) async {
    if (_acting) return;
    setState(() => _acting = true);

    try {
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
