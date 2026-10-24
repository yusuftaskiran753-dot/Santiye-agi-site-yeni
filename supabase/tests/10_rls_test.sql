-- ════════════════════════════════════════════════════════════════════════
--  Şantiye Ağı · Güvenlik (RLS / yetki) ve sunucu kuralı testleri
--
--  YALNIZCA TEST VERİTABANINDA çalıştırın (kullanıcı ve ilan ekler):
--    createdb santiye_test
--    psql -v ON_ERROR_STOP=1 -d santiye_test -f supabase/tests/00_supabase_stub.sql
--    psql -v ON_ERROR_STOP=1 -d santiye_test -f supabase/schema.sql
--    psql -v ON_ERROR_STOP=1 -d santiye_test -f supabase/tests/10_rls_test.sql
--
--  Bir kontrol başarısız olursa betik "FAIL: ..." mesajıyla durur. Hepsi
--  geçerse sonda "TÜM GÜVENLİK TESTLERİ GEÇTİ" yazar.
-- ════════════════════════════════════════════════════════════════════════

\set QUIET on
\o /dev/null
reset role;

-- ───────────── Test yardımcıları ─────────────
drop schema if exists test cascade;
create schema test;
grant usage on schema test to anon, authenticated, service_role;

create function test.ok(p_cond boolean, p_msg text) returns void
language plpgsql as $$
begin
  if not coalesce(p_cond, false) then
    raise exception 'FAIL: %', p_msg;
  end if;
end $$;

-- p_sql çalıştırılır; mesajında veya SQLSTATE'inde p_expected geçen bir hata beklenir.
create function test.expect_error(p_sql text, p_expected text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_expected in sqlerrm) = 0 and sqlstate <> p_expected then
      raise exception 'FAIL: % → beklenen "%", gelen "%" (%)', p_sql, p_expected, sqlerrm, sqlstate;
    end if;
    return;
  end;
  raise exception 'FAIL: % → "%" hatası bekleniyordu', p_sql, p_expected;
end $$;

create function test.login(p_user uuid) returns void
language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
$$;

grant execute on all functions in schema test to anon, authenticated, service_role;

-- ───────────── Kullanıcılar ─────────────
-- A, B, C, E: eski hesaplar · D: bugün açılmış hesap
delete from auth.users where id in (
  'a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002',
  'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000004',
  'e0000000-0000-4000-8000-000000000005');
insert into auth.users (id, created_at) values
  ('a0000000-0000-4000-8000-000000000001', now() - interval '10 days'),
  ('b0000000-0000-4000-8000-000000000002', now() - interval '10 days'),
  ('c0000000-0000-4000-8000-000000000003', now() - interval '10 days'),
  ('d0000000-0000-4000-8000-000000000004', now()),
  ('e0000000-0000-4000-8000-000000000005', now() - interval '10 days');
-- Önceki test çalıştırmalarından kalanlar (yalnızca test veritabanı!).
truncate public.reports, public.deals, public.requests, public.notifications, public.client_ops,
  public.rate_events, public.credit_ledger, public.ratings cascade;
delete from public.credit_wallets where user_id in (
  'a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002',
  'c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000004',
  'e0000000-0000-4000-8000-000000000005');
update public.app_settings set free_monthly_unlocks = 1, free_active_listings = 5, report_hide_threshold = 3,
  daily_deal_limit = 30, daily_report_limit = 30, report_min_account_age_hours = 24, join_attempts_per_hour = 10
  where id = 1;

-- ═════════════ 1) Oturumsuz (anon) erişim kapalı ═════════════
set role anon;
select test.login(null);
select test.expect_error('select count(*) from public.profiles', 'permission denied');
select test.expect_error('select count(*) from public.loads', 'permission denied');
select test.expect_error('select public.my_usage()', 'permission denied');
select test.expect_error('select public.is_premium(''a0000000-0000-4000-8000-000000000001'')', 'permission denied');
select test.expect_error(
  'select public.is_blocked_between(''a0000000-0000-4000-8000-000000000001'', ''b0000000-0000-4000-8000-000000000002'')',
  'permission denied');
reset role;

-- ═════════════ 2) Profil: istemci korumalı alanları değiştiremez ═════════════
set role authenticated;
select test.login('a0000000-0000-4000-8000-000000000001');
insert into public.profiles (id, name, company, rating_avg, rating_count, premium_until, company_verified, deals_completed)
values ('b0000000-0000-4000-8000-000000000002', 'Ali Yılmaz', 'Yılmaz Nakliyat', 5, 999, now() + interval '1 year', true, 50);
insert into public.profiles_private (id, phone) values ('b0000000-0000-4000-8000-000000000002', '+905551112233');
do $$
declare
  v public.profiles;
