# L1b mutation driver (CLAUDE.md §4.4 rule 21). Run from anywhere: python3 docs/audit/coach-history-correctness-tools.mutants.py [M01 ...]
# SP / R paths below are the authoring session scratchpad; point R at the worktree and SP at a dir holding noserve_map.json (an import map stubbing std serve) to re-run.
import subprocess, sys, shutil, os
R='/home/ubuntu/projects/avya/.claude/worktrees/coach-history-correctness-tools'
SP='/tmp/claude-1001/-home-ubuntu-projects-avya/6f8cf6b9-0e53-43b9-93bf-4239f4d89132/scratchpad'
DENO=os.path.expanduser('~/.deno/bin/deno')
F='supabase/functions/'
T=F+'_shared/tools/'
SH=F+'_shared/'
allt=[SH+'uuid_v5_test.ts',SH+'exercise_day_test.ts',SH+'live_exercise_rows_test.ts',SH+'paged_fetch_bounded_test.ts',SH+'recent_prs_test.ts',SH+'workout_statuses_test.ts',
      T+'__tests__/getProgressSummary_test.ts',T+'__tests__/getExerciseHistory_test.ts',T+'__tests__/getPRTimeline_test.ts',T+'__tests__/getNutritionHistory_test.ts',T+'__tests__/unit_c_read_hardening_test.ts',
      F+'pr-detection/',F+'weekly-recalc/',F+'weekly-report/',F+'i-see-you-callout/',F+'future-prediction/']
