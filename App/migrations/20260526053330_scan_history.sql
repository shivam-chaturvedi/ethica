begin;

create table if not exists public.scan_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null,
  barcode text null,
  product_name text not null,
  brand text null,
  decision text null, -- purchased/avoided/alternative
  source text not null default 'ios_app',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists scan_history_user_id_idx on public.scan_history (user_id);
create index if not exists scan_history_barcode_idx on public.scan_history (barcode);

alter table public.scan_history enable row level security;

drop policy if exists "allow all select" on public.scan_history;
create policy "allow all select" on public.scan_history for select using (true);

drop policy if exists "allow all insert" on public.scan_history;
create policy "allow all insert" on public.scan_history for insert with check (true);

drop policy if exists "allow all update" on public.scan_history;
create policy "allow all update" on public.scan_history for update using (true) with check (true);

drop policy if exists "allow all delete" on public.scan_history;
create policy "allow all delete" on public.scan_history for delete using (true);

commit;

