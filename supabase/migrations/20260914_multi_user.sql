-- Multi-user Crystamber: per-user collections, groups, want and trade lists.
--
-- Additive only. The legacy single-user table collection_sets and its anon
-- policies are left exactly as they were, so the current site keeps working
-- until the new build is switched over.
--
-- Prices are private. RLS is row-level, not column-level, so other people never
-- read user_sets directly - they go through get_binder and group_collections,
-- which are security definer functions that simply do not select the prices column.

-- ─── TABLES ──────────────────────────────────────────────────────────────────

create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  binder_public boolean not null default false,
  created_at    timestamptz not null default now()
);

-- Same shape as collection_sets, keyed by user instead of a hardcoded id, plus
-- the two social lists. One row per (user, set) keeps the per-set sync model.
create table public.user_sets (
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  set_id        text not null,
  owned         jsonb not null default '{}'::jsonb,
  conditions    jsonb not null default '{}'::jsonb,
  prices        jsonb not null default '{}'::jsonb,
  card_editions jsonb not null default '{}'::jsonb,
  wants         jsonb not null default '{}'::jsonb,
  for_trade     jsonb not null default '{}'::jsonb,
  rev           bigint not null default 1,
  updated_at    timestamptz not null default now(),
  primary key (user_id, set_id)
);

-- Reuses the existing trigger function - it only touches rev and updated_at.
create trigger user_sets_bump_rev before update on public.user_sets
  for each row execute function public.bump_collection_set_rev();

create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  invite_code text not null unique,
  created_by  uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.group_members (
  group_id  uuid not null references public.groups(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);

alter table public.profiles      enable row level security;
alter table public.user_sets     enable row level security;
alter table public.groups        enable row level security;
alter table public.group_members enable row level security;

-- ─── HELPERS ─────────────────────────────────────────────────────────────────

-- Security definer so group policies can check membership without recursing
-- into group_members' own policy.
create function public.is_group_member(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid and user_id = (select auth.uid())
  );
$$;

-- Every signup gets a profile. The username comes from signUp metadata; the
-- fallback only exists so a user created from the dashboard does not fail.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(nullif(lower(trim(new.raw_user_meta_data ->> 'username')), ''),
             'user_' || substr(replace(new.id::text, '-', ''), 1, 8))
  );
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─── POLICIES ────────────────────────────────────────────────────────────────

-- Usernames are public so binder links resolve and signup can check availability.
create policy "profiles readable" on public.profiles
  for select to anon, authenticated using (true);
-- The only thing a user may change about their profile is whether the binder is public.
revoke update on public.profiles from anon, authenticated;
grant update (binder_public) on public.profiles to authenticated;
create policy "own profile update" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

revoke all on public.user_sets from anon;
create policy "own sets select" on public.user_sets
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own sets insert" on public.user_sets
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own sets update" on public.user_sets
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Groups and memberships are only ever created through the functions below.
revoke all on public.groups        from anon;
revoke all on public.group_members from anon;
create policy "member reads group" on public.groups
  for select to authenticated using (public.is_group_member(id));
create policy "member reads members" on public.group_members
  for select to authenticated using (public.is_group_member(group_id));
create policy "leave group" on public.group_members
  for delete to authenticated using (user_id = (select auth.uid()));

-- ─── FUNCTIONS ───────────────────────────────────────────────────────────────

create function public.create_group(group_name text) returns public.groups
language plpgsql security definer set search_path = '' as $$
declare g public.groups;
begin
  if (select auth.uid()) is null then raise exception 'Sign in first'; end if;
  insert into public.groups (name, invite_code, created_by)
  values (trim(group_name),
          upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
          (select auth.uid()))
  returning * into g;
  insert into public.group_members (group_id, user_id) values (g.id, (select auth.uid()));
  return g;
end;
$$;

create function public.join_group(code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare gid uuid;
begin
  if (select auth.uid()) is null then raise exception 'Sign in first'; end if;
  select id into gid from public.groups where invite_code = upper(trim(code));
  if gid is null then raise exception 'That invite code does not exist'; end if;
  insert into public.group_members (group_id, user_id)
  values (gid, (select auth.uid())) on conflict do nothing;
  return gid;
end;
$$;

-- Everything the Trades and Group views need, for every member, minus prices.
-- Left join so a member who has not logged a card yet still shows on the board.
create function public.group_collections(gid uuid)
returns table (user_id uuid, username text, set_id text, owned jsonb, conditions jsonb,
               card_editions jsonb, wants jsonb, for_trade jsonb)
language sql stable security definer set search_path = '' as $$
  select gm.user_id, p.username, us.set_id, us.owned, us.conditions,
         us.card_editions, us.wants, us.for_trade
  from public.group_members gm
  join public.profiles p on p.id = gm.user_id
  left join public.user_sets us on us.user_id = gm.user_id
  where gm.group_id = gid and public.is_group_member(gid);
$$;

-- Read-only binder by username, minus prices. Visible when the owner made it
-- public, to the owner, or to anyone who shares a group with them.
create function public.get_binder(uname text)
returns table (username text, set_id text, owned jsonb, conditions jsonb,
               card_editions jsonb, wants jsonb, for_trade jsonb)
language sql stable security definer set search_path = '' as $$
  select p.username, us.set_id, us.owned, us.conditions,
         us.card_editions, us.wants, us.for_trade
  from public.profiles p
  join public.user_sets us on us.user_id = p.id
  where p.username = lower(trim(uname))
    and (p.binder_public
         or p.id = (select auth.uid())
         or exists (select 1 from public.group_members a
                    join public.group_members b on b.group_id = a.group_id
                    where a.user_id = p.id and b.user_id = (select auth.uid())));
$$;

-- Supabase grants execute on new public functions to anon and authenticated by
-- default, so every grant here is explicit.
revoke execute on function public.handle_new_user()          from public, anon, authenticated;
revoke execute on function public.is_group_member(uuid)      from public, anon;
revoke execute on function public.create_group(text)         from public, anon;
revoke execute on function public.join_group(text)           from public, anon;
revoke execute on function public.group_collections(uuid)    from public, anon;
revoke execute on function public.get_binder(text)           from public;
grant  execute on function public.is_group_member(uuid)      to authenticated;
grant  execute on function public.create_group(text)         to authenticated;
grant  execute on function public.join_group(text)           to authenticated;
grant  execute on function public.group_collections(uuid)    to authenticated;
grant  execute on function public.get_binder(text)           to anon, authenticated;
