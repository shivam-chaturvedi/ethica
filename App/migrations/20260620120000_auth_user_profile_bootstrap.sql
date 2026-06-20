begin;

-- Extra profile fields used by the iOS app after Apple / Google / email sign-in.
alter table public.user_profiles
  add column if not exists auth_provider text null,
  add column if not exists avatar_url text null,
  add column if not exists last_sign_in_at timestamptz null;

comment on column public.user_profiles.auth_provider is
  'Primary auth provider for the account: apple, google, or email.';

-- Auto-create profile + default preferences whenever a new Supabase Auth user is created.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name text;
  v_provider text;
begin
  v_display_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(concat_ws(' ',
      new.raw_user_meta_data->>'given_name',
      new.raw_user_meta_data->>'family_name'
    )), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), '')
  );

  v_provider := coalesce(
    nullif(trim(new.raw_app_meta_data->>'provider'), ''),
    case
      when new.email is not null then 'email'
      else 'unknown'
    end
  );

  insert into public.user_profiles (
    user_id,
    email,
    display_name,
    auth_provider,
    last_sign_in_at,
    updated_at
  )
  values (
    new.id,
    new.email,
    v_display_name,
    v_provider,
    now(),
    now()
  )
  on conflict (user_id) do update
    set email = coalesce(excluded.email, public.user_profiles.email),
        display_name = coalesce(nullif(excluded.display_name, ''), public.user_profiles.display_name),
        auth_provider = coalesce(excluded.auth_provider, public.user_profiles.auth_provider),
        last_sign_in_at = now(),
        updated_at = now();

  insert into public.user_preferences (user_id, preferences, updated_at)
  values (new.id, '{}'::jsonb, now())
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_auth_user();

commit;
