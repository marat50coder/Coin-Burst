import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../secrets/sealed_blobs.dart';
import 'courier.dart';
import 'vault.dart';

// Keys that senders commonly use to carry the landing URL inside the FCM
// `data` payload. We try them in order so Firebase Console / custom senders
// / server-pushed deep-links all land correctly.
const List<String> _urlKeys = <String>[
  'url',
  'link',
  'deeplink',
  'deep_link',
  'notification_link',
  'click_action',
  'target',
  'destination',
  'landing',
  'u',
];

String? _extractUrl(Map<String, dynamic> data) {
  for (final String key in _urlKeys) {
    final Object? raw = data[key];
    if (raw is String && raw.isNotEmpty) {
      final String trimmed = raw.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
    }
  }
  return null;
}

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

  /// Warm-tap delivery — the active WebView loads this URL directly.
  /// Set in [PortalScene.initState] and cleared in dispose.
  void Function(String url)? onIncomingUrl;

  /// Pumps the Navigator back to the warmup splash so the pilot re-runs
  /// and consumes the parked cold-hint URL. Set in [CoinBurstApp.build].
  void Function()? restartToWarmup;

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

      // Cold tap MUST be awaited: parkColdHint is async and the pilot
      // reads the hint from secure storage on its very first tick. Any
      // race here loses the URL silently.
      final RemoteMessage? initial = await _fcm!.getInitialMessage();
      if (initial != null) await _onColdTap(initial);

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
          final String? url = _extractUrl(data);
          if (url != null) _deliverWarm(url);
        } catch (e, st) {
          assert(() {
            debugPrint('[kqz.bus] local payload decode failed: $e\n$st');
            return true;
          }());
        }
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

  Future<void> _onColdTap(RemoteMessage message) async {
    final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);
    final String? url = _extractUrl(data);
    assert(() {
      debugPrint('[kqz.bus] cold tap url=$url keys=${data.keys.toList()}');
      return true;
    }());
    if (url != null) {
      await _vault.parkColdHint(url);
    }
  }

  void _onWarmTap(RemoteMessage message) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);
    final String? url = _extractUrl(data);
    assert(() {
      debugPrint('[kqz.bus] warm tap url=$url keys=${data.keys.toList()}');
      return true;
    }());
    if (url != null) _deliverWarm(url);
  }

  // Warm (foreground / background-resume) delivery:
  //  • If PortalScene is already alive, hand the URL straight to it.
  //  • Otherwise park the URL as a cold-hint and bounce the Navigator
  //    back to the warmup splash — the pilot picks the hint up and
  //    routes to PortalScene with the right landing URL.
  void _deliverWarm(String url) {
    final void Function(String)? direct = onIncomingUrl;
    if (direct != null) {
      try {
        direct(url);
        return;
      } catch (e, st) {
        assert(() {
          debugPrint('[kqz.bus] onIncomingUrl threw: $e\n$st');
          return true;
        }());
      }
    }
    // No live portal — persist and restart the warmup flow.
    _vault.parkColdHint(url);
    final void Function()? reboot = restartToWarmup;
    if (reboot != null) {
      try {
        reboot();
      } catch (e, st) {
        assert(() {
          debugPrint('[kqz.bus] restartToWarmup threw: $e\n$st');
          return true;
        }());
      }
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
