// OI-348 Landing 1a-ii — nutrition slot sync, the PURE part (no Hive, no
// network). Spec: docs/plans/nutrition-slot-sync.md (FINAL v17) §4.1-§4.5,
// §4.11 slot admission.
//
// Everything here must decide the same on the phone (Dart VM) and on the web
// (dart2js): no `jsonEncode` of doubles, no `DateTime` round trip of server
// timestamps, no locale-dependent lowercasing.
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:uuid/uuid.dart';

/// The four meal slots the server accepts (`nutrition_slot_put` raises on any
/// other value). Same set as `NutritionWriteService.isAllowedMealType`.
const Set<String> kNslotMealTypes = {'breakfast', 'lunch', 'dinner', 'snacks'};

/// Shared bounds (§3.5, §4.2). A test greps the migration for the same numbers.
const int kNslotMaxEntriesPerSlot = 100;
const int kNslotMaxItemsPerSlot = 500;
const int kNslotMaxStringLength = 200;

/// Fixed namespaces for the two v5 ids this module mints. Never change them:
/// every device must derive the same id from the same input.
const String _kSignatureNamespace = '7d2c4a1e-5b3f-4c8d-9e0a-1f2b3c4d5e6f';
const String _kSyntheticNamespace = '3e8f6a2b-1c4d-4e5f-8a9b-0c1d2e3f4a5b';
const Uuid _uuid = Uuid();

/// §4.11 slot admission: a cloud row is admitted only when its `meal_type` is
/// one of the four. Applied before anything else on every cloud read path.
bool nslotAdmitMealType(Object? mealType) =>
    mealType is String && kNslotMealTypes.contains(mealType);

/// §4.2: a number as canonical text, rounded to 3 decimals, `-0` written as
/// `0.000` (web's toFixed drops the sign of zero; the VM keeps it).
String nslotNumText(Object? v) {
  final d = v is num ? v.toDouble() : 0.0;
  if (d.isNaN || d.isInfinite) return '0.000';
  final rounded = (d * 1000).roundToDouble() / 1000;
  if (rounded == 0) return '0.000';
  return rounded.toStringAsFixed(3);
}

/// §4.2: the projected numeric value that is SENT (the cloud and the local
/// row then hold the same number, so a round trip never moves a signature).
double nslotProjectNum(Object? v) => double.parse(nslotNumText(v));

/// §4.2: lowercase ASCII A-Z only (platform `toLowerCase` differs for some
/// non-ASCII letters between the VM and the web).
String nslotAsciiLower(String s) {
  final b = StringBuffer();
  for (final c in s.codeUnits) {
    b.writeCharCode(c >= 65 && c <= 90 ? c + 32 : c);
  }
  return b.toString();
}

/// §4.2: the canonical text of one entry (a local `nlog_` row, or an entry
/// rebuilt from the cloud): its five totals, then each item in order as
/// name|quantity|calories|protein|carbs|fat|fiber. Fields joined by `|`,
/// items by `;`.
String nslotCanonicalText(Map<dynamic, dynamic> entry) {
  final b = StringBuffer()
    ..write(nslotNumText(entry['total_calories']))
    ..write('|')
    ..write(nslotNumText(entry['total_protein']))
    ..write('|')
    ..write(nslotNumText(entry['total_carbs']))
    ..write('|')
    ..write(nslotNumText(entry['total_fat']))
    ..write('|')
    ..write(nslotNumText(entry['total_fiber']));
  final items = entry['items'];
  if (items is List) {
    for (final raw in items) {
      if (raw is! Map) continue;
      b
        ..write(';')
        // `food_name` is the fallback the push payload uses too (engine
        // `buildPayload`); reading only `name` signed such an item with an
        // empty name, unlike its cloud copy (B-pass seat B P3).
        ..write(nslotAsciiLower(
            ((raw['name'] ?? raw['food_name'] ?? '') as Object).toString().trim()))
        ..write('|')
        ..write(nslotNumText(raw['quantity_g']))
        ..write('|')
        ..write(nslotNumText(raw['calories']))
        ..write('|')
        ..write(nslotNumText(raw['protein']))
        ..write('|')
        ..write(nslotNumText(raw['carbs']))
        ..write('|')
        ..write(nslotNumText(raw['fat']))
        ..write('|')
        ..write(nslotNumText(raw['fiber']));
    }
  }
  return b.toString();
}

/// §4.2 signature: a v5 UUID (SHA-1 based, the same `uuid` package the
/// `nlog_` key hash already uses) of the canonical text. Equal content gives
/// an equal signature on every platform.
String nslotSignature(Map<dynamic, dynamic> entry) =>
    _uuid.v5(_kSignatureNamespace, nslotCanonicalText(entry));

/// §4.1 synthetic entry id for a LEGACY cloud row: from the row's id and rev
/// only (a uuid string and an integer: identical on every platform).
String nslotSyntheticEntryId(String cloudRowId, int rev) =>
    _uuid.v5(_kSyntheticNamespace, '$cloudRowId|$rev');

/// §4.5 rule 4: `logged_at` as comparable text `YYYY-MM-DDTHH:MM:SS.mmm`
/// (fraction cut or zero-padded to 3 digits). Absent or shorter than 19
/// characters → the empty string (sorts oldest).
String nslotNormLoggedAt(Object? v) {
  if (v is! String || v.length < 19) return '';
  final head = v.substring(0, 19);
  var frac = '';
  if (v.length > 19 && v[19] == '.') {
    var i = 20;
    while (i < v.length && v.codeUnitAt(i) >= 48 && v.codeUnitAt(i) <= 57) {
      i++;
    }
    frac = v.substring(20, i);
  }
  frac = frac.length >= 3 ? frac.substring(0, 3) : frac.padRight(3, '0');
  return '$head.$frac';
}

