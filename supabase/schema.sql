-- ════════════════════════════════════════════════════════════════════════
--  Şantiye Ağı · Supabase veritabanı şeması
--
--  Kurulum: Supabase panelinde  SQL Editor → New query  açın, bu dosyanın
--  tamamını yapıştırıp  RUN  deyin. Dosya tekrar çalıştırılabilir; yeni
--  sürümde güncellemek için yine tamamını çalıştırmanız yeterlidir.
--
--  Temel ilke: Uygulama para tutmaz, para hareketine aracılık etmez.
--  Taraflar ödemeyi birbirine doğrudan yapar. Bu şema yalnızca ilanları,
--  talepleri, anlaşma kayıtlarını, puanları ve mağaza (Google Play /
--  App Store) üzerinden satılan dijital hakları (Premium, kredi) tutar.
--
--  Güvenlik: Tüm tablolarda satır bazlı güvenlik (RLS) açıktır. Para değeri
--  olan alanlar (kredi bakiyesi, Premium bitişi, öne çıkarma, şikâyet
--  sayısı) istemciden değiştirilemez; yalnızca aşağıdaki sunucu
--  fonksiyonları ve mağaza doğrulama fonksiyonu (Edge Function) değiştirir.
--
--  v2.1 sıkılaştırmaları:
--    · Tüm kurallar yalnızca oturum açmış kullanıcıya (authenticated) uygulanır;
--      oturumsuz (anon) erişim tamamen kapalıdır.
--    · İç yardımcı fonksiyonlar (engel sorgusu, ilan bilgisi, bildirim…)
--      uygulamadan çağrılamaz; kullanıcı yalnızca kendi bilgisini sorgulayabilir.
--    · Çevrimdışı kuyruktan tekrar gönderilen işlemler (p_op_id) sunucuda
--      bir kez uygulanır; bağlantı koptuğunda çift kayıt oluşmaz.
--    · Kredi/ücretsiz hak harcaması eşzamanlı isteklerde kilitlenir.
--    · Anlaşma kodları 32 karakterli alfabeden üretilir; kod tahmini denemeleri sınırlıdır.
--    · Yeni açılmış hesapların şikâyetleri otomatik gizlemeye sayılmaz (sahte hesap saldırısı).
--
--  Yerel test: supabase/tests/ klasöründeki betiklerle (bkz. dosya başlıkları).
-- ════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- Anlaşma kodu: karışmayan 32 karakter (0/O, 1/I yok) × 8 hane ≈ 1,1 trilyon olasılık.
create or replace function public.new_deal_code() returns text
language plpgsql volatile set search_path = public, pg_temp as $$
declare
  v_chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := gen_random_bytes(8);
  v_code text := '';
begin
  for i in 0..7 loop
    v_code := v_code || substr(v_chars, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_code;
end $$;

-- ───────────────────────── Ayarlar (panelden düzenlenir) ─────────────────────────
-- Uygulama güncellemeden kotaları ve fiyatları buradan değiştirebilirsiniz:
-- Table Editor → app_settings
create table if not exists public.app_settings (
  id int primary key default 1 check (id = 1),
  free_monthly_unlocks int not null default 5,     -- ücretsiz üyeye ayda kaç iletişim/teklif hakkı
  free_active_listings int not null default 5,     -- ücretsiz üyenin aynı anda yayında tutabileceği ilan sayısı
  boost_day_cost int not null default 1,           -- 24 saat öne çıkarma (kredi)
  boost_week_cost int not null default 5,          -- 7 gün öne çıkarma (kredi)
  report_hide_threshold int not null default 3,    -- bu kadar farklı kişi şikâyet edince ilan otomatik gizlenir
  daily_request_limit int not null default 40,     -- spam önleme: günlük teklif/talep sınırı
  daily_listing_limit int not null default 20,     -- spam önleme: günlük yeni ilan sınırı
  announcement text not null default ''            -- ana sayfada herkese gösterilecek duyuru (boşsa gizli)
);
-- v2.1 ayarları (mevcut kurulumlara da eklenir).
alter table public.app_settings add column if not exists daily_deal_limit int not null default 30;        -- günlük elle anlaşma kaydı sınırı
alter table public.app_settings add column if not exists daily_report_limit int not null default 30;      -- günlük şikâyet sınırı
alter table public.app_settings add column if not exists report_min_account_age_hours int not null default 24; -- bundan yeni hesapların şikâyeti gizlemeye sayılmaz
alter table public.app_settings add column if not exists join_attempts_per_hour int not null default 10;  -- saatte en fazla hatalı anlaşma kodu denemesi
insert into public.app_settings (id) values (1) on conflict (id) do nothing;

-- ───────────────────────── Profiller ─────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  company text not null default '' check (char_length(company) <= 120),
  role text not null default 'nakliyeci' check (char_length(role) <= 30),
  city text not null default 'İstanbul' check (char_length(city) <= 40),
  phone_verified boolean not null default false,
  company_verified boolean not null default false,  -- yalnızca siz (panelden) işaretlersiniz
  rating_avg numeric(3, 2) not null default 0,
  rating_count int not null default 0,
  deals_completed int not null default 0,
  report_count int not null default 0,
  premium_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Telefon numarası herkese açık değildir; yalnızca iletişim hakkı açılınca
-- karşı tarafa verilir (contact_for fonksiyonu).
create table if not exists public.profiles_private (
  id uuid primary key references public.profiles (id) on delete cascade,
  phone text not null default '' check (char_length(phone) <= 20),
  updated_at timestamptz not null default now()
);

-- ───────────────────────── İlanlar ─────────────────────────
create table if not exists public.loads (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  from_city text not null check (char_length(from_city) <= 40),
  to_city text not null check (char_length(to_city) <= 40),
  cargo text not null check (char_length(cargo) between 2 and 120),
  tons numeric not null check (tons > 0 and tons <= 1000),
  vehicle text not null check (char_length(vehicle) <= 30),
  price numeric not null default 0 check (price >= 0 and price <= 100000000),
  load_date date not null,
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'active' check (status in ('active', 'closed')),
  hidden boolean not null default false,
  report_count int not null default 0,
  boosted_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.machines (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (char_length(type) <= 30),
  model text not null check (char_length(model) between 2 and 80),
  capacity text not null default '' check (char_length(capacity) <= 80),
  city text not null check (char_length(city) <= 40),
  lat double precision not null,
  lng double precision not null,
  hourly numeric not null default 0 check (hourly >= 0 and hourly <= 10000000),
  daily numeric not null default 0 check (daily >= 0 and daily <= 10000000),
  with_operator boolean not null default true,
  available boolean not null default true,
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'active' check (status in ('active', 'closed')),
  hidden boolean not null default false,
  report_count int not null default 0,
  boosted_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.materials (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (char_length(kind) <= 30),
  product text not null check (char_length(product) between 2 and 80),
  unit text not null check (char_length(unit) <= 10),
  price numeric not null check (price > 0 and price <= 10000000),
  stock text not null default 'bol' check (stock in ('bol', 'az', 'yok')),
  plant_name text not null check (char_length(plant_name) between 2 and 120),
  city text not null check (char_length(city) <= 40),
  lat double precision not null,
  lng double precision not null,
  delivery boolean not null default true,
  min_qty numeric not null default 0 check (min_qty >= 0),
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'active' check (status in ('active', 'closed')),
  hidden boolean not null default false,
  report_count int not null default 0,
  boosted_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 3 and 120),
  role text not null check (char_length(role) <= 30),
  city text not null check (char_length(city) <= 40),
  wage numeric not null default 0 check (wage >= 0 and wage <= 10000000),
  wage_period text not null default 'Günlük' check (char_length(wage_period) <= 20),
  duration text not null default '' check (char_length(duration) <= 60),
  requirements text[] not null default '{}',
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'active' check (status in ('active', 'closed')),
  hidden boolean not null default false,
  report_count int not null default 0,
  boosted_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Operatör / personel sicil kartı (kişi başı bir kart).
create table if not exists public.workers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references public.profiles (id) on delete cascade,
  role text not null check (char_length(role) <= 30),
  city text not null check (char_length(city) <= 40),
  years int not null default 0 check (years between 0 and 60),
  certificates text[] not null default '{}',
  available boolean not null default true,
  about text not null default '' check (char_length(about) <= 500),
  status text not null default 'active' check (status in ('active', 'closed')),
  hidden boolean not null default false,
  report_count int not null default 0,
  boosted_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ───────────────────────── Teklif / talep ─────────────────────────
-- kind: yuk (nakliye teklifi) · makine (kiralama talebi) · malzeme (sipariş)
--       personel (iş başvurusu) · sicil (operatöre iş teklifi)
create table if not exists public.requests (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('yuk', 'makine', 'malzeme', 'personel', 'sicil')),
  listing_id uuid not null,
  listing_title text not null default '',
  owner_id uuid not null references public.profiles (id) on delete cascade,
  requester_id uuid not null references public.profiles (id) on delete cascade,
  amount numeric not null default 0 check (amount >= 0 and amount <= 100000000),
  quantity numeric not null default 0 check (quantity >= 0),
  unit text not null default '' check (char_length(unit) <= 20),
  start_date date,
  address text not null default '' check (char_length(address) <= 300),
  note text not null default '' check (char_length(note) <= 500),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'withdrawn')),
  deal_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists requests_one_pending
  on public.requests (listing_id, requester_id) where status = 'pending';

-- ───────────────────────── Anlaşma kayıtları ─────────────────────────
-- Anlaşma, iki taraf arasındaki işin dijital kaydıdır. Ödeme taraflar
-- arasında doğrudan yapılır; hakediş satırları yalnızca takip içindir.
create table if not exists public.deals (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default public.new_deal_code(),
  kind text not null default 'diger' check (kind in ('yuk', 'makine', 'malzeme', 'personel', 'sicil', 'diger')),
  request_id uuid references public.requests (id) on delete set null,
  title text not null check (char_length(title) between 2 and 160),
  details text not null default '' check (char_length(details) <= 1500),
  customer_id uuid references public.profiles (id) on delete set null,   -- işi veren / alıcı / kiracı
  provider_id uuid references public.profiles (id) on delete set null,   -- hizmeti veren / satıcı / makine sahibi
  customer_name text not null default '',
  provider_name text not null default '',
  created_by uuid references public.profiles (id) on delete set null,
  amount numeric not null default 0 check (amount >= 0 and amount <= 1000000000),
  payment_method text not null default 'havale' check (char_length(payment_method) <= 20),
  payment_terms text not null default '' check (char_length(payment_terms) <= 300),
  start_date date,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'delivered', 'completed', 'cancelled', 'disputed')),
  prev_status text,
  milestones jsonb not null default '[]'::jsonb,
  log jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id) on delete cascade,
  from_id uuid not null references public.profiles (id) on delete cascade,
  to_id uuid not null references public.profiles (id) on delete cascade,
  from_name text not null default '',
  stars int not null check (stars between 1 and 5),
  comment text not null default '' check (char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  unique (deal_id, from_id)
);

