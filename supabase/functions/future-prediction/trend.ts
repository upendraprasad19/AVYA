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

export function predictWeight(rows: { date: string; weight_kg: number }[], fallback: number): number {
  if (rows.length < 5) return fallback;
  const first = new Date(rows[0].date).getTime();
  const last = new Date(rows[rows.length - 1].date).getTime();
  if ((last - first) / DAY_MS < 14) return fallback;
  const points = rows.map((r) => ({ x: (new Date(r.date).getTime() - first) / DAY_MS, y: r.weight_kg }));
  const forecast = linearRegressionForecast(points, 90);
  return forecast === null ? fallback : Math.round(forecast * 10) / 10;
}

export function predictLift(rows: { completed_at: string; weight_kg: number }[], fallback: number): number {
  if (rows.length < 2) return fallback;
  const first = new Date(rows[0].completed_at).getTime();
  const last = new Date(rows[rows.length - 1].completed_at).getTime();
  if ((last - first) / DAY_MS < 7) return fallback;
  const points = rows.map((r) => ({ x: (new Date(r.completed_at).getTime() - first) / DAY_MS, y: r.weight_kg }));
  const forecast = linearRegressionForecast(points, 90);
  return forecast === null ? fallback : Math.round(forecast);
}

export function predictStreakWeeks(adherenceRate: number | null, fallback = 8): number {
  if (adherenceRate === null || adherenceRate < 0) return fallback;
  return Math.min(13, Math.max(0, Math.round(adherenceRate * 13)));
}
