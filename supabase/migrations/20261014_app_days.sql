-- Usage: one row per collector per day they open Crystamber [Jakarta date].
-- Written only through log_app_open(), which can only log the caller's own
-- day. Nobody can read the table from the app; usage is read with SQL.
create table if not exists public.app_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  primary key (user_id, day)
);
alter table public.app_days enable row level security;

create or replace function public.log_app_open()
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.app_days (user_id, day)
  select auth.uid(), (now() at time zone 'Asia/Jakarta')::date
  where auth.uid() is not null
  on conflict do nothing;
$$;
revoke all on function public.log_app_open() from public, anon;
grant execute on function public.log_app_open() to authenticated;
