import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../secrets/sealed_blobs.dart';
import 'courier.dart';
import 'vault.dart';

// ─────────────────────────────────────────────────────────────────────────
// SIGNAL BUS — Firebase Messaging + local notification channel
// ─────────────────────────────────────────────────────────────────────────
// Cold-tap push URL goes through the vault's cold-hint slot so the pilot
// picks it up on the next cold boot. Warm taps deliver via the
// [onIncomingUrl] callback — the WebView loads them directly without
// persisting.
//
// The notification channel id MUST match the AndroidManifest value
// `default_notification_channel_id` so OEM push shortcuts route to the
// right channel.
// ─────────────────────────────────────────────────────────────────────────

const String kBusChannelId = 'cb_updates_v1';
const String kBusChannelName = 'Spin updates';
const String _smallIcon = '@drawable/ic_notification';

@pragma('vm:entry-point')
Future<void> _backgroundSink(RemoteMessage message) async {
  // The OS renders the notification; the tap is picked up on resume or
  // on cold boot by `getInitialMessage`.
}

class SignalBus {
  SignalBus(this._vault);

  final SessionVault _vault;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fcm;
  String? _token;
  bool _wired = false;

  /// Warm-tap delivery — the WebView loads this URL directly.
  void Function(String url)? onIncomingUrl;

  /// FCM rotated the device token. The pilot re-posts the verdict so
  /// the backend can target this install.
  void Function(String token)? onTokenRotated;

  String? get token => _token;

  Future<void> wireUp() async {
    if (_wired) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _fcm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_backgroundSink);

      await _ensureLocalChannel();

      _token = await _fcm!.getToken();
      _fcm!.onTokenRefresh.listen((String t) {
        _token = t;
        onTokenRotated?.call(t);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmTap);

      final RemoteMessage? initial = await _fcm!.getInitialMessage();
      if (initial != null) _onColdTap(initial);

      _wired = true;
    } catch (_) {
      // Firebase not configured yet — push stays dormant.
    }
  }

  Future<void> _ensureLocalChannel() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings(_smallIcon);
    const DarwinInitializationSettings darwinInit =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        final String? payload = r.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final Map<String, dynamic> data =
              jsonDecode(payload) as Map<String, dynamic>;
          final String? url = data['url'] as String?;
          if (url != null && url.isNotEmpty) onIncomingUrl?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _local.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          kBusChannelId,
          kBusChannelName,
          description: unlockBusChannelDesc(),
          importance: Importance.high,
        ),
      );
    }
  }

  /// System permission prompt. Records an OS-denied flag so the invite
  /// screen never reappears after a hard "no".
  Future<bool> askForPermission() async {
    if (_fcm == null) return false;
    final NotificationSettings settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final AuthorizationStatus status = settings.authorizationStatus;
    final bool granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    await _vault.markInviteGranted(granted);
    if (status == AuthorizationStatus.denied) {
      await _vault.markInviteBlockedByOs();
    }
    return granted;
  }

  void _onForeground(RemoteMessage message) async {
    final RemoteNotification? n = message.notification;
    if (n == null || !Platform.isAndroid) return;

    AndroidNotificationDetails? details;
    final String? imageUrl = n.android?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final Uint8List? bytes = await _grabImage(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          kBusChannelId,
          kBusChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: _smallIcon,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    details ??= const AndroidNotificationDetails(
      kBusChannelId,
      kBusChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: _smallIcon,
    );

    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(android: details),
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  void _onColdTap(RemoteMessage message) {
    final String? url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _vault.parkColdHint(url);
    }
  }

  void _onWarmTap(RemoteMessage message) {
    final String? url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      onIncomingUrl?.call(url);
    }
  }

  Future<Uint8List?> _grabImage(String url) async {
    try {
      final dynamic response =
          await courier.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes as Uint8List;
    } catch (_) {}
    return null;
  }
}