/// One entry as the merge sees it.
class NslotEntryView {
  const NslotEntryView({
    required this.id,
    required this.signature,
    required this.loggedAt,
  });

  final String id;
  final String signature;

  /// Normalised with [nslotNormLoggedAt].
  final String loggedAt;
}

/// §4.5 order: positive when [a] is the NEWER copy (wins), negative when [b]
/// is, 0 only for equal logged_at AND equal signature.
int nslotCompareNewer(NslotEntryView a, NslotEntryView b) {
  final t = a.loggedAt.compareTo(b.loggedAt);
  if (t != 0) return t;
  return a.signature.compareTo(b.signature);
}

/// What the merge decided for one entry id.
enum NslotChoice {
  /// Keep this device's row as it is.
  keepLocal,

  /// Write the cloud's version of the entry locally.
  takeCloud,

  /// Remove the local row (or leave it absent).
  remove,
}

/// §4.5 `mergeSlot(base, local, cloud)`: per entry id in L ∪ C ∪ B.
/// [base] maps entry id → signature (the ledger's `e`; empty for a slot first
/// seen). Returns the choice for every id; an id absent from both local and
/// the result's keep/take set ends removed.
Map<String, NslotChoice> nslotMergeSlot({
  required Map<String, String> base,
  required Map<String, NslotEntryView> local,
  required Map<String, NslotEntryView> cloud,
}) {
  final ids = <String>{...base.keys, ...local.keys, ...cloud.keys};
  final out = <String, NslotChoice>{};
  for (final id in ids) {
    final l = local[id];
    final c = cloud[id];
    final b = base[id];
    final ls = l?.signature;
    final cs = c?.signature;
    if (ls == cs) {
      // Rule 1 (both null cannot happen for an id from L ∪ C; from B only it
      // means both sides removed it).
      out[id] = l == null ? NslotChoice.remove : NslotChoice.keepLocal;
    } else if (ls == b) {
      // Rule 2: local unchanged since the base → take the cloud's.
      out[id] = c == null ? NslotChoice.remove : NslotChoice.takeCloud;
    } else if (cs == b) {
      // Rule 3: cloud unchanged since the base → keep local.
      out[id] = l == null ? NslotChoice.remove : NslotChoice.keepLocal;
    } else if (l != null && c != null) {
      // Rule 4: both changed → the newer wins.
      out[id] = nslotCompareNewer(l, c) >= 0
          ? NslotChoice.keepLocal
          : NslotChoice.takeCloud;
    } else {
      // Rule 5: both changed, one removed → keep the edited one (S9).
      out[id] = l != null ? NslotChoice.keepLocal : NslotChoice.takeCloud;
    }
  }
  return out;
}

/// §4.5 placement of one incoming entry into slot ([date], [meal]):
/// - its id is already held IN THIS SLOT → that key ([sameSlotKey]);
/// - else its own key [cloudKey] when free, else the first free occurrence of
///   that key's base (`firstFreeLogKey(baseLogKey(k))`).
/// A [cloudKey] that is not an `nlog_<date>_<meal>_<hash>` key of THIS slot
/// (absent, malformed, or naming another slot) is replaced by one derived from
/// the entry id, so a row is never stored under a key that names a slot it is
/// not in.
String nslotPlaceKey({
  required String date,
  required String meal,
  required String entryId,
  required String? cloudKey,
  required String? sameSlotKey,
  required bool Function(String key) taken,
}) {
  if (sameSlotKey != null) return sameSlotKey;
  final prefix = NutritionWriteService.logKeyPrefix(date, meal);
  final ownKey = cloudKey != null &&
          cloudKey.startsWith(prefix) &&
          NutritionWriteService.kNlogKeyShape.hasMatch(cloudKey)
      ? cloudKey
      : NutritionWriteService.logKeyForHash(date, meal, _hex8(entryId));
  if (!taken(ownKey)) return ownKey;
  return NutritionWriteService.firstFreeLogKey(
      taken, NutritionWriteService.baseLogKey(ownKey));
}

String _hex8(String id) {
  final b = StringBuffer();
  for (final c in nslotAsciiLower(id).codeUnits) {
    final hex = (c >= 48 && c <= 57) || (c >= 97 && c <= 102);
    if (hex) b.writeCharCode(c);
    if (b.length == 8) break;
  }
  return b.toString().padRight(8, '0');
}

/// One copy of an entry inside a date, for the day pass.
class NslotDayCopy {
  const NslotDayCopy({
    required this.view,
    required this.mealType,
    required this.key,
  });

  final NslotEntryView view;
  final String mealType;

  /// The local key (or the key it will be placed at).
  final String key;
}

/// §4.5 day pass: an entry id held in two or more slots of one date keeps the
/// copy with the newer `logged_at` (tie: larger signature, then larger key).
/// Returns the KEYS of the copies to remove. Pure and order-independent.
Set<String> nslotDayPass(Iterable<NslotDayCopy> copies) {
  final byId = <String, List<NslotDayCopy>>{};
  for (final c in copies) {
    (byId[c.view.id] ??= []).add(c);
  }
  final remove = <String>{};
  for (final group in byId.values) {
    if (group.length < 2) continue;
    var best = group.first;
    for (final c in group.skip(1)) {
      final cmp = nslotCompareNewer(c.view, best.view);
      if (cmp > 0 || (cmp == 0 && c.key.compareTo(best.key) > 0)) best = c;
    }
    for (final c in group) {
      if (!identical(c, best)) remove.add(c.key);
    }
  }
  return remove;
}
