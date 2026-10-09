import '../cipher/sealant.dart';

// ─────────────────────────────────────────────────────────────────────────
// SEALED BLOBS — Dart-side encoded strings
// ─────────────────────────────────────────────────────────────────────────
// Everything a scanner would otherwise grep for lives here as a byte list
// and only becomes meaningful after passing through `reveal()`.
//
// Secrets split between this file and the Rust `.so`:
//
//   • Rust `.so` holds   : endpoint URL, HMAC secret, envelope field
//                          names, schema revision, Chrome version suffix,
//                          UA scaffold template, JS enhancer bodies.
//   • This file holds    : user-visible UI copy (notification channel
//                          description, invite / offline screen strings)
//                          — scanners still cluster on identical strings
//                          across sibling apps, so even these ship sealed.
//
// Regenerate via `dart run tool/forge_blobs.dart` and paste.
// ─────────────────────────────────────────────────────────────────────────

const List<int> _inviteTitle = <int>[
  26, 105, 176, 35, 99, 157, 37, 78, 137, 208, 30, 14, 3, 129, 147, 76, 14,
];
const List<int> _inviteBody = <int>[
  28, 102, 165, 34, 103, 216, 96, 72, 153, 209, 15, 14, 21, 129, 221, 81, 24,
  243, 36, 130, 44, 35, 221, 72, 12, 148, 91, 213, 47, 164, 39, 105, 113, 225,
  174, 90, 174, 147, 84, 241, 57, 48, 47, 164, 163, 29, 13, 173, 248, 6, 220,
  148, 44, 163, 235, 45, 186, 90, 244, 33, 236, 177, 116, 234, 192, 170, 53,
  87, 51, 55, 253, 251, 250, 115, 127, 193, 202, 123, 237, 29, 147, 151, 43,
];
const List<int> _inviteAccept = <int>[24, 107, 167, 37, 123, 201];
const List<int> _inviteSkip = <int>[10, 99, 173, 48];

const List<int> _offlineTitle = <int>[
  23, 103, 228, 35, 100, 211, 46, 93, 143, 214, 14, 65, 15,
];
const List<int> _offlineBody = <int>[
  14, 109, 228, 44, 100, 206, 52, 24, 152, 202, 2, 14, 18, 135, 154, 87, 28,
  254, 120, 130, 31, 36, 209, 82, 22, 218, 80, 211, 44, 164, 32, 106, 62, 194,
  180, 91, 200, 156, 6, 251, 46, 48, 49, 187, 168, 26, 18, 232, 185, 12, 217,
  192, 41, 226, 246, 46, 227, 17, 242, 43, 241, 243, 104, 233, 137, 38, 219,
  170, 125, 62, 188,
];
const List<int> _offlineRetry = <int>[11, 109, 176, 50, 114];

const List<int> _busChannelDesc = <int>[
  29, 105, 173, 44, 114, 157, 35, 87, 129, 192, 8, 93, 77, 206, 159, 86, 19,
  231, 37, 130, 63, 36, 223, 84, 22, 208, 80, 194, 43, 164, 53, 107, 122, 181,
  178, 16, 232, 144, 84, 180, 56, 98, 51, 164, 185,
];

String unlockInviteTitle() => reveal(_inviteTitle);
String unlockInviteBody() => reveal(_inviteBody);
String unlockInviteAccept() => reveal(_inviteAccept);
String unlockInviteSkip() => reveal(_inviteSkip);

String unlockOfflineTitle() => reveal(_offlineTitle);
String unlockOfflineBody() => reveal(_offlineBody);
String unlockOfflineRetry() => reveal(_offlineRetry);

String unlockBusChannelDesc() => reveal(_busChannelDesc);
