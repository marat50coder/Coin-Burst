// ─────────────────────────────────────────────────────────────────────────
// OUTCOME — sealed boot-pipeline result + persisted route memory + verdict
// ─────────────────────────────────────────────────────────────────────────
// The pilot resolves one of three sealed subtypes. The warmup screen
// destructures via `switch` and only there decides which route to push —
// no routing logic lives anywhere else in this project.
// ─────────────────────────────────────────────────────────────────────────

/// Which branch the previous launch resolved to. Persisted across runs so
/// a returning user who already saw the WebView skips the organic rescue
/// delay on cold start.
enum TrackMemory {
  initial,
  outside,
  slot;

  String get wireValue => switch (this) {
        TrackMemory.initial => 'initial',
        TrackMemory.outside => 'outside',
        TrackMemory.slot => 'slot',
      };

  static TrackMemory parse(String? raw) => switch (raw) {
        'outside' => TrackMemory.outside,
        'slot' => TrackMemory.slot,
        _ => TrackMemory.initial,
      };
}

/// Parsed answer from the verdict dispatcher. Wire fields come straight
/// from the Rust side (`{"ok":bool,"url":string,"status":int}`); the Dart
/// layer never sees the raw envelope.
class VerdictAnswer {
  const VerdictAnswer({
    required this.granted,
    this.url,
    this.statusCode = 0,
    this.failureNote,
  });

  factory VerdictAnswer.rejected(String note) =>
      VerdictAnswer(granted: false, failureNote: note);

  final bool granted;
  final String? url;
  final int statusCode;
  final String? failureNote;

  bool get hasDestination =>
      granted && url != null && url!.isNotEmpty;
}

// ── Sealed outcome ────────────────────────────────────────────────────

/// Top-level result of the warmup pipeline. The screen that owns the
/// loading UI destructures this via `switch` — no `is` / downcast chains.
sealed class Outcome {
  const Outcome();
}

/// Show the native slot — this is the default branch and never requires
/// a working attribution stack.
final class SlotOutcome extends Outcome {
  const SlotOutcome();
}

/// Show the gray-part portal (WebView) at [url]. [coldTap] is true only
/// when the launch was triggered by a cold-boot push notification and the
/// URL came from the intent payload instead of the verdict cache.
final class OutsideOutcome extends Outcome {
  const OutsideOutcome(this.url, {this.coldTap = false});

  final String url;
  final bool coldTap;
}

/// Show the no-connection screen. Retry rebuilds the pipeline from zero —
/// pilot's in-flight future clears on completion, so a retry re-asks the
/// upstream.
final class StallOutcome extends Outcome {
  const StallOutcome({required this.returnsToSlot});

  final bool returnsToSlot;
}
