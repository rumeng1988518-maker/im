import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// 来电通知固定 ID，方便取消
const int _callNotificationId = 99999;
/// 角标通知固定 ID
const int _badgeNotificationId = 99998;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationId = 0;
  // 跟踪每个会话的活跃通知 ID，用于进入会话时取消
  final Map<String, List<int>> _convNotificationIds = {};

  Future<void> init() async {
    if (_initialized || kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(settings);
      _initialized = true;

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      // Request permissions on Android 13+
      await androidImpl?.requestNotificationsPermission();

      // 删除旧通道（importance 变更后旧通道不会生效）
      await androidImpl?.deleteNotificationChannel('im_messages');

      // 预创建高优先级消息通道，确保在发送通知前通道已存在
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          'im_messages_v2',
          '消息通知',
          description: '新消息通知',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
          showBadge: true,
        ),
      );

      // Request permissions on iOS
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }
  }

  /// 检查通知权限是否已开启
  Future<bool> areNotificationsEnabled() async {
    if (!_initialized || kIsWeb) return false;
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        return await androidImpl.areNotificationsEnabled() ?? false;
      }
      return true; // iOS 默认返回 true
    } catch (_) {
      return false;
    }
  }

  /// 打开系统通知设置页面
  Future<void> openNotificationSettings() async {
    try {
      // 使用 Android Intent 打开应用通知设置
      const channel = MethodChannel('im_client/notification');
      await channel.invokeMethod('openNotificationSettings');
    } catch (_) {
      // fallback: 直接打开应用详情
      try {
        const channel = MethodChannel('im_client/notification');
        await channel.invokeMethod('openAppSettings');
      } catch (_) {}
    }
  }

  /// 持久前台通知（用于后台保活）
  static const int keepAliveNotificationId = 88888;

  Future<void> showKeepAliveNotification() async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'im_keepalive',
      '后台运行',
      channelDescription: '保持消息连接',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      playSound: false,
      enableVibration: false,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      keepAliveNotificationId,
      '内部通',
      '正在后台保持连接',
      details,
    );
  }

  Future<void> cancelKeepAliveNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(keepAliveNotificationId);
  }

  /// 每条消息都用新的递增 ID，确保国产 ROM 每次都弹出通知
  int _nextConvNotificationId(String? conversationId) {
    final id = _notificationId++;
    // 避开保留 ID 区间
    if (id == _callNotificationId || id == _badgeNotificationId || id == keepAliveNotificationId) {
      return _nextConvNotificationId(conversationId);
    }
    if (conversationId != null && conversationId.isNotEmpty) {
      _convNotificationIds.putIfAbsent(conversationId, () => []);
      _convNotificationIds[conversationId]!.add(id);
    }
    return id;
  }

  Future<void> showMessageNotification({
    required String senderName,
    required String body,
    String? conversationId,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'im_messages_v2',
      '消息通知',
      channelDescription: '新消息通知',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      channelShowBadge: true,
      ticker: '新消息',
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      _nextConvNotificationId(conversationId),
      senderName,
      body,
      details,
      payload: conversationId,
    );
  }

  /// 取消指定会话的所有通知（用户进入会话时调用）
  Future<void> cancelConversationNotification(String conversationId) async {
    if (!_initialized) return;
    final ids = _convNotificationIds.remove(conversationId);
    if (ids != null) {
      for (final id in ids) {
        await _plugin.cancel(id);
      }
    }
  }

  Future<void> showFriendRequestNotification({
    required String fromName,
    String? message,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'im_friend_requests',
      '好友申请',
      channelDescription: '好友申请通知',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      _notificationId++,
      '新的好友申请',
      message?.isNotEmpty == true ? '$fromName: $message' : '$fromName 请求添加你为好友',
      details,
    );
  }

  /// 来电通知（高优先级，持续振动+铃声）
  Future<void> showCallNotification({
    required String callerName,
    required String callType,
  }) async {
    if (!_initialized) return;

    final isVideo = callType == 'video';
    const androidDetails = AndroidNotificationDetails(
      'im_calls',
      '来电通知',
      channelDescription: '语音和视频来电通知',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      enableVibration: true,
      playSound: true,
      visibility: NotificationVisibility.public,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      _callNotificationId,
      isVideo ? '📹 视频来电' : '📞 语音来电',
      '$callerName 邀请你${isVideo ? "视频" : "语音"}通话',
      details,
      payload: 'call',
    );
  }

  /// 取消来电通知
  Future<void> cancelCallNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(_callNotificationId);
  }

  /// 更新桌面图标角标数字
  Future<void> updateBadge(int count) async {
    if (!_initialized) return;
    try {
      // 通过通知的 number 属性 + channelShowBadge 设置角标
      // 国产启动器(小米/华为/OPPO/vivo)需要 channelShowBadge=true + 可见的通知
      final androidDetails = AndroidNotificationDetails(
        'im_badge',
        '未读消息角标',
        channelDescription: '用于显示桌面图标未读数量',
        importance: Importance.low,
        priority: Priority.low,
        number: count,
        showWhen: false,
        playSound: false,
        enableVibration: false,
        ongoing: false,
        onlyAlertOnce: true,
        channelShowBadge: true,
      );
      final iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: true,
        presentSound: false,
        badgeNumber: count,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _plugin.show(_badgeNotificationId, '', '', details);
    } catch (e) {
      debugPrint('[NotificationService] updateBadge error: $e');
    }
  }

  /// 清除桌面图标角标及所有消息通知
  Future<void> clearBadge() async {
    if (!_initialized) return;
    try {
      // 取消角标通知和所有消息通知（保留 keepAlive 和 call 通知）
      final activeNotifications = await _plugin.getActiveNotifications();
      for (final n in activeNotifications) {
        final id = n.id;
        if (id == null) continue;
        if (id == keepAliveNotificationId || id == _callNotificationId) continue;
        await _plugin.cancel(id);
      }

      // iOS 额外清除角标
      if (!kIsWeb && Platform.isIOS) {
        await _plugin.show(
          _badgeNotificationId,
          null,
          null,
          const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: false,
              presentBadge: true,
              presentSound: false,
              badgeNumber: 0,
            ),
          ),
        );
        await _plugin.cancel(_badgeNotificationId);
      }
    } catch (e) {
      debugPrint('[NotificationService] clearBadge error: $e');
    }
  }
}
