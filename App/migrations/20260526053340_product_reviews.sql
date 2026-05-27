begin;

create table if not exists public.product_reviews (
  review_id text primary key, -- client-generated UUID string
  user_id uuid null,
  user_name text null,
  product_name text not null,
  product_brand text null,
  barcode text null,
  rating double precision not null,
  review text null,
  is_alternative boolean not null default false,
  original_product text null,
  taste_rating double precision null,
  value_rating double precision null,
  availability_rating double precision null,
  helpful_count int not null default 0,
  not_helpful_count int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists product_reviews_product_name_idx on public.product_reviews (product_name);
create index if not exists product_reviews_barcode_idx on public.product_reviews (barcode);

alter table public.product_reviews enable row level security;

drop policy if exists "allow all select" on public.product_reviews;
create policy "allow all select" on public.product_reviews for select using (true);

drop policy if exists "allow all insert" on public.product_reviews;
create policy "allow all insert" on public.product_reviews for insert with check (true);

drop policy if exists "allow all update" on public.product_reviews;
create policy "allow all update" on public.product_reviews for update using (true) with check (true);

drop policy if exists "allow all delete" on public.product_reviews;
create policy "allow all delete" on public.product_reviews for delete using (true);

commit;