begin
  select * into v from public.profiles where name = 'Ali Yılmaz';
  perform test.ok(v.id = 'a0000000-0000-4000-8000-000000000001', 'profil kimliği oturum sahibine zorlanır');
  perform test.ok(v.rating_avg = 0 and v.rating_count = 0 and v.deals_completed = 0, 'puan alanları istemciden yazılamaz');
  perform test.ok(v.premium_until is null and not v.company_verified, 'Premium ve onay rozeti istemciden verilemez');
  perform test.ok((select id from public.profiles_private) = 'a0000000-0000-4000-8000-000000000001',
                  'telefon kaydı oturum sahibine zorlanır');
end $$;

select test.login('b0000000-0000-4000-8000-000000000002');
insert into public.profiles (id, name) values ('b0000000-0000-4000-8000-000000000002', 'Berk Demir');
insert into public.profiles_private (id, phone) values ('b0000000-0000-4000-8000-000000000002', '+905552223344');
select test.login('c0000000-0000-4000-8000-000000000003');
insert into public.profiles (id, name) values ('c0000000-0000-4000-8000-000000000003', 'Can Kaya');
select test.login('d0000000-0000-4000-8000-000000000004');
insert into public.profiles (id, name) values ('d0000000-0000-4000-8000-000000000004', 'Deniz Ak');
select test.login('e0000000-0000-4000-8000-000000000005');
insert into public.profiles (id, name) values ('e0000000-0000-4000-8000-000000000005', 'Ece Tan');

select test.login('b0000000-0000-4000-8000-000000000002');
do $$
declare
  n int;
begin
  perform test.ok((select count(*) from public.profiles where name in ('Ali Yılmaz', 'Berk Demir', 'Can Kaya', 'Deniz Ak', 'Ece Tan')) = 5,
                  'profiller oturum açanlara açık');
  perform test.ok((select count(*) from public.profiles_private) = 1, 'yalnızca kendi telefonu görünür');
  update public.profiles set name = 'Ele geçirildi' where id = 'a0000000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  perform test.ok(n = 0, 'başkasının profili güncellenemez');
  update public.profiles_private set phone = '+900000000000' where id = 'a0000000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  perform test.ok(n = 0, 'başkasının telefonu değiştirilemez');
end $$;

-- ═════════════ 3) İç yardımcılar çağrılamaz, bilgi sızdırmaz ═════════════
select test.expect_error(
  'select public.is_blocked_between(''a0000000-0000-4000-8000-000000000001'', ''c0000000-0000-4000-8000-000000000003'')',
  'permission denied');
select test.expect_error('select * from public.listing_info(''yuk'', gen_random_uuid())', 'permission denied');
select test.expect_error(
  'select public.notify(''a0000000-0000-4000-8000-000000000001'', ''x'', ''sahte'', '''', '''', null)', 'permission denied');
