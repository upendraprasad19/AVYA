export interface Point {
  x: number;
  y: number;
}

/**
 * Least-squares linear regression. `forecastXFromLast` is measured from the
 * LAST point in `points` (not from x=0), so callers pass e.g. 90 to mean
 * "90 days after the most recent data point", regardless of how the x-axis
 * itself is scaled.
 */
export function linearRegressionForecast(points: Point[], forecastXFromLast: number): number | null {
  if (points.length < 2) return null;
  const n = points.length;
  const xMean = points.reduce((s, p) => s + p.x, 0) / n;
  const yMean = points.reduce((s, p) => s + p.y, 0) / n;
  let num = 0;
  let den = 0;
  for (const p of points) {
    num += (p.x - xMean) * (p.y - yMean);
    den += (p.x - xMean) * (p.x - xMean);
  }
  if (den === 0) return points[points.length - 1].y; // all same x — no trend, hold last value
  const slope = num / den;
  const intercept = yMean - slope * xMean;
  const lastX = points[points.length - 1].x;
  return intercept + slope * (lastX + forecastXFromLast);
}

const DAY_MS = 24 * 60 * 60 * 1000;

// Regression is a straight-line extrapolation with no awareness of biology —
// a noisy-but-plausible short history can extrapolate to a nonsensical
// 90-day forecast (a real fixture: 5 weigh-ins dipping 70->65kg over 14 days
// extrapolates to 32.2kg). Clamp to the widest swing from the LAST OBSERVED
// value the app will ever assert, so a bad slope degrades to an extreme-but-
// sane number instead of a physically impossible one. Unlike the static
// fallback formula (bounded by construction between current and target),
// the regression path has no such guard without this clamp.
const WEIGHT_MIN_FACTOR = 0.7; // widest 90-day loss this forecast will ever claim: 30% of last observed weight
const WEIGHT_MAX_FACTOR = 1.3; // widest 90-day gain this forecast will ever claim
const LIFT_MAX_FACTOR = 2.0; // widest 90-day PR gain this forecast will ever claim: 100% of last observed

export function predictWeight(rows: { date: string; weight_kg: number }[], fallback: number): number {
  if (rows.length < 5) return fallback;
  const first = new Date(rows[0].date).getTime();
  const last = new Date(rows[rows.length - 1].date).getTime();
  if ((last - first) / DAY_MS < 14) return fallback;
  const points = rows.map((r) => ({ x: (new Date(r.date).getTime() - first) / DAY_MS, y: r.weight_kg }));
  const forecast = linearRegressionForecast(points, 90);
  if (forecast === null) return fallback;
  const lastWeight = rows[rows.length - 1].weight_kg;
  const clamped = Math.min(lastWeight * WEIGHT_MAX_FACTOR, Math.max(lastWeight * WEIGHT_MIN_FACTOR, forecast));
  return Math.round(clamped * 10) / 10;
}

export function predictLift(rows: { completed_at: string; weight_kg: number }[], fallback: number): number {
  if (rows.length < 2) return fallback;
  const first = new Date(rows[0].completed_at).getTime();
  const last = new Date(rows[rows.length - 1].completed_at).getTime();
  if ((last - first) / DAY_MS < 7) return fallback;
  const points = rows.map((r) => ({ x: (new Date(r.completed_at).getTime() - first) / DAY_MS, y: r.weight_kg }));
  const forecast = linearRegressionForecast(points, 90);
  if (forecast === null) return fallback;
  const lastLift = rows[rows.length - 1].weight_kg;
  const clamped = Math.min(lastLift * LIFT_MAX_FACTOR, Math.max(0, forecast));
  return Math.round(clamped);
}

export function predictStreakWeeks(adherenceRate: number | null, fallback = 8): number {
  if (adherenceRate === null || adherenceRate < 0) return fallback;
  return Math.min(13, Math.max(0, Math.round(adherenceRate * 13)));
}
