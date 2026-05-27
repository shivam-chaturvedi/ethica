begin;

create table if not exists public.user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  email text null,
  display_name text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists user_profiles_user_id_idx
  on public.user_profiles (user_id);

alter table public.user_profiles enable row level security;

drop policy if exists "allow all select" on public.user_profiles;
create policy "allow all select" on public.user_profiles for select using (true);

drop policy if exists "allow all insert" on public.user_profiles;
create policy "allow all insert" on public.user_profiles for insert with check (true);

drop policy if exists "allow all update" on public.user_profiles;
create policy "allow all update" on public.user_profiles for update using (true) with check (true);

drop policy if exists "allow all delete" on public.user_profiles;
create policy "allow all delete" on public.user_profiles for delete using (true);

commit;

