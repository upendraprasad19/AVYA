// supabase/functions/_shared/like_escape.ts
//
// Escapes model- or user-supplied text before it goes into a PostgREST `ilike`
// pattern (OI-507, diagnose 2026-11-23-getformcues-lookup-followups).
//
// Without it `%` matches every row and `_` any one character; PostgREST also
// treats `*` as an alias of `%` and that alias cannot be escaped, so `*` is
// removed. Postgres LIKE uses backslash as its default escape character, so the
// backslash itself is escaped FIRST (otherwise the backslashes added for `%`
// and `_` would be doubled).
export function escapeLike(s: string): string {
  return s
    .replace(/\*/g, "")
    .replace(/\\/g, "\\\\")
    .replace(/%/g, "\\%")
    .replace(/_/g, "\\_");
}