select test.expect_error('select public.display_name(''a0000000-0000-4000-8000-000000000001'')', 'permission denied');
select test.expect_error(
  'select public.grant_credits(''b0000000-0000-4000-8000-000000000002'', 1000, ''hile'', '''')', 'permission denied');
select test.expect_error(
  'select public.record_and_grant_credit_purchase(''android'', ''fake'', ''b0000000-0000-4000-8000-000000000002'', ''santiye_kredi_5'', 5)',
  'permission denied');
select test.expect_error(
  'select public.set_premium(''b0000000-0000-4000-8000-000000000002'', now() + interval ''1 year'', ''x'', ''x'')',
  'permission denied');
select test.expect_error('select public.op_lookup(gen_random_uuid(), ''deal_action'')', 'permission denied');
select test.expect_error('select public.new_deal_code()', 'permission denied');
reset role;
select public.set_premium('a0000000-0000-4000-8000-000000000001', now() + interval '1 day', 'monthly', 'android');
update public.entitlements set premium_until = null where user_id = 'a0000000-0000-4000-8000-000000000001';
update public.profiles set premium_until = null where id = 'a0000000-0000-4000-8000-000000000001';
select public.set_premium('c0000000-0000-4000-8000-000000000003', now() + interval '1 day', 'monthly', 'android');
set role authenticated;
select test.login('b0000000-0000-4000-8000-000000000002');
select test.ok(not public.is_premium('c0000000-0000-4000-8000-000000000003'), 'başkasının Premium durumu sorgulanamaz');
select test.ok(public.active_listing_count('c0000000-0000-4000-8000-000000000003') = 0, 'başkasının ilan sayısı sorgulanamaz');
select test.expect_error('select count(*) from public.client_ops', 'permission denied');
select test.expect_error('select count(*) from public.rate_events', 'permission denied');
select test.expect_error('select count(*) from public.reports', 'permission denied');
select test.expect_error('select count(*) from public.store_purchases', 'permission denied');

-- ═════════════ 4) İlanlar: sahiplik, gizlilik, ücretsiz ilan sınırı ═════════════
select test.login('a0000000-0000-4000-8000-000000000001');
insert into public.loads (id, owner_id, from_city, to_city, cargo, tons, vehicle, price, load_date, hidden, report_count, boosted_until)
values ('10000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002', 'Ankara', 'İstanbul',
        'Seramik', 20, 'tir', 30000, current_date + 2, true, 99, now() + interval '1 year');
insert into public.loads (id, from_city, to_city, cargo, tons, vehicle, price, load_date) values
  ('10000000-0000-4000-8000-000000000002', 'Ankara', 'İzmir', 'Demir', 22, 'tir', 28000, current_date + 2),
  ('10000000-0000-4000-8000-000000000003', 'Ankara', 'Bursa', 'Kum', 25, 'damperli', 15000, current_date + 2),
  ('10000000-0000-4000-8000-000000000004', 'Ankara', 'Konya', 'Çimento', 24, 'tir', 12000, current_date + 2),
  ('10000000-0000-4000-8000-000000000005', 'Ankara', 'Sivas', 'Tuğla', 20, 'tir', 18000, current_date + 2);
do $$
declare
  v public.loads;
begin
  select * into v from public.loads where id = '10000000-0000-4000-8000-000000000001';
  perform test.ok(v.owner_id = 'a0000000-0000-4000-8000-000000000001', 'ilan sahibi oturum sahibine zorlanır');
  perform test.ok(not v.hidden and v.report_count = 0 and v.boosted_until is null, 'moderasyon/öne çıkarma alanları yazılamaz');
  perform test.ok(public.active_listing_count('a0000000-0000-4000-8000-000000000001') = 5, 'kendi ilan sayısı görülür');
end $$;
select test.expect_error(
  'insert into public.loads (from_city, to_city, cargo, tons, vehicle, load_date) values (''Ankara'', ''Ordu'', ''Fazla'', 5, ''tir'', current_date + 1)',
  'LISTING_LIMIT');
-- Aynı kimlikle tekrar gönderim (çevrimdışı kuyruk): sınır hatası değil, benzersizlik hatası.
select test.expect_error(
  'insert into public.loads (id, from_city, to_city, cargo, tons, vehicle, load_date) values (''10000000-0000-4000-8000-000000000002'', ''Ankara'', ''İzmir'', ''Demir'', 22, ''tir'', current_date + 2)',
  '23505');

-- Tarihi geçen ilan sayılmaz; tarihi ileri alınıp yeniden yayına sokulursa sınır uygulanır.
reset role;
update public.loads set load_date = current_date - 3 where id = '10000000-0000-4000-8000-000000000005';
set role authenticated;
select test.login('a0000000-0000-4000-8000-000000000001');
insert into public.loads (id, from_city, to_city, cargo, tons, vehicle, load_date)
values ('10000000-0000-4000-8000-000000000006', 'Ankara', 'Ordu', 'Fındık çuvalı', 10, 'tir', current_date + 1);
select test.expect_error(
  'update public.loads set load_date = current_date + 5 where id = ''10000000-0000-4000-8000-000000000005''',
  'LISTING_LIMIT');

select test.login('b0000000-0000-4000-8000-000000000002');
do $$
declare
  n int;
begin
  perform test.ok((select count(*) from public.loads where owner_id = 'a0000000-0000-4000-8000-000000000001'
                    and load_date >= current_date) = 5, 'yayındaki ilanlar görünür');
  update public.loads set price = 1 where id = '10000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  perform test.ok(n = 0, 'başkasının ilanı güncellenemez');
  delete from public.loads where id = '10000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  perform test.ok(n = 0, 'başkasının ilanı silinemez');
