-- Ethica (iOS) - Supabase bootstrap
-- This migration creates the minimal DB objects the current app uses directly:
-- - `public.product_submissions` (used by ProductSubmissionService via PostgREST)
--
-- NOTE: Column names intentionally match the JSON keys sent by the app (camelCase),
-- so PostgREST inserts work without quoting on the client side.

begin;

create table if not exists public.product_submissions (
  id bigserial primary key,
  barcode text not null,
  "productName" text not null,
  brand text null,
  "ingredientsText" text null,
  "nutritionFactsText" text null,
  "dietaryTags" text[] not null default '{}'::text[],
  notes text null,
  "photosBase64" text[] not null default '{}'::text[],
  "userId" uuid not null,
  "createdAt" timestamptz not null default now(),
  source text not null default 'ios_app',
  status text not null default 'pending_review'
);

create index if not exists product_submissions_user_id_idx
  on public.product_submissions ("userId");

create index if not exists product_submissions_barcode_idx
  on public.product_submissions (barcode);

alter table public.product_submissions enable row level security;

-- "Allow all" policies (as requested). This is NOT recommended for production.
drop policy if exists "allow all select" on public.product_submissions;
create policy "allow all select"
  on public.product_submissions
  for select
  using (true);

drop policy if exists "allow all insert" on public.product_submissions;
create policy "allow all insert"
  on public.product_submissions
  for insert
  with check (true);

drop policy if exists "allow all update" on public.product_submissions;
create policy "allow all update"
  on public.product_submissions
  for update
  using (true)
  with check (true);

drop policy if exists "allow all delete" on public.product_submissions;
create policy "allow all delete"
  on public.product_submissions
  for delete
  using (true);

commit;

