-- Keepalive as a real write. The old ping was a read of collection_sets every
-- three days, and the free tier paused the project anyway [~4 Oct 2026, three
-- days after a successful ping]. A write to its own one-row table is
-- unambiguous database activity and touches no collection data.

create table if not exists public.keepalive (
  id        smallint primary key default 1 check (id = 1),
  pinged_at timestamptz not null default now(),
  pings     bigint not null default 0
);

-- No policies: nobody reads or writes the table directly. Only the function below.
alter table public.keepalive enable row level security;

create or replace function public.keepalive_ping()
returns timestamptz
language sql
security definer
set search_path = public
as $$
  insert into public.keepalive (id, pinged_at, pings) values (1, now(), 1)
  on conflict (id) do update set pinged_at = now(), pings = public.keepalive.pings + 1
  returning pinged_at;
$$;

revoke all on function public.keepalive_ping() from public;
grant execute on function public.keepalive_ping() to anon, authenticated;
