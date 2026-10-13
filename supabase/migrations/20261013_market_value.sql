-- Market value: daily card prices, a dated copy for "this week" changes, the
-- USD -> IDR rate, and each person's choice to see prices or not.
--
-- Prices come from TCGdex [free, no key], which carries TCGplayer market
-- prices per print [1st Edition / Unlimited / Reverse Holo]. Only cards
-- someone owns are priced. The refresh-prices edge function writes these
-- tables with the service role; signed-in people can only read them.

create table public.card_prices (
  set_id     text not null,
  num        text not null,
  usd        jsonb not null default '{}'::jsonb,   -- { "unlimited-holofoil": 50.04, "1st-edition-holofoil": 169.43, ... }
  eur        jsonb not null default '{}'::jsonb,   -- Cardmarket { avg30, trend }
  updated_at timestamptz not null default now(),
  primary key (set_id, num)
);

create table public.price_history (
  day    date not null,
  set_id text not null,
  num    text not null,
  usd    jsonb not null default '{}'::jsonb,
  primary key (day, set_id, num)
);
create index price_history_card_idx on public.price_history (set_id, num, day);

create table public.fx_rates (
  day     date primary key,
  usd_idr numeric not null
);

alter table public.card_prices   enable row level security;
alter table public.price_history enable row level security;
alter table public.fx_rates      enable row level security;

create policy "signed-in read prices"  on public.card_prices   for select to authenticated using (true);
create policy "signed-in read history" on public.price_history for select to authenticated using (true);
create policy "signed-in read fx"      on public.fx_rates      for select to authenticated using (true);

-- Null = not asked yet; the app asks once.
alter table public.profiles add column show_value boolean;
grant update (show_value) on public.profiles to authenticated;

-- Daily refresh at 01:00 UTC [08:00 WIB]. The function skips cards priced in
-- the last 20 hours, so an extra call costs nothing.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- Applied separately after the edge function was deployed:
-- select cron.schedule('refresh-prices-daily', '0 1 * * *', $$
--   select net.http_post(
--     url := 'https://guyrhkzmogqcnemwyilx.supabase.co/functions/v1/refresh-prices',
--     headers := '{"Content-Type":"application/json"}'::jsonb,
--     body := '{}'::jsonb, timeout_milliseconds := 150000) $$);
