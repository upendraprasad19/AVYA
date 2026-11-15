// lib/core/services/exercise_media/exercise_media_webp.dart
//
// The ONE well-formedness predicate for an exercise animation, shared by the store's `read` (a cached file that fails it is
// deleted and re-fetched) and Task 6's client (a body that fails it is not stored). No Flutter import.
//
// What it checks, and why each term exists:
//   - at least 12 bytes: the RIFF and WEBP magic live in bytes 0 to 11, and a shorter body (an empty body, the 8-byte JSON
//     error body `{"error"`) must answer false, never raise a RangeError;
//   - at most 1,500,000 bytes: the bucket's own file size limit (docs/operations/EXERCISE_MEDIA.md);
//   - `RIFF` at 0 to 3 and `WEBP` at 8 to 11;
//   - the RIFF size field (bytes 4 to 7, little endian) + 8 == the length: it catches a truncated or padded body whose length
//     happens to equal the indexed length. Task 1's S7 scan found 0 violations on all 924 files, so the term stays.
import 'dart:typed_data';

/// The bucket's file size limit in bytes.
const int kMaxWebpBytes = 1500000;

bool isWellFormedWebp(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (bytes.length > kMaxWebpBytes) return false;
  // 'RIFF'
  if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) return false;
  // 'WEBP'
  if (bytes[8] != 0x57 || bytes[9] != 0x45 || bytes[10] != 0x42 || bytes[11] != 0x50) return false;
  // Little-endian u32 without shifts (a shift by 24 is signed on the web).
  final size = bytes[4] + bytes[5] * 256 + bytes[6] * 65536 + bytes[7] * 16777216;
  return size + 8 == bytes.length;
}
