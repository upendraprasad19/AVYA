// supabase/functions/pr-detection/cron_writer.ts
//
// Test support for window_test.ts (L1b plan T9): finds the cadence a cron job
// was LAST scheduled with, by reading its WRITER — the migrations — instead of
// trusting a constant that would be true by construction.
//
// Rules (R7T-1, R10T-1): strip `--` and block comments first (migration 141 ends
// with a commented rollback to `*/15`); match across whitespace/newlines; take
// the LAST `cron.schedule('<job>', '<cron>'` or `cron.alter_job(... jobname =
// '<job>' ... schedule := '<cron>')` in migration order; order files by the
// `NNN[a-z]?_` scheme (`050b_`, `068b_` exist) and ignore timestamp-prefixed
// files and `all_migrations_combined.sql`.

export interface MigrationFile {
  name: string;
  text: string;
}

export function stripSqlComments(sql: string): string {
  return sql.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/--[^\n]*/g, "");
}

/** Migration order key for `NNN[a-z]?_...sql`; null for files outside the scheme. */
export function migrationOrderKey(name: string): [number, string] | null {
  const m = /^(\d{3})([a-z]?)_.*\.sql$/.exec(name);
  return m ? [Number(m[1]), m[2]] : null;
}

export function latestCronSchedule(
  files: MigrationFile[],
  job: string,
): string | null {
  const ordered = files
    .map((f) => ({ f, k: migrationOrderKey(f.name) }))
    .filter((x): x is { f: MigrationFile; k: [number, string] } => x.k !== null)
    .sort((a, b) => a.k[0] - b.k[0] || a.k[1].localeCompare(b.k[1]));
  let latest: string | null = null;
  const jobRe = job.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const scheduleRe = new RegExp(
    `cron\\.schedule\\(\\s*'${jobRe}'\\s*,\\s*'([^']+)'`,
    "g",
  );
  const alterRe = /cron\.alter_job\(([\s\S]*?)\)\s*;/g;
  for (const { f } of ordered) {
    const sql = stripSqlComments(f.text);
    const hits: Array<{ pos: number; cron: string }> = [];
    for (const m of sql.matchAll(scheduleRe)) hits.push({ pos: m.index!, cron: m[1] });
    for (const m of sql.matchAll(alterRe)) {
      const body = m[1];
      if (!new RegExp(`jobname\\s*=\\s*'${jobRe}'`).test(body)) continue;
      const s = /schedule\s*:=\s*'([^']+)'/.exec(body);
      if (s) hits.push({ pos: m.index!, cron: s[1] });
    }
    hits.sort((a, b) => a.pos - b.pos);
    if (hits.length) latest = hits[hits.length - 1].cron;
  }
  return latest;
}

// Period in minutes of a step-minute, hourly or step-hour 5-field cron; null otherwise.
export function cronPeriodMinutes(cron: string): number | null {
  const f = cron.trim().split(/\s+/);
  if (f.length !== 5) return null;
  const [min, hour, dom, mon, dow] = f;
  if (dom !== "*" || mon !== "*" || dow !== "*") return null;
  const stepMin = /^\*\/(\d+)$/.exec(min);
  if (stepMin && hour === "*") return Number(stepMin[1]);
  if (/^\d+$/.test(min) && hour === "*") return 60;
  const stepHour = /^\*\/(\d+)$/.exec(hour);
  if (/^\d+$/.test(min) && stepHour) return Number(stepHour[1]) * 60;
  return null;
}
