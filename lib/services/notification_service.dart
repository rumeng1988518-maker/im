import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

      // Request permissions on Android 13+
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      // Request permissions on iOS
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
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

  /// 根据 conversationId 生成稳定的通知 ID（同一会话复用同一 ID，方便取消）
  int _convNotificationId(String? conversationId) {
    if (conversationId == null || conversationId.isEmpty) return _notificationId++;
    // 保持在安全正整数范围内，避开保留 ID
    return (conversationId.hashCode.abs() % 80000) + 10000;
  }

  Future<void> showMessageNotification({
    required String senderName,
    required String body,
    String? conversationId,
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'im_messages',
      '消息通知',
      channelDescription: '新消息通知',
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
      _convNotificationId(conversationId),
      senderName,
      body,
      details,
      payload: conversationId,
    );
  }

  /// 取消指定会话的通知（用户进入会话时调用）
  Future<void> cancelConversationNotification(String conversationId) async {
    if (!_initialized) return;
    await _plugin.cancel(_convNotificationId(conversationId));
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
      // Android: 通过一条静默通知的 number 属性设置角标数字
      // 大多数 Android 启动器（Samsung/Xiaomi/Huawei/OPPO）会读取 number 显示角标
      final androidDetails = AndroidNotificationDetails(
        'im_badge',
        '未读消息角标',
        channelDescription: '用于显示桌面图标未读数量',
        importance: Importance.min,
        priority: Priority.min,
        number: count,
        showWhen: false,
        playSound: false,
        enableVibration: false,
        ongoing: false,
        onlyAlertOnce: true,
        // 使通知几乎不可见但角标仍然生效
        visibility: NotificationVisibility.secret,
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
      // cancelAll 会清除所有通知，之后重新显示 keepAlive（如有需要）
      final activeNotifications = await _plugin.getActiveNotifications();
      for (final n in activeNotifications) {
        final id = n.id;
        if (id == null) continue;
        // 保留 keepAlive 和 call 通知
        if (id == keepAliveNotificationId || id == _callNotificationId) continue;
        await _plugin.cancel(id);
      }

      // iOS 额外清除角标
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
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
