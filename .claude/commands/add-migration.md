# /add-migration — Create a Supabase migration file

Create a new SQL migration for the change described in $ARGUMENTS.

## Steps
1. Read `/CLAUDE.md` Section 7 (Database Schema) for existing tables
2. **Reserve the number — do not read it off `ls`.** `sh scripts/mint_migration.sh --stub <slug>` (add `--live <snapshot.json>` with a fresh `mcp list_migrations` result when you have MCP). It reserves `mig/N` on the remote, prints `MIG-NNN` and the path, and writes the four-tag header stub. `check_migration_number_reserved.dart` blocks a commit that adds a migration with no reservation.
3. Write the migration SQL into `supabase/migrations/{NNN}_{slug}.sql` (fill in the four-tag header)
4. After applying it, add the ledger entry in the SAME commit; take the hash from `dart run scripts/migration_ledger_hash.dart NNN` (never a raw `sha256sum`) — Gate 39 verifies it against the file

## Rules
- 3-digit sequential numbers, allocated by `scripts/mint_migration.sh` (never by hand). Letter suffixes (`050b`) are manual follow-ups to a published base number
- UUID primary keys: `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`
- `timestamptz` for all date/time columns
- Enable RLS: `ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;`
- Add RLS policy: `CREATE POLICY "Users can access own data" ON {table} FOR ALL USING (auth.uid() = user_id);`
- For public tables (exercise_library, food_database): `CREATE POLICY "Public read" ON {table} FOR SELECT USING (true);`
- Add indexes on frequently queried columns: `CREATE INDEX idx_{table}_{col} ON {table}({col});`
- Use `IF NOT EXISTS` for safety
- Include a comment at top: `-- Migration: {description}`
