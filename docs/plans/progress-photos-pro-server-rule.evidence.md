<!-- Live read-only catalog evidence E1-E29 for unit B1 (project dedsavbjuwgarrhphgnl), copied verbatim from the author scratchpad on 2026-10-07 after a scan for emails, JWTs, UUIDs, keys and phone numbers (none found). -->

# Live-catalog evidence for the B1 plan (author-run, 2026-10-06, project dedsavbjuwgarrhphgnl = "Avya Project")
SELECT-only; catalog rows and counts; no row data, no ids. Pasted verbatim from the tool results. You may NOT query the database; judge whether these outputs SUPPORT the plan's claims F1-F5, F7 (the live part), F8, F9.

## E1 pg_policies for public.progress_photos and storage.objects (policies mentioning progress)
query: select schemaname, tablename, policyname, cmd, roles, qual, with_check from pg_policies where (schemaname='public' and tablename='progress_photos') or (schemaname='storage' and tablename='objects' and (coalesce(qual,'') ilike '%progress%' or coalesce(with_check,'') ilike '%progress%')) order by schemaname, tablename, policyname;
result:
- public.progress_photos progress_photos_delete_own  DELETE roles={public} qual=((SELECT auth.uid() AS uid) = user_id) with_check=null
- public.progress_photos progress_photos_insert_own  INSERT roles={public} qual=null with_check=((SELECT auth.uid() AS uid) = user_id)
- public.progress_photos progress_photos_select_own  SELECT roles={public} qual=((SELECT auth.uid() AS uid) = user_id)
- public.progress_photos progress_photos_update_own  UPDATE roles={public} qual=((SELECT auth.uid() AS uid) = user_id) with_check=((SELECT auth.uid() AS uid) = user_id)
- storage.objects progress_photos_delete_own  DELETE roles={authenticated} qual=((bucket_id = 'progress-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
- storage.objects progress_photos_insert_own  INSERT roles={authenticated} with_check=((bucket_id = 'progress-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
- storage.objects progress_photos_select_own  SELECT roles={authenticated} qual=((bucket_id = 'progress-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))

## E2 storage.buckets
[{"id":"progress-photos","name":"progress-photos","public":false,"file_size_limit":8388608,"allowed_mime_types":["image/jpeg","image/png","image/webp"]}]

## E3 non-internal triggers on public.progress_photos
[]  (empty)

## E4 columns of public.progress_photos
id uuid NOT NULL default gen_random_uuid(); user_id uuid NOT NULL; storage_path text NOT NULL; body_area text NULL; taken_at timestamptz NOT NULL; weight_kg_at_time numeric NULL; notes text NULL; created_at timestamptz NULL default now()

## E5 constraints on public.progress_photos
progress_photos_pkey PRIMARY KEY (id); progress_photos_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE

## E6 who has photos (counts only)
users_with_photos=1, total_photos=1, pro_users_with_photos=1, non_pro_users_with_photos=0, non_pro_photos=0, non_pro_with_recent_photo_30d=0   (PRO = a subscriptions row with status='active' AND end_date > now())

## E7 subscriptions by status/plan
active/monthly n=4 future_end=3 null_end=0; active/referral_trial n=4 future_end=0; active/yearly n=2 future_end=2; cancelled/monthly n=3 future_end=0; expired/monthly n=1 future_end=0

## E8 privileges and RLS
has_table_privilege('authenticated','public.subscriptions','SELECT')=true; anon SELECT=true; authenticated INSERT on progress_photos=true; relrowsecurity: subscriptions=true, storage.objects=true. (The apply/verify session role was `postgres`.)
public.subscriptions policies: exactly one, subscriptions_select_own, SELECT, roles={public}, qual=((SELECT auth.uid() AS uid) = user_id).

## E9 the three existing cap trigger functions
enforce_chat_app_daily_limit, enforce_food_text_daily_limit, enforce_vision_analysis_daily_limit: prosecdef=false, proconfig=null (plpgsql, SECURITY INVOKER, no search_path).

# ADDED for plan v2 (author-run read-only catalog queries, 2026-10-06, same project) — answers to round-1 findings 4, 5, 6
## E10 every INSERT or ALL policy on storage.objects (query: select policyname, permissive, roles, cmd, with_check, qual from pg_policies where schemaname='storage' and tablename='objects' and cmd in ('INSERT','ALL')) — VERBATIM
9 rows; for every row: permissive=PERMISSIVE, roles={authenticated}, cmd=INSERT, qual=null; with_check text is exactly `((bucket_id = '<B>'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))` with <B> as below; no ALL policy:
- "Allow authenticated uploads to avatars"  <B>=avatars
- "Allow authenticated uploads to banners"  <B>=banners
- "Users can upload own avatar"             <B>=avatars
- "Users can upload own banner"             <B>=banners
- "Users can upload own chat media"         <B>=chat-media
- "Users can upload their own avatar"       <B>=avatars
- "Users can upload their own banner"       <B>=banners
- coach_media_insert_own                    <B>=coach-media
- progress_photos_insert_own                <B>=progress-photos
Every one is scoped to a single bucket; none is scoped to progress-photos except progress_photos_insert_own.
## E11 the three progress-photos policies on storage.objects (select policyname, permissive, roles, cmd ... where qual or with_check ilike '%progress%')
progress_photos_delete_own PERMISSIVE {authenticated} DELETE; progress_photos_insert_own PERMISSIVE {authenticated} INSERT; progress_photos_select_own PERMISSIVE {authenticated} SELECT. (No UPDATE policy mentions progress.)
## E12 non-internal triggers on storage.objects
protect_objects_delete  BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete()
update_objects_updated_at  BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column()
(no INSERT trigger)
## E13 privileges / ownership
has_table_privilege('authenticated','storage.objects','INSERT')=true, SELECT=true; storage.objects owner = supabase_storage_admin; the session role is `postgres` (rolsuper=false); auth.users total = 42.
## E14 the three existing cap trigger functions: language plpgsql, prosecdef=false for all three.
## E15 public.subscriptions columns (is_nullable): id NO (default gen_random_uuid()); user_id NO; plan NO; status YES (default 'active'); start_date NO; end_date NO; razorpay_order_id YES; razorpay_payment_id YES; razorpay_signature YES; created_at YES (default now()); razorpay_subscription_id YES; cancelled_at YES.
## E16 public.subscriptions non-internal triggers and constraints
trigger: trg_set_subscription_cancelled_at BEFORE INSERT OR UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION private.set_subscription_cancelled_at()  (the only one)
constraints: subscriptions_pkey PRIMARY KEY (id); subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE; unique_razorpay_payment_id UNIQUE (razorpay_payment_id)
## E17 users with no subscription row: 35 (of 42 rows in auth.users)

# ADDED for plan v3 (author-run read-only catalog queries, 2026-10-06, same project) — answers to round-2 findings
## E18 roles and privileges (select pg_has_role(...), rolbypassrls, has_table_privilege(...))
postgres: member of authenticated = true; rolbypassrls = true; rolsuper = false; member of supabase_storage_admin = FALSE.
authenticated: DELETE, SELECT, UPDATE on public.progress_photos = true; UPDATE and DELETE on storage.objects = true.
## E19 UPDATE or ALL policies on storage.objects: 6 rows, all PERMISSIVE {authenticated} UPDATE, each qual `((bucket_id = '<B>'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))`, with_check null: avatars x3 ("Allow users to update their own avatars", "Users can update own avatar", "Users can update their own avatar"), banners x3. None for progress-photos, chat-media or coach-media. No ALL policy.
## E20 borrowable users (auth.users joined to public.users, no subscriptions row, no progress_photos row): 35
## E21 public.subscriptions policies, full: exactly one: subscriptions_select_own PERMISSIVE {public} SELECT qual=((SELECT auth.uid() AS uid) = user_id) with_check=null. (The repo's migration 008 creates "users_own_subscriptions" FOR ALL USING (auth.uid() = user_id); it is ABSENT live.)
## E22 relation owners and RLS: storage.buckets and storage.objects owner = supabase_storage_admin (relrowsecurity true, force false); public.subscriptions and public.progress_photos owner = postgres (relrowsecurity true, force false).
## E23 live policies created by repo migrations through the MCP path: chat_media_delete_own (migration 116, applier claude-via-mcp, 2026-07-30; created with a DROP POLICY inside a DO block then CREATE POLICY on storage.objects) EXISTS live, as do coach_media_{select,insert,delete}_own (migration 070, applied by the founder). So a policy on storage.objects HAS been created through the MCP path although the session role `postgres` is not a member of the owner role; ALTER POLICY on storage.objects has no precedent and needs the same ownership.
## E24 project confirmation: list_projects on 2026-10-06 returned id dedsavbjuwgarrhphgnl name "Avya Project" (ap-southeast-1, ACTIVE_HEALTHY, org hwwukmntixflgbxkwavm) and krcrkntuwutvnmdnkfqf "ICANBEFITTER ECOSYSTEM (Website)" (never touched).
## E25 triggers on auth.users (author-run, 2026-10-06, project dedsavbjuwgarrhphgnl): exactly one non-internal: on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_auth_user(), enabled 'O'. (This is why the arbiter script's synthetic user "Alice" has a public.users row: its auth.users INSERT fires it; the existing case 27 grants Alice a subscriptions row, whose FK is public.users(id).)
## E26 (repo, not live) subscriptions policy statements across supabase/migrations/*.sql excluding all_migrations_combined.sql: 006 creates subscriptions_{select,insert,update,delete}_own; 008:68 creates users_own_subscriptions FOR ALL USING (auth.uid() = user_id); 052:41-43 drops insert/update/delete _own; 100:106 ALTERs select_own. NOTHING drops users_own_subscriptions in the repo; live it is absent (E21). So a database rebuilt from the repo carries a self-grant path.

## E27 (2026-10-06, read-only, project dedsavbjuwgarrhphgnl via MCP execute_sql; added after Hermes L2 finding 1) -- every SQL function whose body writes public.subscriptions
Query: pg_proc where prokind='f', schema not pg_catalog/information_schema, prosrc ~* '(insert\s+into|update|delete\s+from|merge\s+into)\s+(public\.)?"?subscriptions"?([^a-z_]|$)', with has_function_privilege for anon/authenticated/service_role.
Result (verbatim): [{"nspname":"public","proname":"redeem_referral_atomic","secdef":true,"args":"p_code text, p_referrer_id uuid, p_referee_id uuid, p_days integer","anon_x":false,"auth_x":false,"svc_x":true}]
Meaning: the ONLY function whose source names a write to subscriptions is redeem_referral_atomic, SECURITY DEFINER, EXECUTE for service_role only (not anon, not authenticated). Limit: a regex over prosrc; dynamic SQL built from strings, or a write through a view, would not match; E21 (policies: only subscriptions_select_own) covers direct client writes.

## E28 (2026-10-06, read-only, MCP get_edge_function, project dedsavbjuwgarrhphgnl; Hermes L12 F4) -- the DEPLOYED verify-subscription
slug verify-subscription, status ACTIVE, version 16, updated_at 1775835287749 (2026-04-10), verify_jwt true. The deployed index.ts carries the same predicate lines as the repo file: `.from("subscriptions").select("plan, status, end_date").eq("user_id", userId).eq("status", "active").order("end_date", { ascending: false }).limit(1).maybeSingle()`, `const expiresAt = new Date(endDate); const isActive = expiresAt.getTime() > Date.now();`, `is_pro: isActive,` (compared by reading both). Meaning: C5's repo-source parity also holds for the deployed copy.

## E29 (2026-10-06, read-only, MCP execute_sql; Hermes L23 F1 and F3) -- writers of the guarded objects, name shadows, search_path, CREATE privilege
One UNION query over catalog tables. Verbatim facts:
- kind 'writer' (pg_proc, prosrc ~* insert/update/delete/merge into storage.objects | public.progress_photos): ZERO rows. No SQL function writes either object (regex over prosrc: dynamic SQL would not match).
- kind 'shadow_func' (functions named now, uid, foldername outside pg_catalog/information_schema): auth.uid and storage.foldername only (the two schema-qualified functions the policy itself names). NO `now` outside pg_catalog.
- kind 'nonstandard_operator' (operators > = >= < <= <> :: outside the catalogs): only schema `extensions`, types halfvec, sparsevec, vector (pgvector). None for timestamptz or text.
- search_path role settings: postgres = "$user", public, extensions (pg_catalog NOT listed, so it is searched first implicitly); supabase_admin = "$user", public, auth, extensions; supabase_auth_admin = auth; supabase_storage_admin = storage.
- has_schema_privilege(<role>, 'public', 'CREATE'): anon false, authenticated false, authenticator false, service_role false, postgres true.
Meaning: the Storage policy's unqualified now() and the operators bind to pg_catalog on the live database under the apply role's own search_path; no shadow exists to bind to.