end $$;
reset role;
update public.loads set hidden = true where id = '10000000-0000-4000-8000-000000000004';
set role authenticated;
select test.login('b0000000-0000-4000-8000-000000000002');
select test.ok((select count(*) from public.loads where id = '10000000-0000-4000-8000-000000000004') = 0,
               'gizlenen ilan başkalarına görünmez');
select test.login('a0000000-0000-4000-8000-000000000001');
select test.ok((select count(*) from public.loads where id = '10000000-0000-4000-8000-000000000004') = 1,
               'gizlenen ilan sahibine görünür');
reset role;
update public.loads set hidden = false where id = '10000000-0000-4000-8000-000000000004';

-- ═════════════ 5) İletişim hakkı, kota ve kredi ═════════════
set role authenticated;
select test.login('b0000000-0000-4000-8000-000000000002');
select test.ok((public.unlock_listing('yuk', '10000000-0000-4000-8000-000000000002') ->> 'method') = 'free', 'ilk hak ücretsiz');
select test.ok((public.unlock_listing('yuk', '10000000-0000-4000-8000-000000000002') ->> 'method') = 'already', 'aynı ilan tekrar hak harcamaz');
select test.ok((public.unlock_listing('yuk', '10000000-0000-4000-8000-000000000003') ->> 'reason') = 'QUOTA', 'ücretsiz hak biter');
select test.ok((public.unlock_listing('yuk', '10000000-0000-4000-8000-000000000003', true) ->> 'reason') = 'QUOTA',
               'kredisi yoksa kredi ile açılmaz');
reset role;
select public.grant_credits('b0000000-0000-4000-8000-000000000002', 1, 'test', '');
set role authenticated;
select test.login('b0000000-0000-4000-8000-000000000002');
select test.ok((public.unlock_listing('yuk', '10000000-0000-4000-8000-000000000003', true) ->> 'method') = 'credit', 'kredi ile açılır');
select test.ok((select balance from public.credit_wallets) = 0, 'kredi düşer');
select test.ok((public.unlock_listing('yuk', '10000000-0000-4000-8000-000000000004', true) ->> 'reason') = 'QUOTA',
               'bakiye bitince yeniden açılmaz');
select test.ok((public.contact_for('yuk', '10000000-0000-4000-8000-000000000002') ->> 'phone') = '+905551112233',
               'hak açılınca telefon görünür');
select test.login('c0000000-0000-4000-8000-000000000003');
select test.expect_error('select public.contact_for(''yuk'', ''10000000-0000-4000-8000-000000000002'')', 'LOCKED');

-- Doğrudan yazma yasak.
select test.login('b0000000-0000-4000-8000-000000000002');
select test.expect_error('update public.credit_wallets set balance = 999', 'permission denied');
select test.expect_error(
  'insert into public.unlocks (user_id, ref_type, ref_id, method) values (''b0000000-0000-4000-8000-000000000002'', ''yuk'', ''10000000-0000-4000-8000-000000000004'', ''free'')',
  'permission denied');
select test.expect_error(
  'insert into public.requests (kind, listing_id, owner_id, requester_id) values (''yuk'', gen_random_uuid(), ''a0000000-0000-4000-8000-000000000001'', ''b0000000-0000-4000-8000-000000000002'')',
  'permission denied');
select test.expect_error('insert into public.deals (title) values (''sahte'')', 'permission denied');
select test.expect_error('update public.entitlements set premium_until = now() + interval ''9 years''', 'permission denied');

-- ═════════════ 6) Çevrimdışı kuyruk: aynı işlem bir kez uygulanır ═════════════
select public.create_request('yuk', '10000000-0000-4000-8000-000000000002', 27000, 22, 'ton', current_date + 2, '', 'Aracım hazır',
                             '0f000000-0000-4000-8000-000000000001');
select public.create_request('yuk', '10000000-0000-4000-8000-000000000002', 27000, 22, 'ton', current_date + 2, '', 'Aracım hazır',
                             '0f000000-0000-4000-8000-000000000001');
select test.ok((select count(*) from public.requests) = 1, 'tekrar gönderilen teklif çift kayıt oluşturmaz');

select test.login('a0000000-0000-4000-8000-000000000001');
select test.ok((select count(*) from public.notifications where type = 'request') = 1, 'tekrar gönderimde ikinci bildirim gitmez');
create temp table t_deal as
  select (public.respond_request((select id from public.requests limit 1), true, '0f000000-0000-4000-8000-000000000002') ->> 'deal_id')::uuid as id;
