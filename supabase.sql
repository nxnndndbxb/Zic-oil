-- ============================================================
-- JACK OIL (ZQL) — FIXED one-time setup / repair script
-- Safe to RE-RUN: every statement is idempotent.
-- Dashboard -> SQL Editor -> New query -> paste -> Run
-- ============================================================

-- ---------- PRODUCTS ----------
create table if not exists products (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  sku text, name text, category text, supplier text,
  series text, api_grade text, size_label text,
  purchase numeric default 0, retail numeric default 0, discounted numeric default 0,
  stock int default 0, reorder int default 5,
  created_at timestamptz default now()
);
alter table products add column if not exists series text;
alter table products add column if not exists api_grade text;
alter table products add column if not exists size_label text;

-- ---------- CUSTOMERS ----------
create table if not exists customers (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text, mobile text, vehicle text, car_model text, next_visit date,
  created_at timestamptz default now()
);
alter table customers add column if not exists car_model text;   -- FIXED: was missing

-- ---------- INVOICES ----------
create table if not exists invoices (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  number text, customer_id bigint, items jsonb,
  subtotal numeric default 0, discount numeric default 0, total numeric default 0, cost numeric default 0,
  payment_type text, paid numeric default 0, service_charges numeric default 0, date timestamptz,
  created_at timestamptz default now()
);
alter table invoices add column if not exists service_charges numeric default 0;  -- FIXED: moved AFTER table creation

-- ---------- EXPENSES ----------
create table if not exists expenses (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text, category text, amount numeric default 0, date date,
  created_at timestamptz default now()
);

-- ---------- INCOMES ----------
create table if not exists incomes (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text, amount numeric default 0, category text, date date,
  created_at timestamptz default now()
);

-- ---------- PURCHASES ----------
create table if not exists purchases (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id bigint, product_name text, supplier text,
  qty int, cost numeric, total numeric, paid text, date date,
  created_at timestamptz default now()
);

-- ---------- SUPPLIERS ----------
create table if not exists suppliers (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text, contact text, mobile text, company text,
  created_at timestamptz default now()
);

-- ---------- SETTINGS ----------
create table if not exists settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  businessname text, owner text, currency text,
  phone text, address text, terms text
);
alter table settings add column if not exists phone text;
alter table settings add column if not exists address text;
alter table settings add column if not exists terms text;

-- ---------- UDHAR (CREDIT) LEDGER ----------
create table if not exists ledger (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id bigint, invoice_id bigint,
  type text,
  amount numeric default 0,
  note text,
  date timestamptz,
  created_at timestamptz default now()
);

-- ---------- SERVICES ----------
create table if not exists services (
  id bigint primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  customer_id bigint, vehicle text,
  mileage bigint default 0,
  oil_product_id bigint, oil_product_name text, oil_qty numeric default 1,
  oil_filter boolean default false, air_filter boolean default false,
  next_date date, next_km bigint default 0,
  cost numeric default 0, notes text, completed boolean default false,
  date timestamptz default now(),
  created_at timestamptz default now()
);

-- ---------- ROW LEVEL SECURITY ----------
alter table products enable row level security;
alter table customers enable row level security;
alter table invoices enable row level security;
alter table expenses enable row level security;
alter table incomes enable row level security;
alter table purchases enable row level security;
alter table suppliers enable row level security;
alter table settings enable row level security;
alter table ledger enable row level security;
alter table services enable row level security;

-- FIXED: drop-if-exists before create so the script can be re-run safely
drop policy if exists own_products on products;
create policy own_products on products for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_customers on customers;
create policy own_customers on customers for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_invoices on invoices;
create policy own_invoices on invoices for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_expenses on expenses;
create policy own_expenses on expenses for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_incomes on incomes;
create policy own_incomes on incomes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_purchases on purchases;
create policy own_purchases on purchases for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_suppliers on suppliers;
create policy own_suppliers on suppliers for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_settings on settings;
create policy own_settings on settings for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_ledger on ledger;
create policy own_ledger on ledger for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists own_services on services;
create policy own_services on services for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------- INVOICE PDF STORAGE ----------
insert into storage.buckets (id, name, public)
values ('invoices', 'invoices', false)
on conflict (id) do nothing;

drop policy if exists own_invoice_files on storage.objects;
create policy own_invoice_files on storage.objects for all
using (
  bucket_id = 'invoices'
  and auth.uid()::text = (storage.foldername(name))[1]
) with check (
  bucket_id = 'invoices'
  and auth.uid()::text = (storage.foldername(name))[1]
);

-- ---------- REALTIME (idempotent — re-run safe) ----------
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='products') then
    alter publication supabase_realtime add table products; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='customers') then
    alter publication supabase_realtime add table customers; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='invoices') then
    alter publication supabase_realtime add table invoices; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='expenses') then
    alter publication supabase_realtime add table expenses; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='incomes') then
    alter publication supabase_realtime add table incomes; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='purchases') then
    alter publication supabase_realtime add table purchases; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='suppliers') then
    alter publication supabase_realtime add table suppliers; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='settings') then
    alter publication supabase_realtime add table settings; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='ledger') then
    alter publication supabase_realtime add table ledger; end if; end $$;
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='services') then
    alter publication supabase_realtime add table services; end if; end $$;