M=[
# (id, file, old, new)
('M01',SH+'live_exercise_rows.ts','    if (r.deleted_at) continue;\n','    // mutated: keep tombstones\n'),
('M02',SH+'live_exercise_rows.ts','if (a > b || (a === b && cmpId(r.id, cur.id) > 0))','if (a < b || (a === b && cmpId(r.id, cur.id) > 0))'),
('M03',SH+'live_exercise_rows.ts','const user = r.user_id ?? "";','const user = "";'),
('M04',SH+'live_exercise_rows.ts','return `${user}|~${day}|${ex}`;','return `${user}|~|${ex}`;'),
('M05',SH+'live_exercise_rows.ts','(a === b && cmpId(r.id, cur.id) > 0)','(a === b && cmpId(r.id, cur.id) < 0)'),
('M06',SH+'uuid_v5.ts','(b[6] & 0x0f) | 0x50','(b[6] & 0x0f) | 0x40'),
('M07',SH+'exercise_day.ts','export const DAY_MAP_FUTURE_DAYS = 400;','export const DAY_MAP_FUTURE_DAYS = 30;'),
('M08',SH+'exercise_day.ts','export const DAY_MAP_START = "2020-01-01";','export const DAY_MAP_START = "2026-01-01";'),
('M09',SH+'exercise_day.ts','  if (viaId) return viaId;\n','  // mutated: always completed_at\n'),
('M10',SH+'exercise_day.ts','new Date(Date.parse(`${nextIstDate(last)}T00:00:00Z`) - IST_OFFSET_MS)','new Date(Date.parse(`${last}T00:00:00Z`) - IST_OFFSET_MS)'),
('M11',SH+'paged_fetch_bounded.ts','makeQuery(page === 0)','makeQuery(true)'),
('M12',SH+'paged_fetch_bounded.ts','if (total !== null && all.length >= total) return { rows: all, truncated: false };','// mutated'),
('M13',SH+'paged_fetch_bounded.ts','return { rows: all, truncated: lastFull };','return { rows: all, truncated: false };'),
('M14',SH+'paged_fetch_bounded.ts','const from = all.length;','const from = page * pageSize;'),
('M15',SH+'recent_prs.ts','return d === today || d === yesterday;','return true;'),
('M16',SH+'recent_prs.ts','return liveSummaryRows([...rows], dayMap)\n    .filter((r) => r.is_pr === true)','return [...rows].filter((r) => r.is_pr === true)'),
('M17',SH+'wle_window_read.ts','const ids = await windowLogIds(dates);','const ids = (await windowLogIds(dates)).slice(0, 1);'),
('M18',T+'progress/getProgressSummary.ts','.filter((r) =>\n    inWindow(r, dayMap, dates)\n  );','.filter(() => true);'),
('M19',T+'progress/getProgressSummary.ts','          .lte("scheduled_date", today),','          ,'),
('M20',T+'progress/getProgressSummary.ts','!NON_WORKOUT_STATUSES.has(s.status)','true'),
('M21',T+'progress/getProgressSummary.ts','if (r.is_pr && day) prDays.add(day);','if (day) prDays.add(day);'),
('M22',T+'progress/getProgressSummary.ts','const live = liveSummaryRows(wle.rows, dayMap)','const live = (wle.rows as SummaryRow[])'),
('M23',T+'progress/getExerciseHistory.ts','total_volume_kg: Math.round(w * reps),','total_volume_kg: Math.round(w * reps * s),'),
('M24',T+'progress/getExerciseHistory.ts','x.day < y.day ? -1 : x.day > y.day ? 1 :','x.day < y.day ? 1 : x.day > y.day ? -1 :'),
('M25',T+'progress/getExerciseHistory.ts','.filter((r) => inWindow(r, dayMap, dates))','.filter(() => true)'),
('M26',T+'progress/getPRTimeline.ts','    .filter((x) => x.r.is_pr === true)\n','    .filter((x) => x.r !== null)\n'),
('M27',T+'progress/getPRTimeline.ts','? (a.day < z.day ? 1 : -1)','? (a.day < z.day ? -1 : 1)'),
('M28',T+'progress/getPRTimeline.ts','live.slice(0, MAX_PRS)','live.slice(0, 5000)'),
('M29',T+'progress/getPRTimeline.ts','(!args.to || x.day <= args.to)','true'),
('M30',T+'nutrition/getNutritionHistory.ts','const wantItems = args.aggregation === "per_day" &&','const wantItems = true ||'),
('M31',T+'nutrition/getNutritionHistory.ts','export const MAX_ITEM_RANGE_DAYS = 31;','export const MAX_ITEM_RANGE_DAYS = 32;'),
('M32',F+'pr-detection/window.ts','const since = new Date(until.getTime() - periodMinutes * MS_PER_MINUTE);','const since = new Date(until.getTime() - 20 * MS_PER_MINUTE);'),
('M33',F+'pr-detection/window.ts','export const PR_PERIOD_MINUTES = 60;','export const PR_PERIOD_MINUTES = 30;'),
('M34',F+'pr-detection/index.ts','.lt("completed_at", until)','.lte("completed_at", until)'),
('M35',F+'pr-detection/index.ts','celebratablePrs(excludeDeletedPrs(rawRows), dayMap, now)','excludeDeletedPrs(rawRows).filter((r) => r.is_pr)'),
('M36',F+'pr-detection/message.ts','total reps','reps'),
('M37',F+'i-see-you-callout/index.ts','recentLivePrs(recent ?? [], await buildDayMap())','(recent ?? []).filter((r: { is_pr?: boolean }) => r.is_pr)'),
('M38',F+'i-see-you-callout/index.ts','    ? `${pr.weight_kg} kg`','    ? `${pr.weight_kg} kg × ${pr.reps} reps`'),
('M39',F+'weekly-recalc/live_log_filter.ts','return liveSummaryRows([...rows], dayMap)\n    .filter((r) => inWindow(r, dayMap, dates))','return [...rows]\n    .filter((r) => inWindow(r, dayMap, dates))'),
('M40',F+'weekly-recalc/index.ts','const windowDates = istDatesEnding(28);','const windowDates = istDatesEnding(29);'),
('M41',F+'weekly-report/week_rows.ts','.filter((r) => inWindow(r, dayMap, dates))','.filter(() => true)'),
('M42',F+'weekly-report/index.ts','istDatesEnding(7, now)','istDatesEnding(8, now)'),
('M43',F+'weekly-report/week_rows.ts','a.day !== b.day\n        ? (a.day < b.day ? -1 : 1)','a.day !== b.day\n        ? (a.day < b.day ? 1 : -1)'),
('M44',F+'future-prediction/index.ts','    const prs = liveSummaryRows(rows, dayMap)','    const prs = rows'),
('M45',SH+'workout_statuses.ts','  "dropped",\n',''),
('M46',SH+'live_exercise_rows.ts','(r.exercise_id ?? "").toLowerCase()','(r.exercise_id ?? "")'),
('M47',T+'progress/getPRTimeline.ts','x.day <= (args.to ?? istDateStr())','(!args.to || x.day <= args.to)'),
('M48',F+'pr-detection/live_pr_filter.ts','return !Number.isNaN(t) && t >= lo && t < hi;','return true;'),
('M49',F+'pr-detection/live_pr_filter.ts','t >= lo && t < hi','t >= lo && t <= hi'),
('M50',T+'progress/getProgressSummary.ts','truncated: wle.truncated || sched.truncated || weights.truncated || nutrition.truncated,','truncated: false,'),
]
only=sys.argv[1:] 
res=[]
for mid,f,old,new in M:
    if only and mid not in only: continue
    p=os.path.join(R,f)
    src=open(p).read()
    if old not in src:
        res.append((mid,'NOT-APPLIED (old text missing)')); print(mid,res[-1][1]); continue
    open(p,'w').write(src.replace(old,new,1))
    assert open(p).read()!=src
    try:
        cmd=[DENO,'test','--no-check','--allow-all','--node-modules-dir=none','--import-map='+SP+'/noserve_map.json']+[os.path.join(R,t) for t in allt]
        r=subprocess.run(cmd,capture_output=True,text=True,cwd=R,timeout=600)
        out=r.stdout+r.stderr
        import re
        out=re.sub(r'\x1b\[[0-9;]*m','',out)
        m=re.findall(r'(\d+) passed \| (\d+) failed',out)
        failed=int(m[-1][1]) if m else -1
        status='RED' if (r.returncode!=0) else 'GREEN(survived)'
        res.append((mid,f'{status} failed={failed}'))
        print(mid,f,res[-1][1],flush=True)
    finally:
        open(p,'w').write(src)
bad=[x for x in res if not x[1].startswith('RED')]
print('SURVIVORS/NOT-APPLIED:',bad)