grant select on t_deal to authenticated;
select test.ok(
  (public.respond_request((select id from public.requests limit 1), true, '0f000000-0000-4000-8000-000000000002') ->> 'deal_id')::uuid
    = (select id from t_deal),
  'tekrar gönderilen kabul aynı anlaşmayı döner (NOT_PENDING hatası vermez)');
select test.expect_error(
  'select public.respond_request((select id from public.requests limit 1), true)', 'NOT_PENDING');

select test.login('b0000000-0000-4000-8000-000000000002');
select public.deal_action((select id from t_deal), 'note', null, 'Yola çıktım', '0f000000-0000-4000-8000-000000000003');
select public.deal_action((select id from t_deal), 'note', null, 'Yola çıktım', '0f000000-0000-4000-8000-000000000003');
select test.ok((select jsonb_array_length(log) from public.deals where id = (select id from t_deal)) = 2,
               'aynı not iki kez eklenmez');
select public.deal_action((select id from t_deal), 'deliver', null, null, '0f000000-0000-4000-8000-000000000004');
select public.deal_action((select id from t_deal), 'deliver', null, null, '0f000000-0000-4000-8000-000000000004');
select test.ok((select status from public.deals where id = (select id from t_deal)) = 'delivered',
               'tekrar gönderilen teslim BAD_STATE vermez');
select test.expect_error('select public.deal_action((select id from t_deal), ''deliver'')', 'BAD_STATE');

-- Başkasının işlem kimliği kullanılamaz.
select test.login('c0000000-0000-4000-8000-000000000003');
select test.expect_error(
  'select public.deal_action((select id from t_deal), ''note'', null, ''x'', ''0f000000-0000-4000-8000-000000000003'')',
  'BAD_INPUT');

select test.login('a0000000-0000-4000-8000-000000000001');
select public.deal_action((select id from t_deal), 'complete');
select public.rate_deal((select id from t_deal), 5, 'Teşekkürler', '0f000000-0000-4000-8000-000000000005');
select public.rate_deal((select id from t_deal), 5, 'Teşekkürler', '0f000000-0000-4000-8000-000000000005');
select test.expect_error('select public.rate_deal((select id from t_deal), 4, ''tekrar'')', 'ALREADY_RATED');
select test.ok((select rating_count from public.profiles where id = 'b0000000-0000-4000-8000-000000000002') = 1,
               'tekrar gönderilen puan bir kez sayılır');

-- ═════════════ 7) Anlaşma kodu ve kod tahmin sınırı ═════════════
create temp table t_manual as
  select * from public.create_deal('Hafriyat taşıma', '', 'customer', 'Ali Usta', 50000, 'havale', '', current_date, '[]'::jsonb);
