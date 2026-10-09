import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
// flutter_local_notifications resolves `icon` via
// `Resources#getIdentifier(name, "drawable", pkg)` — pass the resource
// name only, NEVER the `@drawable/…` XML reference form, otherwise the
// lookup silently returns 0 and the notification is dropped.
const String _smallIcon = 'ic_notification';

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
      assert(() {
        debugPrint('[kqz.bus] wired. token=${_token?.substring(0, 16)}…');
        return true;
      }());
    } catch (e, st) {
      // Firebase not configured yet — push stays dormant. Log in debug
      // so the operator can tell "no credentials" from "runtime panic".
      assert(() {
        debugPrint('[kqz.bus] wireUp failed: $e\n$st');
        return true;
      }());
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
          // `max` + `playSound:true` + `enableVibration:true` is the only
          // combo that reliably heads-up on Android 12+. `high` degrades
          // to in-tray on some OEM skins (Xiaomi / Realme).
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
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
    if (!Platform.isAndroid) return;

    // Resolve title/body from either the `notification` block or the
    // `data` map — Firebase Console pushes always carry `notification`,
    // but custom senders sometimes ship data-only payloads to bypass
    // the system auto-display path.
    final RemoteNotification? n = message.notification;
    final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);
    final String? title = n?.title ?? data['title'] as String?;
    final String? body = n?.body ?? data['body'] as String?;
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      // Nothing to render — do not fabricate a blank notification.
      return;
    }

    AndroidNotificationDetails? details;
    final String? imageUrl =
        n?.android?.imageUrl ?? data['image'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final Uint8List? bytes = await _grabImage(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          kBusChannelId,
          kBusChannelName,
          importance: Importance.max,
          priority: Priority.max,
          icon: _smallIcon,
          playSound: true,
          enableVibration: true,
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
      importance: Importance.max,
      priority: Priority.max,
      icon: _smallIcon,
      playSound: true,
      enableVibration: true,
    );

    final int tag = (message.messageId ?? message.hashCode.toString()).hashCode;
    try {
      await _local.show(
        tag,
        title,
        body,
        NotificationDetails(android: details),
        payload: data.isNotEmpty ? jsonEncode(data) : null,
      );
    } catch (e, st) {
      // Make the delivery failure LOUD in debug — silent catch masked
      // the icon-reference bug for weeks.
      assert(() {
        debugPrint('[kqz.bus] show failed: $e\n$st');
        return true;
      }());
    }
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
