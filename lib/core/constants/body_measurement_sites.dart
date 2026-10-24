/// The body-measurement sites the app stores, in the order of the cloud
/// `body_measurements` columns (`chest, waist, hips, arms`, centimetres).
///
/// ONE list: the sync push and pull, the chat parse and log handler and the AI
/// snapshot all derive from it (OI-297: the list used to be hard-coded in five
/// Dart places, so a site added in one and missed in another stayed
/// device-only). The TS twin is `supabase/functions/_shared/
/// body_measurement_sites.ts`; `test/contracts/body_measurement_sites_parity_test.dart`
/// pins the Dart list, the twin, `backups/live_schema_columns.json` and the
/// two prompt lists in `supabase/functions/_shared/write_claim_prompt.ts`
/// (the ai-proxy and ai-media-proxy ICBF blocks) to one set.
///
/// Tokens only. Labels, guide lines and bounds belong to the L2b sheet. NOT the
/// keys of `user_stat_snapshots.measurements` (`arms_l`, `arms_r`, `thighs_*`).
const List<String> kBodyMeasurementSites = ['chest', 'waist', 'hips', 'arms'];

/// True when [type] is one of [kBodyMeasurementSites].
bool isBodyMeasurementSite(String? type) =>
    type != null && kBodyMeasurementSites.contains(type);