grant select on t_manual to authenticated;
select test.ok((select code from t_manual) ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$', 'anlaşma kodu güçlü alfabeden üretilir');
select test.expect_error(
  'select public.create_deal(''x'', '''', ''customer'', ''y'', 10, ''havale'', '''', null, ''[{"title":"a","amount":"abc"}]''::jsonb)',
  'BAD_INPUT');

select test.login('c0000000-0000-4000-8000-000000000003');
do $$
begin
  for i in 1..10 loop
    perform test.ok((public.join_deal('ZZZZZZZ' || i::text)).id is null, 'yanlış kod boş sonuç döner');
  end loop;
end $$;
select test.expect_error('select public.join_deal(''ZZZZZZZZ'')', 'RATE_LIMIT');

select test.login('e0000000-0000-4000-8000-000000000005');
select test.ok((public.join_deal(lower((select code from t_manual)))).provider_id = 'e0000000-0000-4000-8000-000000000005',
               'doğru kodla katılınır');

reset role;
update public.app_settings set daily_deal_limit = 1 where id = 1;
set role authenticated;
select test.login('a0000000-0000-4000-8000-000000000001');
select test.expect_error(
  'select public.create_deal(''İkinci kayıt'', '''', ''customer'', ''Veli'', 10, ''havale'', '''', null, ''[]''::jsonb)',
  'RATE_LIMIT');
reset role;
update public.app_settings set daily_deal_limit = 30 where id = 1;

-- ═════════════ 8) Şikâyet: sahte hesap ve kendi ilanı sayılmaz ═════════════
set role authenticated;
select test.login('a0000000-0000-4000-8000-000000000001');
select public.report_content('yuk', '10000000-0000-4000-8000-000000000003', 'Diğer', '');
select test.login('d0000000-0000-4000-8000-000000000004');
select public.report_content('yuk', '10000000-0000-4000-8000-000000000003', 'Sahte veya yanıltıcı ilan', '');
select test.login('b0000000-0000-4000-8000-000000000002');
select public.report_content('yuk', '10000000-0000-4000-8000-000000000003', 'Sahte veya yanıltıcı ilan', '');
select public.report_content('yuk', '10000000-0000-4000-8000-000000000003', 'Sahte veya yanıltıcı ilan', '');
select test.login('c0000000-0000-4000-8000-000000000003');
select public.report_content('yuk', '10000000-0000-4000-8000-000000000003', 'Dolandırıcılık şüphesi', '');
select test.expect_error('select public.report_content(''bilinmeyen'', gen_random_uuid(), ''x'', '''')', 'BAD_INPUT');
reset role;
select test.ok((select report_count from public.loads where id = '10000000-0000-4000-8000-000000000003') = 2,
               'yalnızca eski hesapların başkasının ilanına şikâyeti sayılır');
select test.ok(not (select hidden from public.loads where id = '10000000-0000-4000-8000-000000000003'), 'eşik aşılmadan gizlenmez');
select test.ok((select count(*) from public.reports where target_id = '10000000-0000-4000-8000-000000000003') = 4,
               'tüm şikâyetler yöneticiye kaydedilir');
set role authenticated;
select test.login('e0000000-0000-4000-8000-000000000005');
select public.report_content('yuk', '10000000-0000-4000-8000-000000000003', 'Spam / tekrar eden ilan', '');
select public.report_content('profil', 'a0000000-0000-4000-8000-000000000001', 'Hakaret veya uygunsuz içerik', '');
reset role;
select test.ok((select hidden from public.loads where id = '10000000-0000-4000-8000-000000000003'), 'eşik aşılınca ilan gizlenir');
select test.ok((select report_count from public.profiles where id = 'a0000000-0000-4000-8000-000000000001') = 0,
               'profil şikâyet sayısı herkese açık tabloya yazılmaz');

-- ═════════════ 9) Engelleme ve öne çıkarma ═════════════
set role authenticated;
select test.login('a0000000-0000-4000-8000-000000000001');
insert into public.blocks (blocker_id, blocked_id) values ('a0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000003');
select test.login('c0000000-0000-4000-8000-000000000003');
select test.ok((select count(*) from public.blocks) = 0, 'başkasının engel listesi görünmez');
select test.expect_error('select public.unlock_listing(''yuk'', ''10000000-0000-4000-8000-000000000002'')', 'BLOCKED');
select test.expect_error('select public.boost_listing(''yuk'', ''10000000-0000-4000-8000-000000000002'', ''day'')', 'FORBIDDEN');
reset role;

-- ═════════════ 10) Mağaza kredisi atomik ve idempotent ═════════════
set role service_role;
do $$
declare
  v_key text := 'test-credit-' || gen_random_uuid()::text;
  v_first text;
  v_second text;
begin
  v_first := public.record_and_grant_credit_purchase(
    'android', v_key, 'e0000000-0000-4000-8000-000000000005', 'santiye_kredi_5', 5);
  v_second := public.record_and_grant_credit_purchase(
    'android', v_key, 'e0000000-0000-4000-8000-000000000005', 'santiye_kredi_5', 5);
  perform test.ok(v_first = 'granted', 'ilk kredi satın alımı tanımlanır');
  perform test.ok(v_second = 'already_granted', 'aynı makbuz tekrar kredi tanımlamaz');
  perform test.ok((select balance from public.credit_wallets where user_id = 'e0000000-0000-4000-8000-000000000005') = 5,
                  'cüzdan yalnızca bir kez artar');
  perform test.ok((select count(*) from public.credit_ledger where user_id = 'e0000000-0000-4000-8000-000000000005' and ref = 'android:' || v_key) = 1,
                  'kredi defterinde tek hareket bulunur');
end $$;
reset role;

-- ═════════════ 11) Eski fonksiyon imzaları kaldırıldı ═════════════
select test.ok(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('create_request', 'respond_request', 'deal_action', 'rate_deal')) = 4,
  'her API fonksiyonunun tek imzası var (PostgREST belirsizliği yok)');
select test.ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%pg_temp%')),
  'tüm security definer fonksiyonlarda search_path sabit (pg_temp en sonda)');

drop schema test cascade;
\o
\echo 'TÜM GÜVENLİK TESTLERİ GEÇTİ'
