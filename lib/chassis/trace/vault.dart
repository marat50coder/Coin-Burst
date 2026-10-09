import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/outcome.dart';
import '../secrets/routing_card.dart';

// ─────────────────────────────────────────────────────────────────────────
// SESSION VAULT — persistent state (prefs + secure storage)
// ─────────────────────────────────────────────────────────────────────────
// Plain booleans and timestamps live in SharedPreferences; URLs live in
// the OS-encrypted secure store (Keychain on iOS, EncryptedSharedPrefs
// on Android). Every key uses a short three-letter prefix unrelated to
// the app slug so a `pm-user-cache` dump never reveals intent.
//
// Prefix "kqz_" is a per-project token; deliberately not reused across
// shipped siblings. Changing it later migrates every user into the
// "undecided" branch, so pick once and keep.
// ─────────────────────────────────────────────────────────────────────────

const String _kp = 'kqz_';

class SessionVault {
  SessionVault({FlutterSecureStorage? secure})
      : _locker = secure ??
            const FlutterSecureStorage(
              // flutter_secure_storage 10.3+ migrates away from the
              // deprecated EncryptedSharedPreferences automatically on
              // first access, so AndroidOptions does not need the
              // `encryptedSharedPreferences: true` flag here.
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const String _kTrack = '${_kp}trk';
  static const String _kCached = '${_kp}cached';
  static const String _kCachedUntil = '${_kp}cached_ttl';
  static const String _kInviteUntil = '${_kp}inv_until';
  static const String _kInviteGranted = '${_kp}inv_ok';
  static const String _kInviteBlocked = '${_kp}inv_blocked';
  static const String _kColdHint = '${_kp}cold';
  static const String _kInstallToken = '${_kp}iid';

  late final SharedPreferences _prefs;
  final FlutterSecureStorage _locker;

  Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Track memory ─────────────────────────────────────────────────
  TrackMemory get track => TrackMemory.parse(_prefs.getString(_kTrack));

  Future<void> stampTrack(TrackMemory value) =>
      _prefs.setString(_kTrack, value.wireValue);

  // ── Cached verdict URL ───────────────────────────────────────────
  Future<String?> cachedUrl() => _locker.read(key: _kCached);

  Future<void> cacheUrl(String url, int? explicitExpiry) async {
    await _locker.write(key: _kCached, value: url);
    final int until = explicitExpiry ??
        (_nowSeconds() + RoutingCard.cachedUrlLifetimeSeconds);
    await _prefs.setInt(_kCachedUntil, until);
  }

  bool get cachedUrlExpired {
    final int? until = _prefs.getInt(_kCachedUntil);
    if (until == null) return true;
    return _nowSeconds() >= until;
  }

  // ── Invite stage state ───────────────────────────────────────────
  bool get inviteGranted => _prefs.getBool(_kInviteGranted) ?? false;

  Future<void> markInviteGranted(bool value) =>
      _prefs.setBool(_kInviteGranted, value);

  bool get inviteBlockedByOs => _prefs.getBool(_kInviteBlocked) ?? false;

  Future<void> markInviteBlockedByOs() =>
      _prefs.setBool(_kInviteBlocked, true);

  Future<void> snoozeInvite(int unixSeconds) =>
      _prefs.setInt(_kInviteUntil, unixSeconds);

  bool get shouldShowInvite {
    if (inviteGranted) return false;
    if (inviteBlockedByOs) return false;
    final int? until = _prefs.getInt(_kInviteUntil);
    if (until == null) return true;
    return _nowSeconds() >= until;
  }

  // ── Cold-tap URL slot ────────────────────────────────────────────
  Future<void> parkColdHint(String? url) async {
    if (url == null || url.isEmpty) {
      await _locker.delete(key: _kColdHint);
    } else {
      await _locker.write(key: _kColdHint, value: url);
    }
  }

  Future<String?> redeemColdHint() async {
    final String? url = await _locker.read(key: _kColdHint);
    if (url != null) await _locker.delete(key: _kColdHint);
    return url;
  }

  // ── Install token (persistent, opaque) ───────────────────────────
  Future<String> installToken() async {
    final String? existing = await _locker.read(key: _kInstallToken);
    if (existing != null && existing.isNotEmpty) return existing;
    final int seed = DateTime.now().microsecondsSinceEpoch;
    final String hex = seed.toRadixString(16).padLeft(16, '0');
    final String token = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '4${hex.substring(12, 15)}-'
        '${(8 + (seed & 3)).toRadixString(16)}'
        '${hex.substring(0, 3)}-'
        '${hex.substring(3, 15)}${hex.substring(0, 3)}';
    await _locker.write(key: _kInstallToken, value: token);
    return token;
  }

  static int _nowSeconds() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
