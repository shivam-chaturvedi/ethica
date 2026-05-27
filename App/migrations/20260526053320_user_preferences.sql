begin;

create table if not exists public.user_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  preferences jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists user_preferences_user_id_idx
  on public.user_preferences (user_id);

alter table public.user_preferences enable row level security;

drop policy if exists "allow all select" on public.user_preferences;
create policy "allow all select" on public.user_preferences for select using (true);

drop policy if exists "allow all insert" on public.user_preferences;
create policy "allow all insert" on public.user_preferences for insert with check (true);

drop policy if exists "allow all update" on public.user_preferences;
create policy "allow all update" on public.user_preferences for update using (true) with check (true);

drop policy if exists "allow all delete" on public.user_preferences;
create policy "allow all delete" on public.user_preferences for delete using (true);

commit;

