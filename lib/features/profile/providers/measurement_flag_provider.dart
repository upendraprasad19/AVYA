import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/measurement_flags.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

/// Whether the body-measurements surfaces are on (`enable_body_measurements`,
/// default OFF; L2b Landing B).
///
/// Its own file so the flag half of the B-alpha / B-beta cut line is
/// self-contained. The only new read on the OFF path of the slots, the
/// providers and the Weight sheet, and it touches `configBox` only. It watches
/// the auth token so a flag the previous account's dev toggle set is re-read
/// after an account swap; the dev panel invalidates it after writing the key
/// (this cached `Provider<bool>` has no other refresh).
final measurementsEnabledProvider = Provider<bool>((ref) {
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
  return MeasurementFlags.bodyMeasurementsEnabled;
});
