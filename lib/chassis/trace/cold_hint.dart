import 'vault.dart';

// ─────────────────────────────────────────────────────────────────────────
// COLD HINT — one-shot reader for cold-boot push URLs
// ─────────────────────────────────────────────────────────────────────────
// On Android, a cold-boot push tap delivers the URL through the launch
// intent, which Firebase Messaging surfaces via `getInitialMessage()`.
// `SignalBus._onColdTap` stashes that URL in the vault. The pilot calls
// this class as its very first routing input so the sequence is
// symmetric with the returning-launch code path.
// ─────────────────────────────────────────────────────────────────────────

class ColdHint {
  ColdHint._();

  /// Reads and clears the parked URL. Returns `null` when there was no
  /// cold-boot push tap.
  static Future<String?> redeem(SessionVault vault) => vault.redeemColdHint();
}
