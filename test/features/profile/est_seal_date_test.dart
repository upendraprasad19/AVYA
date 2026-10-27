// OI-341 Piece B2b — the EST seal never shows a future date
// (docs/plans/oi341-piece-b2b-client.md 2.5). Run with TZ=Asia/Kolkata.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/services/est_seal_date.dart';

void main() {
  final now = DateTime(2026, 10, 22, 10);

  test('no expiry: today', () {
    expect(estSealDate(expiresAt: null, plan: 'monthly', now: now), '22/10/26');
  });

  test('monthly ending in 10 days: expiry - 30', () {
    expect(
        estSealDate(
            expiresAt: DateTime(2026, 11, 1, 10), plan: 'monthly', now: now),
        '02/10/26');
  });

  test('stacked: trial end in 5 days + 30 -> today until the trial ends', () {
    expect(
        estSealDate(
            expiresAt: DateTime(2026, 11, 26, 10), plan: 'monthly', now: now),
        '22/10/26');
  });

  test('a UTC expiry prints the LOCAL date (refreshFromSupabase stores UTC)',
      () {
    // Local 2026-10-02 01:30 as a UTC instant (2026-10-01 20:00Z in IST).
    final expiry = DateTime(2026, 10, 2, 1, 30).toUtc();
    final startLocal = DateTime(2026, 10, 2, 1, 30)
        .subtract(const Duration(days: 30));
    final want = '${startLocal.day.toString().padLeft(2, '0')}/'
        '${startLocal.month.toString().padLeft(2, '0')}/26';
    expect(estSealDate(expiresAt: expiry, plan: 'monthly', now: now), want);
    expect(want, '02/09/26');
  });

  test('yearly, the annual alias and mixed case back-compute 365', () {
    final exp = DateTime(2027, 9, 22, 10);
    for (final plan in ['yearly', 'annual', 'Yearly']) {
      expect(estSealDate(expiresAt: exp, plan: plan, now: now), '22/09/26',
          reason: plan);
    }
  });
}
