begin;

create table if not exists public.review_votes (
  id uuid primary key default gen_random_uuid(),
  review_id text not null references public.product_reviews(review_id) on delete cascade,
  user_id uuid null,
  vote text not null, -- helpful / not_helpful
  created_at timestamptz not null default now()
);

create index if not exists review_votes_review_id_idx on public.review_votes (review_id);

alter table public.review_votes enable row level security;

drop policy if exists "allow all select" on public.review_votes;
create policy "allow all select" on public.review_votes for select using (true);

drop policy if exists "allow all insert" on public.review_votes;
create policy "allow all insert" on public.review_votes for insert with check (true);

drop policy if exists "allow all update" on public.review_votes;
create policy "allow all update" on public.review_votes for update using (true) with check (true);

drop policy if exists "allow all delete" on public.review_votes;
create policy "allow all delete" on public.review_votes for delete using (true);

commit;
