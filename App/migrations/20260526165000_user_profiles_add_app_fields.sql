begin;

alter table public.user_profiles
  add column if not exists allergens text[] null,
  add column if not exists dietary_tags text[] null,
  add column if not exists is_vegetarian boolean null,
  add column if not exists is_vegan boolean null,
  add column if not exists additional_details jsonb null;

commit;

