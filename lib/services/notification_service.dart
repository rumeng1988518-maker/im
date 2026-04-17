import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 来电通知固定 ID，方便取消
const int _callNotificationId = 99999;

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

    await _plugin.initialize(settings);
    _initialized = true;

    // Request permissions on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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
      _notificationId++,
      senderName,
      body,
      details,
      payload: conversationId,
    );
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
}
