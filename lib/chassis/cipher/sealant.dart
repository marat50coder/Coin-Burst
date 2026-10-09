import 'dart:convert';
import 'dart:typed_data';

// ─────────────────────────────────────────────────────────────────────────
// SEALANT — Dart-side string-hiding codec (FNV-1a → LCG keystream)
// ─────────────────────────────────────────────────────────────────────────
// This is the Dart twin of the Rust `.so`'s own XOR-key sealing. The two
// systems are intentionally different: the Rust side uses a quartered XOR
// key assembled at runtime, this side uses an FNV-1a hash of the salt
// seeded into a Numerical Recipes LCG keystream. A static-analysis tool
// that signs one of them will miss the other.
//
// Public contract:
//   • `List<int> seal(String plain)` — only used by `tool/forge_blobs.dart`
//     at build time (never ships in production).
//   • `String reveal(List<int> encoded)` — the only accessor used at
//     runtime by `sealed_blobs.dart`.
//
// Everything that would otherwise ship as a raw literal (JS enhancer
// bodies, legal URL fragments if encoded) runs through this file.
// ─────────────────────────────────────────────────────────────────────────

// Random 16-byte salt generated when this project was spun up. Any value
// not shared with a shipped sibling is acceptable.
const List<int> _saltBytes = <int>[
  0xC7, 0x1B, 0x92, 0x4E, 0xA3, 0x55, 0x08, 0xDE,
  0x6F, 0xB2, 0x3C, 0x80, 0x29, 0xF4, 0x11, 0x7D,
];

/// Keystream length. 30 bytes keeps the per-byte position mask inside a
/// cheap byte-array lookup without clustering with the typical 16/32 pins
/// seen in sibling apps.
const int _streamLen = 30;

const int _fnvOffset = 0x811C9DC5;
const int _fnvPrime = 0x01000193;

/// FNV-1a 32-bit folded over the salt bytes.
int _fnvSalt() {
  int hash = _fnvOffset;
  for (int i = 0; i < _saltBytes.length; i++) {
    hash = (hash ^ _saltBytes[i]) & 0xFFFFFFFF;
    hash = (hash * _fnvPrime) & 0xFFFFFFFF;
  }
  // Mix the length so a tampered salt with trailing zeros doesn't collide.
  return (hash ^ (_saltBytes.length * 0x9E37)) & 0xFFFFFFFF;
}

/// Numerical-Recipes LCG. Different shape from the xorshift32 used by the
/// template's `position_xor` codec.
Uint8List _derivedStream() {
  int state = _fnvSalt();
  if (state == 0) state = 0xDEADBEEF;
  final Uint8List bytes = Uint8List(_streamLen);
  for (int i = 0; i < _streamLen; i++) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    // Harvest high byte — the low byte of an LCG is weak.
    bytes[i] = (state >> 24) & 0xFF;
  }
  return bytes;
}

final Uint8List _stream = _derivedStream();

/// Per-position mask — folds `i` into the FNV salt so repeated plaintext
/// bytes never encode identically.
int _posMix(int i) {
  int h = (_fnvSalt() ^ i) & 0xFFFFFFFF;
  h = (h * _fnvPrime) & 0xFFFFFFFF;
  return (h >> 8) & 0xFF;
}

/// Decodes the bytes-at-rest to UTF-8. Returns `""` for an empty input —
/// callers must treat that as "value not configured yet".
String reveal(List<int> encoded) {
  if (encoded.isEmpty) return '';
  final Uint8List out = Uint8List(encoded.length);
  for (int i = 0; i < encoded.length; i++) {
    out[i] = (encoded[i] ^ _stream[i % _streamLen] ^ _posMix(i)) & 0xFF;
  }
  return utf8.decode(out, allowMalformed: false);
}

/// Build-time encoder — kept here so `tool/forge_blobs.dart` can import a
/// single file. Round-trips with `reveal`.
List<int> seal(String plain) {
  final List<int> bytes = utf8.encode(plain);
  final List<int> out = List<int>.filled(bytes.length, 0);
  for (int i = 0; i < bytes.length; i++) {
    out[i] = (bytes[i] ^ _stream[i % _streamLen] ^ _posMix(i)) & 0xFF;
  }
  return out;
}
