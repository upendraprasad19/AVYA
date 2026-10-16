// TS twin of lib/core/constants/body_measurement_sites.dart (OI-297).
// The four body-measurement sites, in the order of the cloud `body_measurements`
// columns. Parity (Dart list == this list == live_schema_columns.json ==
// the Edge Function prompt lists) is pinned by
// test/contracts/body_measurement_sites_parity_test.dart. No Edge Function
// imports this yet; the first server importer is the L3 athlete state.
export const BODY_MEASUREMENT_SITES = ["chest", "waist", "hips", "arms"] as const;
export type BodyMeasurementSite = typeof BODY_MEASUREMENT_SITES[number];
