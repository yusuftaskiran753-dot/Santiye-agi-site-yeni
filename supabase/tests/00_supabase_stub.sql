-- ════════════════════════════════════════════════════════════════════════
--  Yerel test için Supabase benzeri ortam (YALNIZCA TEST, canlıda çalıştırmayın)
--
--  Boş bir PostgreSQL 15/16 veritabanında Supabase'in rollerini (anon,
--  authenticated, service_role), auth şemasını ve varsayılan yetkilerini
--  taklit eder. Böylece schema.sql ve RLS kuralları Supabase'e yüklemeden
--  denenebilir:
--
--    createdb santiye_test
--    psql -d santiye_test -f supabase/tests/00_supabase_stub.sql
--    psql -d santiye_test -f supabase/schema.sql
--    psql -d santiye_test -f supabase/tests/10_rls_test.sql
-- ════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin noinherit bypassrls; end if;
end $$;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  email text,
  phone text,
  phone_confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Supabase'deki auth.uid() ile aynı davranış: JWT'deki "sub".
create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  );
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant execute on function auth.role() to anon, authenticated, service_role;

-- Supabase, public şemasındaki yeni nesnelere bu rollerin hepsine tam yetki verir.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
