// OI-252 (stable ID rework). Extracted pure so it is independently testable
// without a live Supabase call -- the main handler is not unit-tested at the
// Deno level (see index_test.ts's own scope: message-building + a Gemini
// no-call grep only), so this is the only piece of the delete-filter logic
// a `deno test` can actually exercise.

/** The shape this module reads off a `scheduled_workouts` row. */
export interface ScheduledRowTemplateRef {
  template_id: string | null;
}

/** The shape this module reads off a `workout_templates` row. */
export interface TemplateDeletedRef {
  id: string;
  deleted_at: string | null;
}

/**
 * The set of template ids that are soft-deleted (migration 145's
 * `deleted_at`), derived from an already-fetched templates batch -- never a
 * fresh query. A "window closing" nudge for a scheduled day whose template
 * is in this set is stale (the template was deleted elsewhere; unscheduling
 * is local-only today, so the cloud row can outlive the deletion) and must
 * be excluded, not merely lose its personalised name.
 */
export function deletedTemplateIds(
  templates: readonly TemplateDeletedRef[],
): Set<string> {
  const out = new Set<string>();
  for (const t of templates) {
    if (t.deleted_at != null) out.add(t.id);
  }
  return out;
}

/**
 * Drops every `[userId, row]` entry whose `template_id` is a deleted
 * template. A row with a null `template_id` (a plain, non-template workout
 * day) is NEVER excluded -- this is the exact case an `!inner` embed join
 * would have wrongly dropped (round-2 plan review), which is why this is an
 * application-code filter against an already-fetched set rather than a join.
 */
export function excludeDeletedTemplateRows<T extends ScheduledRowTemplateRef>(
  byUser: Map<string, T>,
  deletedIds: ReadonlySet<string>,
): Map<string, T> {
  const kept = new Map<string, T>();
  for (const [userId, row] of byUser) {
    const tid = row.template_id;
    if (tid && deletedIds.has(tid)) continue;
    kept.set(userId, row);
  }
  return kept;
}
