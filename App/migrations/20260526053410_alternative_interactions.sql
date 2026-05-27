begin;

create table if not exists public.alternative_interactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid null,
  alternative_name text not null,
  alternative_brand text null,
  original_product text not null,
  action text not null,
  created_at timestamptz not null default now()
);

create index if not exists alternative_interactions_created_at_idx on public.alternative_interactions (created_at);

alter table public.alternative_interactions enable row level security;

drop policy if exists "allow all select" on public.alternative_interactions;
create policy "allow all select" on public.alternative_interactions for select using (true);

drop policy if exists "allow all insert" on public.alternative_interactions;
create policy "allow all insert" on public.alternative_interactions for insert with check (true);

drop policy if exists "allow all update" on public.alternative_interactions;
create policy "allow all update" on public.alternative_interactions for update using (true) with check (true);

drop policy if exists "allow all delete" on public.alternative_interactions;
create policy "allow all delete" on public.alternative_interactions for delete using (true);

commit;