-- ───────────────────────── Güven ve güvenlik ─────────────────────────
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  target_type text not null check (target_type in ('yuk', 'makine', 'malzeme', 'personel', 'sicil', 'profil', 'anlasma')),
  target_id uuid not null,
  reason text not null check (char_length(reason) <= 60),
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  unique (reporter_id, target_type, target_id)
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- İletişim hakkı açılan ilanlar (teklif/talep göndermek için de gerekir).
create table if not exists public.unlocks (
  user_id uuid not null references public.profiles (id) on delete cascade,
  ref_type text not null,
  ref_id uuid not null,
  method text not null check (method in ('free', 'premium', 'credit')),
  created_at timestamptz not null default now(),
  primary key (user_id, ref_type, ref_id)
);

-- ───────────────────────── Mağaza hakları ─────────────────────────
create table if not exists public.entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  premium_until timestamptz,
  plan text not null default '',
  platform text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.credit_wallets (
  user_id uuid primary key references auth.users (id) on delete cascade,
  balance int not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.credit_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  delta int not null,
  reason text not null,
  ref text not null default '',
  created_at timestamptz not null default now()
);

-- Aynı mağaza makbuzunun iki kez kullanılmasını engeller.
create table if not exists public.store_purchases (
  platform text not null,
  purchase_key text not null,
  user_id uuid references auth.users (id) on delete set null,
  product_id text not null,
  kind text not null,
  created_at timestamptz not null default now(),
  -- Kredili satın alma ile bakiye artışı aynı DB transaction'ında tamamlanır.
  credits_granted_at timestamptz,
  primary key (platform, purchase_key)
);

-- Var olan kurulumlara güvenli şekilde yükseltme. Eski satın alımların
-- hangilerinde bakiye tanımlamasının başarısız olduğunu eski şema ayırt edemediği
-- için eski kredi kayıtları yeniden tanımlanmaz; olası eski uyuşmazlıklar mağaza
-- kayıtlarıyla mutabakat yapılarak manuel giderilmelidir.
alter table public.store_purchases
  add column if not exists credits_granted_at timestamptz;
update public.store_purchases
  set credits_granted_at = created_at
  where kind = 'credits' and credits_granted_at is null;

-- ───────────────────────── Bildirimler ─────────────────────────
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null default 'info',
  title text not null,
  body text not null default '',
  ref_type text not null default '',
  ref_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- ───────────────────────── Çevrimdışı kuyruk ve kötüye kullanım önleme ─────────────────────────
-- Uygulamanın çevrimdışıyken biriktirip sonra gönderdiği işlemlerin kimlikleri.
-- Aynı işlem (bağlantı koptuğu için) ikinci kez gelirse yeniden uygulanmaz.
-- İstemcinin bu tabloya hiçbir erişimi yoktur.
create table if not exists public.client_ops (
  op_id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  fn text not null,
  ref uuid,
  created_at timestamptz not null default now()
);
create index if not exists client_ops_user_idx on public.client_ops (user_id, created_at);

-- Sayılması gereken ama satırı olmayan olaylar (ör. hatalı anlaşma kodu denemesi).
create table if not exists public.rate_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  created_at timestamptz not null default now()
);
create index if not exists rate_events_user_idx on public.rate_events (user_id, kind, created_at);

-- Mevcut kurulumlarda anlaşma kodunu yeni üreticiye geçir; dizi alanlarına üst sınır koy.
alter table public.deals alter column code set default public.new_deal_code();
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'jobs_requirements_max') then
    alter table public.jobs add constraint jobs_requirements_max check (cardinality(requirements) <= 20) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workers_certificates_max') then
    alter table public.workers add constraint workers_certificates_max check (cardinality(certificates) <= 20) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'materials_min_qty_max') then
    alter table public.materials add constraint materials_min_qty_max check (min_qty <= 10000000) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'requests_quantity_max') then
    alter table public.requests add constraint requests_quantity_max check (quantity <= 100000000) not valid;
  end if;
end $$;

-- ───────────────────────── İndeksler ─────────────────────────
create index if not exists loads_market_idx on public.loads (status, hidden, load_date);
create index if not exists loads_owner_idx on public.loads (owner_id);
create index if not exists machines_owner_idx on public.machines (owner_id);
create index if not exists machines_market_idx on public.machines (status, hidden);
create index if not exists materials_owner_idx on public.materials (owner_id);
create index if not exists materials_market_idx on public.materials (status, hidden, kind);
create index if not exists jobs_owner_idx on public.jobs (owner_id);
create index if not exists jobs_market_idx on public.jobs (status, hidden);
create index if not exists requests_owner_idx on public.requests (owner_id, created_at desc);
create index if not exists requests_requester_idx on public.requests (requester_id, created_at desc);
create index if not exists requests_listing_idx on public.requests (listing_id);
create index if not exists deals_customer_idx on public.deals (customer_id);
create index if not exists deals_provider_idx on public.deals (provider_id);
create index if not exists deals_creator_idx on public.deals (created_by);
create index if not exists ratings_to_idx on public.ratings (to_id, created_at desc);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);
create index if not exists unlocks_month_idx on public.unlocks (user_id, method, created_at);
create index if not exists credit_ledger_user_idx on public.credit_ledger (user_id, created_at desc);
create index if not exists reports_reporter_idx on public.reports (reporter_id, created_at desc);
create index if not exists reports_target_idx on public.reports (target_type, target_id);

-- ════════════════════════════ Yardımcı fonksiyonlar ════════════════════════════

-- İstemciden (uygulamadan) gelen doğrudan bir yazma mı? Sunucu fonksiyonları
-- "security definer" çalıştığı için bu kontrol onlarda false döner.
create or replace function public.is_client_write() returns boolean
language sql stable as $$
  select current_user in ('authenticated', 'anon');
$$;

-- Bu yardımcılar tetikleyicilerde istemci rolüyle de çalıştığı için çağrılabilir
-- kalır; ancak oturum açmış kullanıcı yalnızca KENDİ bilgisini öğrenebilir
-- (başkasının Premium durumu / ilan sayısı sorgulanamaz).
create or replace function public.is_self_or_server(p_user uuid) returns boolean
language sql stable as $$
  select auth.uid() is null or p_user is not distinct from auth.uid();
$$;

create or replace function public.is_premium(p_user uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_self_or_server(p_user) and exists (
    select 1 from public.entitlements e
    where e.user_id = p_user and e.premium_until is not null and e.premium_until > now()
  );
$$;

create or replace function public.display_name(p_user uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select coalesce(nullif(p.company, ''), p.name) from public.profiles p where p.id = p_user), 'Kullanıcı');
$$;

create or replace function public.is_blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

