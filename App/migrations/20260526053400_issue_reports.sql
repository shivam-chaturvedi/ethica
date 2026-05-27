begin;

create table if not exists public.issue_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null,
  barcode text null,
  product_name text not null,
  issue_type text not null,
  description text not null,
  expected text null,
  actual text null,
  created_at timestamptz not null default now()
);

create index if not exists issue_reports_created_at_idx on public.issue_reports (created_at);

alter table public.issue_reports enable row level security;

drop policy if exists "allow all select" on public.issue_reports;
create policy "allow all select" on public.issue_reports for select using (true);

drop policy if exists "allow all insert" on public.issue_reports;
create policy "allow all insert" on public.issue_reports for insert with check (true);

drop policy if exists "allow all update" on public.issue_reports;
create policy "allow all update" on public.issue_reports for update using (true) with check (true);

drop policy if exists "allow all delete" on public.issue_reports;
create policy "allow all delete" on public.issue_reports for delete using (true);

commit;

