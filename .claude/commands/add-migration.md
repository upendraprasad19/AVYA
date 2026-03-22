# /add-migration — Create a Supabase migration file

Create a new SQL migration for the change described in $ARGUMENTS.

## Steps
1. Read `/CLAUDE.md` Section 7 (Database Schema) for existing tables
2. Check existing migrations in `supabase/migrations/` for the next sequence number
3. Create `supabase/migrations/{NNN}_{description}.sql`
4. Write the migration SQL

## Rules
- Sequential numbering: 001_, 002_, 003_, etc.
- UUID primary keys: `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`
- `timestamptz` for all date/time columns
- Enable RLS: `ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;`
- Add RLS policy: `CREATE POLICY "Users can access own data" ON {table} FOR ALL USING (auth.uid() = user_id);`
- For public tables (exercise_library, food_database): `CREATE POLICY "Public read" ON {table} FOR SELECT USING (true);`
- Add indexes on frequently queried columns: `CREATE INDEX idx_{table}_{col} ON {table}({col});`
- Use `IF NOT EXISTS` for safety
- Include a comment at top: `-- Migration: {description}`