create or replace function public.active_listing_count(p_user uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select case when not public.is_self_or_server(p_user) then 0 else
    (select count(*) from public.loads where owner_id = p_user and status = 'active' and not hidden and load_date >= current_date)::int
  + (select count(*) from public.machines where owner_id = p_user and status = 'active' and not hidden)::int
  + (select count(*) from public.materials where owner_id = p_user and status = 'active' and not hidden)::int
  + (select count(*) from public.jobs where owner_id = p_user and status = 'active' and not hidden)::int
  end;
$$;

create or replace function public.listings_created_today(p_user uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select case when not public.is_self_or_server(p_user) then 0 else
    (select count(*) from public.loads where owner_id = p_user and created_at > now() - interval '1 day')::int
  + (select count(*) from public.machines where owner_id = p_user and created_at > now() - interval '1 day')::int
  + (select count(*) from public.materials where owner_id = p_user and created_at > now() - interval '1 day')::int
  + (select count(*) from public.jobs where owner_id = p_user and created_at > now() - interval '1 day')::int
  end;
$$;

-- ───────────── Tekrar gönderilen işlemler (idempotency) ─────────────
-- p_op: uygulamanın işlem kimliği. Daha önce uygulandıysa kaydedilen referansı
-- (ör. oluşan anlaşmanın kimliği) döner; uygulanmadıysa null. Aynı kimlikle
-- eşzamanlı iki istek gelirse ikincisi birincinin bitmesini bekler.
create or replace function public.op_lookup(p_op uuid, p_fn text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_row public.client_ops;
begin
  if p_op is null then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('op:' || p_op::text, 0));
  select * into v_row from public.client_ops c where c.op_id = p_op;
  if not found then
    return null;
  end if;
  if v_row.user_id is distinct from auth.uid() or v_row.fn <> p_fn then
    raise exception 'BAD_INPUT';
  end if;
  return coalesce(v_row.ref, '00000000-0000-0000-0000-000000000000'::uuid);
end $$;

create or replace function public.op_record(p_op uuid, p_fn text, p_ref uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_op is null or auth.uid() is null then
    return;
  end if;
  insert into public.client_ops (op_id, user_id, fn, ref) values (p_op, auth.uid(), p_fn, p_ref)
  on conflict (op_id) do nothing;
  -- 30 günden eski kayıtlar gereksizdir (kuyruk en geç birkaç gün içinde boşalır).
  delete from public.client_ops c where c.user_id = auth.uid() and c.created_at < now() - interval '30 days';
end $$;

-- Kullanıcı başına işlem kilidi: kota / kredi / günlük sınır kontrolleri
-- eşzamanlı isteklerle aşılamaz.
create or replace function public.lock_user(p_scope text) returns void
language sql security definer set search_path = public, pg_temp as $$
  select pg_advisory_xact_lock(hashtextextended(p_scope || ':' || coalesce(auth.uid()::text, ''), 0));
$$;

-- Bir ilanın sahibi, başlığı ve yayın durumu.
create or replace function public.listing_info(p_kind text, p_id uuid)
returns table (owner_id uuid, title text, status text, hidden boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select l.owner_id, l.from_city || ' → ' || l.to_city || ' · ' || l.cargo, l.status, (l.hidden or l.load_date < current_date)
    from public.loads l where p_kind = 'yuk' and l.id = p_id
  union all
  select m.owner_id, m.model || ' · ' || m.city, m.status, m.hidden
    from public.machines m where p_kind = 'makine' and m.id = p_id
  union all
  select m.owner_id, m.product || ' · ' || m.plant_name, m.status, m.hidden
    from public.materials m where p_kind = 'malzeme' and m.id = p_id
  union all
  select j.owner_id, j.title, j.status, j.hidden
    from public.jobs j where p_kind = 'personel' and j.id = p_id
  union all
  select w.owner_id, coalesce(p.name, 'Operatör') || ' · sicil kartı', w.status, w.hidden
    from public.workers w left join public.profiles p on p.id = w.owner_id
    where p_kind = 'sicil' and w.id = p_id;
$$;

create or replace function public.notify(
  p_user uuid, p_type text, p_title text, p_body text, p_ref_type text, p_ref_id uuid
) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.notifications (user_id, type, title, body, ref_type, ref_id)
  select p_user, p_type, left(p_title, 120), left(coalesce(p_body, ''), 300), coalesce(p_ref_type, ''), p_ref_id
  where p_user is not null and exists (select 1 from public.profiles where id = p_user);
$$;

create or replace function public.format_tl(p_amount numeric) returns text
language sql immutable as $$
  select '₺' || replace(to_char(round(coalesce(p_amount, 0)), 'FM999,999,999,990'), ',', '.');
$$;

-- ════════════════════════════ Tetikleyiciler ════════════════════════════

-- Oturum açan kullanıcının telefonu doğrulanmış mı / doğrulanmış numarası.
-- (Yalnızca kendi bilgisini döndürür.)
create or replace function public.my_confirmed_phone() returns text
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select case when left(u.phone, 1) = '+' then u.phone else '+' || u.phone end
  from auth.users u
  where u.id = auth.uid() and u.phone_confirmed_at is not null and coalesce(u.phone, '') <> '';
$$;

-- Profil: istemci yalnızca ad, firma, rol ve ili değiştirebilir.
-- Not: Tetikleyiciler "security definer" değildir; böylece istemci yazması
-- ile sunucu fonksiyonu yazması ayırt edilebilir.
create or replace function public.tg_profiles_guard() returns trigger
language plpgsql as $$
begin
  if public.is_client_write() then
    if tg_op = 'INSERT' then
      new.id := auth.uid();
      new.company_verified := false;
      new.rating_avg := 0;
      new.rating_count := 0;
      new.deals_completed := 0;
      new.report_count := 0;
      new.premium_until := null;
      new.created_at := now();
    else
      new.id := old.id;
      new.company_verified := old.company_verified;
      new.rating_avg := old.rating_avg;
      new.rating_count := old.rating_count;
      new.deals_completed := old.deals_completed;
      new.report_count := old.report_count;
      new.premium_until := old.premium_until;
      new.created_at := old.created_at;
    end if;
    new.phone_verified := public.my_confirmed_phone() is not null;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before insert or update on public.profiles
  for each row execute function public.tg_profiles_guard();

-- Telefonla giriş yapılmışsa iletişim numarası doğrulanmış numaradır.
create or replace function public.tg_private_guard() returns trigger
language plpgsql as $$
declare
  v_phone text;
begin
  if public.is_client_write() then
    new.id := auth.uid();
    v_phone := public.my_confirmed_phone();
    if v_phone is not null then
      new.phone := v_phone;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists profiles_private_guard on public.profiles_private;
create trigger profiles_private_guard before insert or update on public.profiles_private
  for each row execute function public.tg_private_guard();

-- Telefon doğrulanınca profil rozetini güncelle.
create or replace function public.tg_sync_phone_verified() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.profiles set phone_verified = (new.phone_confirmed_at is not null) where id = new.id;
  return new;
end $$;

drop trigger if exists on_auth_user_phone on auth.users;
create trigger on_auth_user_phone after update of phone_confirmed_at on auth.users
  for each row execute function public.tg_sync_phone_verified();

-- İlanlar: sahibi, gizlilik, öne çıkarma ve şikâyet sayısı istemciden
-- değiştirilemez. Ücretsiz üyelerde aktif ilan sınırı uygulanır.
create or replace function public.tg_listing_guard() returns trigger
language plpgsql as $$
declare
  v_counts boolean;
  v_settings public.app_settings;
  v_exists boolean := false;
  v_reactivates boolean := false;
begin
  v_counts := tg_nargs = 0 or tg_argv[0] <> 'nolimit';
  if public.is_client_write() then
    select * into v_settings from public.app_settings where id = 1;
    if tg_op = 'INSERT' then
      if auth.uid() is null then
        raise exception 'AUTH_REQUIRED';
      end if;
      -- Çevrimdışı kuyruk aynı ilanı (aynı kimlikle) yeniden gönderebilir:
      -- satır zaten varsa sınır kontrolü yapılmaz, ekleme benzersizlik
      -- hatasıyla sonuçlanır ve uygulama bunu "zaten kaydedilmiş" sayar.
      if new.id is not null then
        execute format('select exists (select 1 from %I.%I where id = $1)', tg_table_schema, tg_table_name)
          into v_exists using new.id;
      end if;
      new.owner_id := auth.uid();
      new.hidden := false;
      new.report_count := 0;
      new.boosted_until := null;
      new.created_at := now();
      if not v_exists then
        if public.listings_created_today(auth.uid()) >= v_settings.daily_listing_limit then
          raise exception 'RATE_LIMIT';
        end if;
        if v_counts and new.status = 'active' and not public.is_premium(auth.uid())
           and public.active_listing_count(auth.uid()) >= v_settings.free_active_listings then
          raise exception 'LISTING_LIMIT';
        end if;
      end if;
    else
      new.id := old.id;
      new.owner_id := old.owner_id;
      new.hidden := old.hidden;
      new.report_count := old.report_count;
      new.boosted_until := old.boosted_until;
      new.created_at := old.created_at;
      v_reactivates := old.status <> 'active' and new.status = 'active';
      -- Tarihi geçmiş yük ilanı sayılmaz; tarihi ileri alınarak yeniden
      -- yayına sokulursa ücretsiz ilan sınırı yine uygulanır.
      if tg_table_name = 'loads' then
        if new.status = 'active' and old.load_date < current_date and new.load_date >= current_date then
          v_reactivates := true;
        end if;
      end if;
      if v_counts and v_reactivates and not public.is_premium(auth.uid())
         and public.active_listing_count(auth.uid()) >= v_settings.free_active_listings then
        raise exception 'LISTING_LIMIT';
      end if;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists loads_guard on public.loads;
create trigger loads_guard before insert or update on public.loads
  for each row execute function public.tg_listing_guard('limit');
drop trigger if exists machines_guard on public.machines;
create trigger machines_guard before insert or update on public.machines
  for each row execute function public.tg_listing_guard('limit');
drop trigger if exists materials_guard on public.materials;
create trigger materials_guard before insert or update on public.materials
  for each row execute function public.tg_listing_guard('limit');
drop trigger if exists jobs_guard on public.jobs;
create trigger jobs_guard before insert or update on public.jobs
  for each row execute function public.tg_listing_guard('limit');
drop trigger if exists workers_guard on public.workers;
create trigger workers_guard before insert or update on public.workers
  for each row execute function public.tg_listing_guard('nolimit');

-- İlan silinince bekleyen talepler kapanır.
create or replace function public.tg_listing_deleted() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.requests set status = 'rejected', updated_at = now()
    where listing_id = old.id and status = 'pending';
  return old;
end $$;

drop trigger if exists loads_deleted on public.loads;
create trigger loads_deleted after delete on public.loads for each row execute function public.tg_listing_deleted();
drop trigger if exists machines_deleted on public.machines;
create trigger machines_deleted after delete on public.machines for each row execute function public.tg_listing_deleted();
drop trigger if exists materials_deleted on public.materials;
create trigger materials_deleted after delete on public.materials for each row execute function public.tg_listing_deleted();
drop trigger if exists jobs_deleted on public.jobs;
create trigger jobs_deleted after delete on public.jobs for each row execute function public.tg_listing_deleted();
drop trigger if exists workers_deleted on public.workers;
create trigger workers_deleted after delete on public.workers for each row execute function public.tg_listing_deleted();

-- Puan eklenince / silinince profil ortalamasını yeniden hesapla.
create or replace function public.tg_ratings_aggregate() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := coalesce(new.to_id, old.to_id);
begin
  update public.profiles p set
    rating_avg = coalesce((select round(avg(r.stars)::numeric, 2) from public.ratings r where r.to_id = v_user), 0),
    rating_count = (select count(*) from public.ratings r where r.to_id = v_user)
  where p.id = v_user;
  return null;
end $$;

drop trigger if exists ratings_aggregate on public.ratings;
create trigger ratings_aggregate after insert or delete on public.ratings
  for each row execute function public.tg_ratings_aggregate();

-- ════════════════════════════ Uygulamanın çağırdığı fonksiyonlar ════════════════════════════

-- Kullanım durumu: ücretsiz hak, kredi, Premium.
create or replace function public.my_usage() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_settings public.app_settings;
begin
  select * into v_settings from public.app_settings where id = 1;
  return jsonb_build_object(
    'free_used', (select count(*) from public.unlocks u
                  where u.user_id = v_uid and u.method = 'free' and u.created_at >= date_trunc('month', now())),
    'free_limit', v_settings.free_monthly_unlocks,
    'credits', coalesce((select w.balance from public.credit_wallets w where w.user_id = v_uid), 0),
    'premium_until', (select e.premium_until from public.entitlements e where e.user_id = v_uid),
    'free_listing_limit', v_settings.free_active_listings,
    'active_listings', public.active_listing_count(v_uid),
    'boost_day_cost', v_settings.boost_day_cost,
    'boost_week_cost', v_settings.boost_week_cost,
    'announcement', v_settings.announcement
  );
end $$;

-- İletişim / teklif hakkı açma. Premium: sınırsız. Ücretsiz: ayda
-- free_monthly_unlocks adet. Hak bitince, kullanıcı onay verirse 1 kredi.
create or replace function public.unlock_listing(p_kind text, p_id uuid, p_use_credit boolean default false)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_status text;
  v_hidden boolean;
  v_used int;
  v_limit int;
  v_balance int;
  v_method text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  -- Aynı kullanıcının eşzamanlı istekleri sırayla işlenir (kota ve kredi iki kez harcanmaz).
  perform public.lock_user('unlock');
  select li.owner_id, li.status, li.hidden into v_owner, v_status, v_hidden
    from public.listing_info(p_kind, p_id) li;
  if v_owner is null then
    raise exception 'NOT_FOUND';
  end if;
  if v_owner = v_uid then
    return jsonb_build_object('ok', true, 'method', 'own');
  end if;
  if exists (select 1 from public.unlocks u where u.user_id = v_uid and u.ref_type = p_kind and u.ref_id = p_id) then
    return jsonb_build_object('ok', true, 'method', 'already');
  end if;
  if public.is_blocked_between(v_uid, v_owner) then
    raise exception 'BLOCKED';
  end if;
  if v_hidden or v_status <> 'active' then
    raise exception 'NOT_AVAILABLE';
  end if;

  if public.is_premium(v_uid) then
    v_method := 'premium';
  else
    select s.free_monthly_unlocks into v_limit from public.app_settings s where s.id = 1;
    select count(*) into v_used from public.unlocks u
      where u.user_id = v_uid and u.method = 'free' and u.created_at >= date_trunc('month', now());
    if v_used < v_limit then
      v_method := 'free';
    else
      select coalesce((select w.balance from public.credit_wallets w where w.user_id = v_uid), 0) into v_balance;
      if not p_use_credit or v_balance < 1 then
        return jsonb_build_object('ok', false, 'reason', 'QUOTA', 'credits', v_balance, 'free_limit', v_limit);
      end if;
      update public.credit_wallets set balance = balance - 1, updated_at = now()
        where user_id = v_uid and balance >= 1;
      if not found then
        -- Bakiye bu arada harcanmış: ücretsiz açılmaz.
        return jsonb_build_object('ok', false, 'reason', 'QUOTA', 'credits', 0, 'free_limit', v_limit);
      end if;
      insert into public.credit_ledger (user_id, delta, reason, ref) values (v_uid, -1, 'unlock', p_kind || ':' || p_id);
      v_method := 'credit';
    end if;
  end if;

  insert into public.unlocks (user_id, ref_type, ref_id, method) values (v_uid, p_kind, p_id, v_method)
    on conflict do nothing;
  return jsonb_build_object('ok', true, 'method', v_method);
end $$;

-- Karşı tarafın iletişim bilgisi. İlan için hak açılmış olmalı; talep ve
-- anlaşmalarda yalnızca taraflar görebilir.
create or replace function public.contact_for(p_ref_type text, p_ref_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_other uuid;
  v_owner uuid;
  v_req public.requests;
  v_deal public.deals;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_ref_type in ('yuk', 'makine', 'malzeme', 'personel', 'sicil') then
    select li.owner_id into v_owner from public.listing_info(p_ref_type, p_ref_id) li;
    if v_owner is null then
      raise exception 'NOT_FOUND';
    end if;
    if v_owner <> v_uid and not exists (
      select 1 from public.unlocks u where u.user_id = v_uid and u.ref_type = p_ref_type and u.ref_id = p_ref_id
    ) then
      raise exception 'LOCKED';
    end if;
    v_other := v_owner;
  elsif p_ref_type = 'request' then
    select * into v_req from public.requests r where r.id = p_ref_id;
    if not found then
      raise exception 'NOT_FOUND';
    end if;
    if v_req.owner_id = v_uid then
      v_other := v_req.requester_id;
    elsif v_req.requester_id = v_uid then
      v_other := v_req.owner_id;
    else
      raise exception 'FORBIDDEN';
    end if;
  elsif p_ref_type = 'deal' then
    select * into v_deal from public.deals d where d.id = p_ref_id;
    if not found then
      raise exception 'NOT_FOUND';
    end if;
    if v_deal.customer_id = v_uid then
      v_other := v_deal.provider_id;
    elsif v_deal.provider_id = v_uid then
      v_other := v_deal.customer_id;
    else
      raise exception 'FORBIDDEN';
    end if;
  else
    raise exception 'BAD_INPUT';
  end if;

  if v_other is null then
    return jsonb_build_object('name', '', 'phone', '', 'phone_verified', false);
  end if;
  if v_other <> v_uid and public.is_blocked_between(v_uid, v_other) then
    raise exception 'BLOCKED';
  end if;
  return jsonb_build_object(
    'user_id', v_other,
    'name', public.display_name(v_other),
    'phone', coalesce((select pp.phone from public.profiles_private pp where pp.id = v_other), ''),
    'phone_verified', coalesce((select p.phone_verified from public.profiles p where p.id = v_other), false)
  );
end $$;

-- v2.1: işlem kimliği (p_op_id) parametresi eklenen fonksiyonların eski imzaları.
drop function if exists public.create_request(text, uuid, numeric, numeric, text, date, text, text);
drop function if exists public.respond_request(uuid, boolean);
drop function if exists public.deal_action(uuid, text, int, text);
drop function if exists public.rate_deal(uuid, int, text);

-- Teklif / talep gönderme. İlan için iletişim hakkı açılmış olmalıdır.
create or replace function public.create_request(
  p_kind text,
  p_listing_id uuid,
  p_amount numeric default 0,
  p_quantity numeric default 0,
  p_unit text default '',
  p_start_date date default null,
  p_address text default '',
  p_note text default '',
  p_op_id uuid default null
) returns public.requests
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_title text;
  v_status text;
  v_hidden boolean;
  v_req public.requests;
  v_today int;
  v_limit int;
  v_title_txt text;
  v_body text;
  v_done uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  -- Çevrimdışı kuyruktan tekrar gelen istek: ilk seferki kaydı döndür.
  v_done := public.op_lookup(p_op_id, 'create_request');
  if v_done is not null then
    select * into v_req from public.requests r where r.id = v_done;
    if found then
      return v_req;
    end if;
  end if;
  if p_kind not in ('yuk', 'makine', 'malzeme', 'personel', 'sicil') then
    raise exception 'BAD_INPUT';
  end if;
  if coalesce(p_amount, 0) < 0 or coalesce(p_amount, 0) > 100000000
     or coalesce(p_quantity, 0) < 0 or coalesce(p_quantity, 0) > 100000000 then
    raise exception 'BAD_INPUT';
  end if;
  perform public.lock_user('request');
  select li.owner_id, li.title, li.status, li.hidden into v_owner, v_title, v_status, v_hidden
    from public.listing_info(p_kind, p_listing_id) li;
  if v_owner is null then
    raise exception 'NOT_FOUND';
  end if;
  if v_owner = v_uid then
    raise exception 'OWN_LISTING';
  end if;
  if v_hidden or v_status <> 'active' then
    raise exception 'NOT_AVAILABLE';
  end if;
  if public.is_blocked_between(v_uid, v_owner) then
    raise exception 'BLOCKED';
  end if;
  if not exists (
    select 1 from public.unlocks u where u.user_id = v_uid and u.ref_type = p_kind and u.ref_id = p_listing_id
  ) then
    raise exception 'LOCKED';
  end if;
  select s.daily_request_limit into v_limit from public.app_settings s where s.id = 1;
  select count(*) into v_today from public.requests r
    where r.requester_id = v_uid and r.created_at > now() - interval '1 day';
  if v_today >= v_limit then
    raise exception 'RATE_LIMIT';
  end if;

  v_title_txt := case p_kind
    when 'yuk' then 'Yeni nakliye teklifi'
    when 'makine' then 'Yeni kiralama talebi'
    when 'malzeme' then 'Yeni sipariş talebi'
    when 'personel' then 'Yeni iş başvurusu'
    else 'Yeni iş teklifi' end;
  v_body := public.display_name(v_uid) || ' · ' || v_title
    || case when coalesce(p_amount, 0) > 0 then ' · ' || public.format_tl(p_amount) else '' end;

  -- Bekleyen talep varsa yenisini açmak yerine günceller.
  update public.requests r set
      amount = coalesce(p_amount, 0),
      quantity = coalesce(p_quantity, 0),
      unit = left(coalesce(p_unit, ''), 20),
      start_date = p_start_date,
      address = left(coalesce(p_address, ''), 300),
      note = left(coalesce(p_note, ''), 500),
      updated_at = now()
    where r.listing_id = p_listing_id and r.requester_id = v_uid and r.status = 'pending'
    returning * into v_req;
  if found then
    perform public.notify(v_owner, 'request', v_title_txt || ' (güncellendi)', v_body, 'request', v_req.id);
    perform public.op_record(p_op_id, 'create_request', v_req.id);
    return v_req;
  end if;

  insert into public.requests (kind, listing_id, listing_title, owner_id, requester_id, amount, quantity, unit,
                               start_date, address, note)
  values (p_kind, p_listing_id, v_title, v_owner, v_uid, coalesce(p_amount, 0), coalesce(p_quantity, 0),
          left(coalesce(p_unit, ''), 20), p_start_date, left(coalesce(p_address, ''), 300),
          left(coalesce(p_note, ''), 500))
  returning * into v_req;
  perform public.notify(v_owner, 'request', v_title_txt, v_body, 'request', v_req.id);
  perform public.op_record(p_op_id, 'create_request', v_req.id);
  return v_req;
end $$;

-- İlan sahibi talebi kabul / reddeder. Kabulde anlaşma kaydı oluşur.
create or replace function public.respond_request(p_id uuid, p_accept boolean, p_op_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_req public.requests;
  v_other public.requests;
  v_customer uuid;
  v_provider uuid;
  v_deal uuid;
  v_details text;
  v_milestones jsonb := '[]'::jsonb;
  v_done uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  v_done := public.op_lookup(p_op_id, 'respond_request');
  if v_done is not null then
    return jsonb_build_object('ok', true, 'deal_id',
      case when v_done = '00000000-0000-0000-0000-000000000000'::uuid then null else v_done end);
  end if;
  select * into v_req from public.requests r where r.id = p_id for update;
  if not found then
    raise exception 'NOT_FOUND';
  end if;
  if v_req.owner_id <> v_uid then
    raise exception 'FORBIDDEN';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'NOT_PENDING';
  end if;

  if not p_accept then
    update public.requests set status = 'rejected', updated_at = now() where id = p_id;
    perform public.notify(v_req.requester_id, 'request_rejected', 'Talebiniz kabul edilmedi',
                          v_req.listing_title, 'request', p_id);
    perform public.op_record(p_op_id, 'respond_request', null);
    return jsonb_build_object('ok', true, 'deal_id', null);
  end if;

  if v_req.kind in ('yuk', 'personel') then
    v_customer := v_req.owner_id;
    v_provider := v_req.requester_id;
  else
    v_customer := v_req.requester_id;
    v_provider := v_req.owner_id;
  end if;

  v_details := concat_ws(E'\n',
    case when v_req.quantity > 0 then 'Miktar: ' || replace(trim_scale(v_req.quantity)::text, '.', ',') || ' ' || v_req.unit end,
    case when v_req.start_date is not null then 'Tarih: ' || to_char(v_req.start_date, 'DD.MM.YYYY') end,
    case when v_req.address <> '' then 'Adres: ' || v_req.address end,
    case when v_req.note <> '' then 'Not: ' || v_req.note end);
  if v_req.amount > 0 then
    v_milestones := jsonb_build_array(jsonb_build_object(
      'title', 'Toplam bedel', 'amount', v_req.amount, 'paid_at', null, 'received_at', null));
  end if;

  insert into public.deals (kind, request_id, title, details, customer_id, provider_id, customer_name, provider_name,
                            created_by, amount, start_date, status, milestones, log)
  values (v_req.kind, v_req.id, v_req.listing_title, coalesce(v_details, ''), v_customer, v_provider,
          public.display_name(v_customer), public.display_name(v_provider), v_uid, v_req.amount, v_req.start_date,
          'active', v_milestones,
          jsonb_build_array(jsonb_build_object('at', now(), 'by', public.display_name(v_uid),
                                               'text', 'Talep kabul edildi, anlaşma kaydı oluşturuldu')))
  returning id into v_deal;

  update public.requests set status = 'accepted', deal_id = v_deal, updated_at = now() where id = p_id;
  perform public.notify(v_req.requester_id, 'request_accepted', 'Talebiniz kabul edildi',
                        v_req.listing_title || ' · anlaşma kaydı oluştu', 'deal', v_deal);

  -- Yük tek araçla taşınır: ilan kapanır, diğer bekleyen teklifler reddedilir.
  if v_req.kind = 'yuk' then
    update public.loads set status = 'closed', updated_at = now() where id = v_req.listing_id;
    for v_other in
      select * from public.requests r
      where r.listing_id = v_req.listing_id and r.status = 'pending' and r.id <> p_id
    loop
      update public.requests set status = 'rejected', updated_at = now() where id = v_other.id;
      perform public.notify(v_other.requester_id, 'request_rejected', 'Yük başka bir nakliyeciyle anlaştı',
                            v_other.listing_title, 'request', v_other.id);
    end loop;
  end if;

  perform public.op_record(p_op_id, 'respond_request', v_deal);
  return jsonb_build_object('ok', true, 'deal_id', v_deal);
end $$;

create or replace function public.withdraw_request(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.requests set status = 'withdrawn', updated_at = now()
    where id = p_id and requester_id = auth.uid() and status = 'pending';
  if not found then
    raise exception 'NOT_PENDING';
  end if;
end $$;

-- Elle anlaşma kaydı (ilan dışında yapılan işler için). Karşı taraf
-- uygulamadaysa paylaşılan kodla katılıp onaylar.
create or replace function public.create_deal(
  p_title text,
  p_details text,
  p_my_side text,
  p_counterparty_name text,
  p_amount numeric,
  p_payment_method text,
  p_payment_terms text,
  p_start_date date,
  p_milestones jsonb
) returns public.deals
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_deal public.deals;
  v_name text;
  v_ms jsonb := '[]'::jsonb;
  v_item jsonb;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_my_side not in ('customer', 'provider') then
    raise exception 'BAD_INPUT';
  end if;
  if coalesce(char_length(trim(p_title)), 0) < 2 then
    raise exception 'BAD_INPUT';
  end if;
  if jsonb_typeof(coalesce(p_milestones, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_milestones, '[]'::jsonb)) > 24 then
    raise exception 'BAD_INPUT';
  end if;
  if coalesce(p_amount, 0) < 0 or coalesce(p_amount, 0) > 1000000000 then
    raise exception 'BAD_INPUT';
  end if;
  -- Spam önleme: günlük elle anlaşma kaydı sınırı.
  perform public.lock_user('deal');
  if (select count(*) from public.deals d where d.created_by = v_uid and d.created_at > now() - interval '1 day')
     >= (select s.daily_deal_limit from public.app_settings s where s.id = 1) then
    raise exception 'RATE_LIMIT';
  end if;
  for v_item in select * from jsonb_array_elements(coalesce(p_milestones, '[]'::jsonb)) loop
    if jsonb_typeof(v_item) <> 'object' or coalesce(v_item ->> 'amount', '0') !~ '^[0-9]+(\.[0-9]+)?$' then
      raise exception 'BAD_INPUT';
    end if;
    v_ms := v_ms || jsonb_build_array(jsonb_build_object(
      'title', left(coalesce(nullif(trim(v_item ->> 'title'), ''), 'Ödeme'), 80),
      'amount', least(coalesce((v_item ->> 'amount')::numeric, 0), 1000000000),
      'paid_at', null, 'received_at', null));
  end loop;
  v_name := public.display_name(v_uid);

  insert into public.deals (kind, title, details, customer_id, provider_id, customer_name, provider_name, created_by,
                            amount, payment_method, payment_terms, start_date, status, milestones, log)
  values ('diger', left(trim(p_title), 160), left(coalesce(p_details, ''), 1500),
          case when p_my_side = 'customer' then v_uid end,
          case when p_my_side = 'provider' then v_uid end,
          case when p_my_side = 'customer' then v_name else left(coalesce(p_counterparty_name, ''), 120) end,
          case when p_my_side = 'provider' then v_name else left(coalesce(p_counterparty_name, ''), 120) end,
          v_uid, greatest(coalesce(p_amount, 0), 0), left(coalesce(p_payment_method, 'havale'), 20),
          left(coalesce(p_payment_terms, ''), 300), p_start_date, 'pending', v_ms,
          jsonb_build_array(jsonb_build_object('at', now(), 'by', v_name, 'text', 'Anlaşma kaydı oluşturuldu')))
  returning * into v_deal;
  return v_deal;
end $$;

create or replace function public.join_deal(p_code text) returns public.deals
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_deal public.deals;
  v_name text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  -- Kod tahmin saldırısını önleme: saatte belirli sayıda hatalı deneme.
  perform public.lock_user('join');
  if (select count(*) from public.rate_events e
      where e.user_id = v_uid and e.kind = 'join_fail' and e.created_at > now() - interval '1 hour')
     >= (select s.join_attempts_per_hour from public.app_settings s where s.id = 1) then
    raise exception 'RATE_LIMIT';
  end if;
  select * into v_deal from public.deals d where d.code = upper(trim(coalesce(p_code, ''))) for update;
  if not found then
    -- Hata fırlatılırsa deneme kaydı da geri alınacağı için boş sonuç döner;
    -- uygulama bunu "Kayıt bulunamadı" olarak gösterir.
    insert into public.rate_events (user_id, kind) values (v_uid, 'join_fail');
    return null;
  end if;
  if v_deal.customer_id = v_uid or v_deal.provider_id = v_uid then
    return v_deal;
  end if;
  -- Bekleyen veya karşı tarafı boş (kendi kaydı olarak başlatılmış) anlaşmalara katılınabilir.
  if v_deal.status not in ('pending', 'active') or (v_deal.customer_id is not null and v_deal.provider_id is not null) then
    raise exception 'NOT_AVAILABLE';
  end if;
  if public.is_blocked_between(v_uid, v_deal.created_by) then
    raise exception 'BLOCKED';
  end if;
  v_name := public.display_name(v_uid);
  update public.deals set
      customer_id = coalesce(customer_id, case when customer_id is null then v_uid end),
      customer_name = case when customer_id is null then v_name else customer_name end,
      provider_id = coalesce(provider_id, case when customer_id is not null and provider_id is null then v_uid end),
      provider_name = case when customer_id is not null and provider_id is null then v_name else provider_name end,
      log = log || jsonb_build_array(jsonb_build_object('at', now(), 'by', v_name, 'text', 'Anlaşmaya katıldı')),
      updated_at = now()
    where id = v_deal.id
    returning * into v_deal;
  perform public.notify(v_deal.created_by, 'deal', 'Anlaşmanıza katılım', v_name || ' · ' || v_deal.title, 'deal', v_deal.id);
  return v_deal;
end $$;

-- Anlaşma üzerindeki tüm işlemler.
-- confirm · reject · cancel · deliver · complete · dispute · resolve · mark_paid · mark_received · note
create or replace function public.deal_action(
  p_id uuid, p_action text, p_index int default null, p_note text default null, p_op_id uuid default null
) returns public.deals
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_deal public.deals;
  v_is_c boolean;
  v_is_p boolean;
  v_solo boolean;
  v_can_c boolean;
  v_can_p boolean;
  v_name text;
  v_text text;
  v_note text := left(trim(coalesce(p_note, '')), 300);
  v_count int;
  v_other uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  select * into v_deal from public.deals d where d.id = p_id for update;
  if not found then
    raise exception 'NOT_FOUND';
  end if;
  -- Aynı işlem daha önce uygulandıysa (bağlantı kopup yeniden gönderildiyse)
  -- tekrar uygulanmaz; anlaşmanın güncel hâli döner.
  if public.op_lookup(p_op_id, 'deal_action') is not null then
    if not (v_deal.customer_id is not distinct from v_uid or v_deal.provider_id is not distinct from v_uid
            or v_deal.created_by = v_uid) then
      raise exception 'FORBIDDEN';
    end if;
    return v_deal;
  end if;
  v_is_c := v_deal.customer_id is not distinct from v_uid;
  v_is_p := v_deal.provider_id is not distinct from v_uid;
  if not (v_is_c or v_is_p or v_deal.created_by = v_uid) then
    raise exception 'FORBIDDEN';
  end if;
  -- Karşı taraf uygulamada değilse, kaydı oluşturan iki tarafın işlemlerini de yapabilir.
  v_solo := v_deal.created_by = v_uid and (v_deal.customer_id is null or v_deal.provider_id is null);
  v_can_c := v_is_c or (v_solo and v_deal.customer_id is null);
  v_can_p := v_is_p or (v_solo and v_deal.provider_id is null);
  v_name := public.display_name(v_uid);
  v_count := jsonb_array_length(v_deal.milestones);

  if p_action = 'confirm' then
    if v_deal.status <> 'pending' then raise exception 'BAD_STATE'; end if;
    if v_deal.created_by = v_uid and not v_solo then raise exception 'WAITING_OTHER'; end if;
    v_deal.status := 'active';
    v_text := 'Anlaşma onaylandı';
  elsif p_action = 'reject' then
    if v_deal.status <> 'pending' or v_deal.created_by = v_uid then raise exception 'BAD_STATE'; end if;
    v_deal.status := 'cancelled';
    v_text := 'Anlaşma reddedildi';
  elsif p_action = 'cancel' then
    if v_deal.status not in ('pending', 'active', 'disputed') then raise exception 'BAD_STATE'; end if;
    v_deal.status := 'cancelled';
    v_text := 'Anlaşma iptal edildi' || case when v_note <> '' then ': ' || v_note else '' end;
  elsif p_action = 'deliver' then
    if not v_can_p or v_deal.status <> 'active' then raise exception 'BAD_STATE'; end if;
    v_deal.status := 'delivered';
    v_text := 'İş tamamlandı / teslim edildi olarak bildirildi';
  elsif p_action = 'complete' then
    if not v_can_c or v_deal.status not in ('active', 'delivered') then raise exception 'BAD_STATE'; end if;
    v_deal.status := 'completed';
    v_text := 'Teslim alındı, anlaşma tamamlandı';
    -- Yalnızca iki tarafı da uygulamada olan anlaşmalar sayılır.
    if v_deal.customer_id is not null and v_deal.provider_id is not null then
      update public.profiles set deals_completed = deals_completed + 1
        where id in (v_deal.customer_id, v_deal.provider_id);
    end if;
  elsif p_action = 'dispute' then
    if not (v_is_c or v_is_p or v_solo) or v_deal.status not in ('active', 'delivered') then raise exception 'BAD_STATE'; end if;
    v_deal.prev_status := v_deal.status;
    v_deal.status := 'disputed';
    v_text := 'Sorun bildirildi' || case when v_note <> '' then ': ' || v_note else '' end;
  elsif p_action = 'resolve' then
    if v_deal.status <> 'disputed' then raise exception 'BAD_STATE'; end if;
    v_deal.status := coalesce(v_deal.prev_status, 'active');
    v_deal.prev_status := null;
    v_text := 'Sorun çözüldü olarak işaretlendi';
  elsif p_action = 'mark_paid' then
    if not v_can_c or p_index is null or p_index < 0 or p_index >= v_count then raise exception 'BAD_INPUT'; end if;
    if v_deal.status in ('pending', 'cancelled') then raise exception 'BAD_STATE'; end if;
    v_deal.milestones := jsonb_set(v_deal.milestones, array[p_index::text, 'paid_at'], to_jsonb(now()));
    v_text := (v_deal.milestones -> p_index ->> 'title') || ' ödendi olarak işaretlendi ('
              || public.format_tl((v_deal.milestones -> p_index ->> 'amount')::numeric) || ')';
  elsif p_action = 'mark_received' then
    if not v_can_p or p_index is null or p_index < 0 or p_index >= v_count then raise exception 'BAD_INPUT'; end if;
    if v_deal.status in ('pending', 'cancelled') then raise exception 'BAD_STATE'; end if;
    if (v_deal.milestones -> p_index ->> 'paid_at') is null then
      v_deal.milestones := jsonb_set(v_deal.milestones, array[p_index::text, 'paid_at'], to_jsonb(now()));
    end if;
    v_deal.milestones := jsonb_set(v_deal.milestones, array[p_index::text, 'received_at'], to_jsonb(now()));
    v_text := (v_deal.milestones -> p_index ->> 'title') || ' tahsil edildi ('
              || public.format_tl((v_deal.milestones -> p_index ->> 'amount')::numeric) || ')';
  elsif p_action = 'note' then
    if v_note = '' then raise exception 'BAD_INPUT'; end if;
    v_text := 'Not: ' || v_note;
  else
    raise exception 'BAD_INPUT';
  end if;

  update public.deals set
      status = v_deal.status,
      prev_status = v_deal.prev_status,
      milestones = v_deal.milestones,
      log = log || jsonb_build_array(jsonb_build_object('at', now(), 'by', v_name, 'text', v_text)),
      updated_at = now()
    where id = p_id
    returning * into v_deal;

  v_other := case when v_is_c then v_deal.provider_id when v_is_p then v_deal.customer_id end;
  if v_other is not null and v_other <> v_uid then
    perform public.notify(v_other, 'deal', v_deal.title, v_name || ': ' || v_text, 'deal', v_deal.id);
  end if;
  perform public.op_record(p_op_id, 'deal_action', v_deal.id);
  return v_deal;
end $$;

-- Tamamlanan anlaşmadan sonra karşı tarafı puanlama (kişi başı bir kez).
create or replace function public.rate_deal(
  p_deal uuid, p_stars int, p_comment text default '', p_op_id uuid default null
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_deal public.deals;
  v_other uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if public.op_lookup(p_op_id, 'rate_deal') is not null then
    return;
  end if;
  if p_stars < 1 or p_stars > 5 then
    raise exception 'BAD_INPUT';
  end if;
  select * into v_deal from public.deals d where d.id = p_deal;
  if not found then
    raise exception 'NOT_FOUND';
  end if;
  if v_deal.status <> 'completed' then
    raise exception 'BAD_STATE';
  end if;
  if v_deal.customer_id = v_uid then
    v_other := v_deal.provider_id;
  elsif v_deal.provider_id = v_uid then
    v_other := v_deal.customer_id;
  else
    raise exception 'FORBIDDEN';
  end if;
  if v_other is null then
    raise exception 'NOT_AVAILABLE';
  end if;
  begin
    insert into public.ratings (deal_id, from_id, to_id, from_name, stars, comment)
    values (p_deal, v_uid, v_other, public.display_name(v_uid), p_stars, left(coalesce(p_comment, ''), 300));
  exception when unique_violation then
    raise exception 'ALREADY_RATED';
  end;
  perform public.notify(v_other, 'rating', 'Yeni değerlendirme',
                        public.display_name(v_uid) || ' size ' || p_stars || ' yıldız verdi', 'deal', p_deal);
  perform public.op_record(p_op_id, 'rate_deal', p_deal);
end $$;

-- Şikâyet. Eşik aşılınca ilan otomatik gizlenir (siz panelden geri açabilirsiniz).
-- Sahte hesaplarla rakip ilanı gizleme saldırısına karşı: yalnızca en az
-- report_min_account_age_hours saatlik hesapların şikâyeti sayılır, kişi kendi
-- ilanını şikâyet ederek sayaç artıramaz ve günlük şikâyet sınırı vardır.
-- Profil şikâyetleri herkese açık profil tablosuna yazılmaz (gizlilik);
-- sayısı reports tablosundan görülür.
create or replace function public.report_content(
  p_type text, p_id uuid, p_reason text, p_note text default ''
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_settings public.app_settings;
  v_count int;
  v_owner uuid;
  v_table text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_id is null or p_type is null
     or p_type not in ('yuk', 'makine', 'malzeme', 'personel', 'sicil', 'profil', 'anlasma') then
    raise exception 'BAD_INPUT';
  end if;
  select * into v_settings from public.app_settings s where s.id = 1;
  perform public.lock_user('report');
  if (select count(*) from public.reports r where r.reporter_id = v_uid and r.created_at > now() - interval '1 day')
     >= v_settings.daily_report_limit then
    raise exception 'RATE_LIMIT';
  end if;
  insert into public.reports (reporter_id, target_type, target_id, reason, note)
  values (v_uid, p_type, p_id, left(coalesce(nullif(trim(p_reason), ''), 'Diğer'), 60), left(coalesce(p_note, ''), 500))
  on conflict (reporter_id, target_type, target_id) do nothing;
  if not found then
    return;
  end if;

  v_table := case p_type
    when 'yuk' then 'loads' when 'makine' then 'machines' when 'malzeme' then 'materials'
    when 'personel' then 'jobs' when 'sicil' then 'workers' end;
  if v_table is null then
    return;
  end if;
  -- Yeni açılmış hesabın şikâyeti kaydedilir ama otomatik gizlemeye sayılmaz.
  if not exists (
    select 1 from auth.users u
    where u.id = v_uid and u.created_at <= now() - make_interval(hours => v_settings.report_min_account_age_hours)
  ) then
    return;
  end if;
  select li.owner_id into v_owner from public.listing_info(p_type, p_id) li;
  if v_owner is null or v_owner = v_uid then
    return;
  end if;
  execute format(
    'update public.%I set report_count = report_count + 1, hidden = hidden or report_count + 1 >= $1 '
    'where id = $2 returning report_count', v_table)
    into v_count using v_settings.report_hide_threshold, p_id;

  if v_count = v_settings.report_hide_threshold then
    perform public.notify(v_owner, 'moderation', 'İlanınız incelemeye alındı',
      'Birden fazla kullanıcı şikâyet ettiği için ilanınız geçici olarak yayından kaldırıldı. '
      || 'Hata olduğunu düşünüyorsanız destek adresine yazın.', p_type, p_id);
  end if;
end $$;

-- Öne çıkarma (kredi ile).
create or replace function public.boost_listing(p_kind text, p_id uuid, p_option text) returns timestamptz
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_status text;
  v_hidden boolean;
  v_cost int;
  v_interval interval;
  v_until timestamptz;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  select li.owner_id, li.status, li.hidden into v_owner, v_status, v_hidden from public.listing_info(p_kind, p_id) li;
  if v_owner is null then
    raise exception 'NOT_FOUND';
  end if;
  if v_owner <> v_uid then
    raise exception 'FORBIDDEN';
  end if;
  if v_hidden or v_status <> 'active' then
    raise exception 'NOT_AVAILABLE';
  end if;
  if p_option = 'day' then
    select s.boost_day_cost into v_cost from public.app_settings s where s.id = 1;
    v_interval := interval '1 day';
  elsif p_option = 'week' then
    select s.boost_week_cost into v_cost from public.app_settings s where s.id = 1;
    v_interval := interval '7 days';
  else
    raise exception 'BAD_INPUT';
  end if;

  update public.credit_wallets set balance = balance - v_cost, updated_at = now()
    where user_id = v_uid and balance >= v_cost;
  if not found then
    raise exception 'NO_CREDITS';
  end if;
  insert into public.credit_ledger (user_id, delta, reason, ref) values (v_uid, -v_cost, 'boost_' || p_option, p_kind || ':' || p_id);

  if p_kind = 'yuk' then
    update public.loads set boosted_until = greatest(coalesce(boosted_until, now()), now()) + v_interval
      where id = p_id returning boosted_until into v_until;
  elsif p_kind = 'makine' then
    update public.machines set boosted_until = greatest(coalesce(boosted_until, now()), now()) + v_interval
      where id = p_id returning boosted_until into v_until;
  elsif p_kind = 'malzeme' then
    update public.materials set boosted_until = greatest(coalesce(boosted_until, now()), now()) + v_interval
      where id = p_id returning boosted_until into v_until;
  elsif p_kind = 'personel' then
    update public.jobs set boosted_until = greatest(coalesce(boosted_until, now()), now()) + v_interval
      where id = p_id returning boosted_until into v_until;
  else
    update public.workers set boosted_until = greatest(coalesce(boosted_until, now()), now()) + v_interval
      where id = p_id returning boosted_until into v_until;
  end if;
  return v_until;
end $$;

create or replace function public.mark_notifications_read() returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.notifications set read_at = now() where user_id = auth.uid() and read_at is null;
$$;

-- Hesap silme (Apple ve Google zorunluluğu). Kullanıcının tüm ilanları,
-- talepleri, bildirimleri ve profili silinir. Karşı tarafın kendi kaydı
-- olarak tutulan anlaşmalarda yalnızca ad bilgisi kalır.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  delete from auth.users where id = v_uid;
end $$;

-- ════════════════════════ Yalnızca sunucunun (Edge Function) çağırdığı fonksiyonlar ════════════════════════

create or replace function public.record_store_purchase(
  p_platform text, p_key text, p_user uuid, p_product text, p_kind text
) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_existing uuid;
begin
  insert into public.store_purchases (platform, purchase_key, user_id, product_id, kind)
  values (p_platform, p_key, p_user, p_product, p_kind)
  on conflict (platform, purchase_key) do nothing;
  if found then
    return 'new';
  end if;
  select sp.user_id into v_existing from public.store_purchases sp
    where sp.platform = p_platform and sp.purchase_key = p_key;
  if v_existing is not distinct from p_user then
    return 'same_user';
  end if;
  return 'other_user';
end $$;

-- Satın alma kaydı, kredi defteri ve cüzdan artışı tek atomik işlemde yapılır.
-- Aynı mağaza makbuzu paralel veya yeniden gönderilirse ikinci kez kredi vermez.
create or replace function public.record_and_grant_credit_purchase(
  p_platform text, p_key text, p_user uuid, p_product text, p_amount int
) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid;
  v_product text;
  v_kind text;
  v_granted_at timestamptz;
  v_ref text;
begin
  if p_platform not in ('android', 'ios') or p_key is null or length(p_key) = 0
     or p_user is null or p_product is null or p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_CREDIT_PURCHASE';
  end if;

  insert into public.store_purchases (platform, purchase_key, user_id, product_id, kind)
  values (p_platform, p_key, p_user, p_product, 'credits')
  on conflict (platform, purchase_key) do nothing;

  select user_id, product_id, kind, credits_granted_at
    into v_user, v_product, v_kind, v_granted_at
    from public.store_purchases
   where platform = p_platform and purchase_key = p_key
   for update;

  if v_user is distinct from p_user then
    return 'other_user';
  end if;
  if v_product <> p_product or v_kind <> 'credits' then
    raise exception 'PURCHASE_METADATA_MISMATCH';
  end if;

  if v_granted_at is not null then
    return 'already_granted';
  end if;

  insert into public.credit_wallets (user_id, balance)
  values (p_user, p_amount)
  on conflict (user_id) do update
    set balance = public.credit_wallets.balance + excluded.balance,
        updated_at = now();

  v_ref := p_platform || ':' || p_key;
  insert into public.credit_ledger (user_id, delta, reason, ref)
  values (p_user, p_amount, 'purchase', v_ref);

  update public.store_purchases
     set credits_granted_at = now()
   where platform = p_platform and purchase_key = p_key;

  return 'granted';
end $$;

create or replace function public.grant_credits(p_user uuid, p_amount int, p_reason text, p_ref text) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_balance int;
begin
  insert into public.credit_wallets (user_id, balance) values (p_user, greatest(p_amount, 0))
  on conflict (user_id) do update set balance = public.credit_wallets.balance + greatest(p_amount, 0), updated_at = now()
  returning balance into v_balance;
  insert into public.credit_ledger (user_id, delta, reason, ref) values (p_user, p_amount, p_reason, coalesce(p_ref, ''));
  return v_balance;
end $$;

create or replace function public.set_premium(
  p_user uuid, p_until timestamptz, p_plan text, p_platform text
) returns timestamptz
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_until timestamptz;
begin
  insert into public.entitlements (user_id, premium_until, plan, platform)
  values (p_user, p_until, coalesce(p_plan, ''), coalesce(p_platform, ''))
  on conflict (user_id) do update set
    premium_until = greatest(coalesce(public.entitlements.premium_until, excluded.premium_until), excluded.premium_until),
    plan = excluded.plan,
    platform = excluded.platform,
    updated_at = now()
  returning premium_until into v_until;
  update public.profiles set premium_until = v_until where id = p_user;
  return v_until;
end $$;

-- Abonelik başka bir uygulama hesabında kayıtlıysa (ör. uygulama silinip
-- yeniden kurulduysa) aboneliği ödeyen mağaza hesabının yeni uygulama
-- hesabına taşır; eski hesabın Premium'u sona erer.
create or replace function public.transfer_store_purchase(p_platform text, p_key text, p_user uuid) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_prev uuid;
begin
  select sp.user_id into v_prev from public.store_purchases sp
    where sp.platform = p_platform and sp.purchase_key = p_key for update;
  update public.store_purchases set user_id = p_user where platform = p_platform and purchase_key = p_key;
  if v_prev is not null and v_prev <> p_user then
    update public.entitlements set premium_until = now(), updated_at = now() where user_id = v_prev;
    update public.profiles set premium_until = now() where id = v_prev;
  end if;
  return v_prev;
end $$;

-- ════════════════════════════ Fonksiyon yetkileri ════════════════════════════
-- PostgreSQL ve Supabase yeni fonksiyonları varsayılan olarak herkese (PUBLIC,
-- anon, authenticated) açar. Önce kapatılır, sonra yalnızca gereken rol açılır.

-- 1) Yalnızca mağaza doğrulama fonksiyonunun (Edge Function, service_role) çağırdıkları.
revoke execute on function public.record_store_purchase(text, text, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.transfer_store_purchase(text, text, uuid) from public, anon, authenticated;
revoke execute on function public.grant_credits(uuid, int, text, text) from public, anon, authenticated;
revoke execute on function public.record_and_grant_credit_purchase(text, text, uuid, text, int) from public, anon, authenticated;
revoke execute on function public.set_premium(uuid, timestamptz, text, text) from public, anon, authenticated;
grant execute on function public.record_store_purchase(text, text, uuid, text, text) to service_role;
grant execute on function public.transfer_store_purchase(text, text, uuid) to service_role;
grant execute on function public.grant_credits(uuid, int, text, text) to service_role;
grant execute on function public.record_and_grant_credit_purchase(text, text, uuid, text, int) to service_role;
grant execute on function public.set_premium(uuid, timestamptz, text, text) to service_role;

-- 2) İç yardımcılar: yalnızca diğer sunucu fonksiyonlarının içinden çalışır.
--    (Ör. is_blocked_between açık kalırsa herkes "A, B'yi engellemiş mi?" diye sorgulayabilirdi.)
revoke execute on function public.notify(uuid, text, text, text, text, uuid) from public, anon, authenticated;
revoke execute on function public.is_blocked_between(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.listing_info(text, uuid) from public, anon, authenticated;
revoke execute on function public.display_name(uuid) from public, anon, authenticated;
revoke execute on function public.format_tl(numeric) from public, anon, authenticated;
revoke execute on function public.is_self_or_server(uuid) from public, anon, authenticated;
revoke execute on function public.op_lookup(uuid, text) from public, anon, authenticated;
revoke execute on function public.op_record(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.lock_user(text) from public, anon, authenticated;
revoke execute on function public.new_deal_code() from public, anon, authenticated;

-- 3) Tetikleyicilerin istemci rolüyle çağırdıkları. Yalnızca çağıranın kendi
--    bilgisini döndürür (bkz. is_self_or_server).
revoke execute on function public.is_premium(uuid) from public, anon;
revoke execute on function public.active_listing_count(uuid) from public, anon;
revoke execute on function public.listings_created_today(uuid) from public, anon;
revoke execute on function public.my_confirmed_phone() from public, anon;
revoke execute on function public.is_client_write() from anon;
grant execute on function public.is_premium(uuid) to authenticated, service_role;
grant execute on function public.active_listing_count(uuid) to authenticated, service_role;
grant execute on function public.listings_created_today(uuid) to authenticated, service_role;
grant execute on function public.my_confirmed_phone() to authenticated;
grant execute on function public.is_client_write() to authenticated, service_role;

-- 4) Uygulamanın çağırdığı fonksiyonlar: yalnızca oturum açmış kullanıcı.
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.my_usage()',
    'public.unlock_listing(text, uuid, boolean)',
    'public.contact_for(text, uuid)',
    'public.create_request(text, uuid, numeric, numeric, text, date, text, text, uuid)',
    'public.respond_request(uuid, boolean, uuid)',
    'public.withdraw_request(uuid)',
    'public.create_deal(text, text, text, text, numeric, text, text, date, jsonb)',
    'public.join_deal(text)',
    'public.deal_action(uuid, text, int, text, uuid)',
    'public.rate_deal(uuid, int, text, uuid)',
    'public.report_content(text, uuid, text, text)',
    'public.boost_listing(text, uuid, text)',
    'public.mark_notifications_read()',
    'public.delete_my_account()'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ════════════════════════════ Satır bazlı güvenlik (RLS) ════════════════════════════

do $$
declare
  t text;
begin
  foreach t in array array[
    'app_settings', 'profiles', 'profiles_private', 'loads', 'machines', 'materials', 'jobs', 'workers',
    'requests', 'deals', 'ratings', 'reports', 'blocks', 'unlocks', 'entitlements', 'credit_wallets',
    'credit_ledger', 'store_purchases', 'notifications', 'client_ops', 'rate_events'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    -- Oturumsuz (anon) istemci hiçbir tabloya erişemez.
    execute format('revoke all on public.%I from anon', t);
    -- TRUNCATE satır güvenliğini atlar; REFERENCES/TRIGGER istemciye gerekmez.
    execute format('revoke truncate, references, trigger on public.%I from authenticated', t);
  end loop;
end $$;

drop policy if exists "settings okunur" on public.app_settings;
create policy "settings okunur" on public.app_settings for select to authenticated using (true);

drop policy if exists "profiller herkese açık" on public.profiles;
create policy "profiller herkese açık" on public.profiles for select to authenticated using (true);
drop policy if exists "kendi profilini ekler" on public.profiles;
create policy "kendi profilini ekler" on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
drop policy if exists "kendi profilini günceller" on public.profiles;
create policy "kendi profilini günceller" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "kendi telefonu" on public.profiles_private;
create policy "kendi telefonu" on public.profiles_private for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- İlan tabloları: yayındaki ilanlar oturum açmış herkese açık; sahibi kendi ilanlarını her durumda görür.
do $$
declare
  t text;
begin
  foreach t in array array['loads', 'machines', 'materials', 'jobs', 'workers'] loop
    execute format('drop policy if exists "yayındaki ilanlar" on public.%I', t);
    execute format('create policy "yayındaki ilanlar" on public.%I for select to authenticated using ((status = ''active'' and not hidden) or owner_id = (select auth.uid()))', t);
    execute format('drop policy if exists "ilan ekle" on public.%I', t);
    execute format('create policy "ilan ekle" on public.%I for insert to authenticated with check (owner_id = (select auth.uid()))', t);
    execute format('drop policy if exists "ilan güncelle" on public.%I', t);
    execute format('create policy "ilan güncelle" on public.%I for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()))', t);
    execute format('drop policy if exists "ilan sil" on public.%I', t);
    execute format('create policy "ilan sil" on public.%I for delete to authenticated using (owner_id = (select auth.uid()))', t);
  end loop;
end $$;

drop policy if exists "taraflar görür" on public.requests;
create policy "taraflar görür" on public.requests for select to authenticated
  using (owner_id = (select auth.uid()) or requester_id = (select auth.uid()));

drop policy if exists "taraflar görür" on public.deals;
create policy "taraflar görür" on public.deals for select to authenticated
  using (customer_id = (select auth.uid()) or provider_id = (select auth.uid()) or created_by = (select auth.uid()));

drop policy if exists "puanlar herkese açık" on public.ratings;
create policy "puanlar herkese açık" on public.ratings for select to authenticated using (true);

drop policy if exists "kendi engelleri" on public.blocks;
create policy "kendi engelleri" on public.blocks for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));

drop policy if exists "kendi hakları" on public.unlocks;
create policy "kendi hakları" on public.unlocks for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "kendi aboneliği" on public.entitlements;
create policy "kendi aboneliği" on public.entitlements for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "kendi kredisi" on public.credit_wallets;
create policy "kendi kredisi" on public.credit_wallets for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "kendi kredi hareketleri" on public.credit_ledger;
create policy "kendi kredi hareketleri" on public.credit_ledger for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "kendi bildirimleri" on public.notifications;
create policy "kendi bildirimleri" on public.notifications for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "kendi bildirimini siler" on public.notifications;
create policy "kendi bildirimini siler" on public.notifications for delete to authenticated
  using (user_id = (select auth.uid()));

-- reports, store_purchases, client_ops ve rate_events için hiçbir kural
-- yoktur: istemci bu tabloları göremez ve yazamaz.

-- Ek koruma: istemcinin doğrudan yazamayacağı tablolar (işlemler yalnızca
-- yukarıdaki fonksiyonlarla yapılır).
revoke all on public.reports, public.store_purchases, public.client_ops, public.rate_events from anon, authenticated;
revoke insert, update, delete on public.requests, public.deals, public.ratings, public.unlocks,
  public.entitlements, public.credit_wallets, public.credit_ledger, public.app_settings from anon, authenticated;
revoke insert, update on public.notifications from anon, authenticated;

-- ════════════════════════════ Canlı bildirim (Realtime) ════════════════════════════
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end $$;

-- Kurulum tamam. Yönetim için faydalı sorgular:
--   Şikâyetler:            select * from reports order by created_at desc;
--   Gizlenen ilanı aç:      update loads set hidden = false, report_count = 0 where id = '...';
--   Firma onay rozeti:      update profiles set company_verified = true where id = '...';
--   Duyuru yayınla:         update app_settings set announcement = 'Bakım: 22.00-23.00' where id = 1;
--   Çok şikâyet alan profiller: select target_id, count(*) from reports where target_type = 'profil'
--                               group by 1 order by 2 desc;
--   Eski kuyruk kayıtları:  delete from client_ops where created_at < now() - interval '30 days';
--                           delete from rate_events where created_at < now() - interval '7 days';
