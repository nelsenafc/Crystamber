// Daily market prices for every card someone owns.
//
// Source: TCGdex [api.tcgdex.net, free, no key], which carries TCGplayer
// market prices per print - "1st-edition-holofoil", "unlimited-holofoil",
// "holofoil", "normal", "reverse-holofoil" - plus Cardmarket averages in EUR.
// USD -> IDR from Frankfurter [ECB rates, free, no key].
//
// Called daily by pg_cron, and by the app when someone's cards have no price
// yet. It never re-prices a card priced in the last 12 hours and only prices
// cards that appear in someone's collection, so a stray or repeated call costs
// nothing and can't be used to hammer TCGdex. That is why it runs without a
// JWT check: it reads nothing private and returns only counts.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

// Crystamber set id -> TCGdex set id
const SETS: Record<string, string> = {
  base: "base1", jungle: "base2", fossil: "base3", baseset2: "base4", teamrocket: "base5",
  legendary: "lc", gymheroes: "gym1", gymchallenge: "gym2", neogenesis: "neo1",
  neodiscovery: "neo2", neorevelation: "neo3", neodestiny: "neo4", expedition: "ecard1",
  aquapolis: "ecard2", skyridge: "ecard3", promos: "basep", bestofgame: "bog",
  southernislands: "si1",
};

// Aquapolis and Skyridge holos are stored as 151-182 and printed H1-H32;
// TCGdex calls them H01-H32.
function localId(setId: string, num: string): string {
  const n = Number(num);
  if ((setId === "aquapolis" || setId === "skyridge") && n >= 151) return "H" + String(n - 150).padStart(2, "0");
  return String(n);
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const today = new Date().toISOString().slice(0, 10);

  // Every card anyone owns.
  const { data: rows, error } = await sb.from("user_sets").select("set_id, owned");
  if (error) return json({ error: error.message }, 500);
  const owned = new Set<string>();
  for (const r of rows ?? []) {
    if (!SETS[r.set_id]) continue;
    for (const num of Object.keys(r.owned ?? {})) owned.add(`${r.set_id}|${num}`);
  }

  // Skip what was priced in the last 12 hours, so an evening price never blocks the 08:00 run.
  const since = new Date(Date.now() - 12 * 3600e3).toISOString();
  const { data: fresh } = await sb.from("card_prices").select("set_id, num").gte("updated_at", since);
  const isFresh = new Set((fresh ?? []).map((r) => `${r.set_id}|${r.num}`));
  const todo = [...owned].filter((k) => !isFresh.has(k)).slice(0, 800);

  const prices: Record<string, unknown>[] = [];
  const history: Record<string, unknown>[] = [];
  let next = 0, failed = 0;
  async function worker() {
    while (next < todo.length) {
      const [setId, num] = todo[next++].split("|");
      try {
        const res = await fetch(`https://api.tcgdex.net/v2/en/cards/${SETS[setId]}-${localId(setId, num)}`);
        if (!res.ok) { failed++; continue; }
        const card = await res.json();
        const usd: Record<string, number> = {};
        for (const [variant, p] of Object.entries(card?.pricing?.tcgplayer ?? {})) {
          const m = (p as { marketPrice?: unknown })?.marketPrice;
          if (typeof m === "number" && m > 0) usd[variant] = m;
        }
        const cm = card?.pricing?.cardmarket ?? {};
        const eur: Record<string, number> = {};
        for (const f of ["avg30", "trend", "avg30-holo", "trend-holo"]) if (typeof cm[f] === "number") eur[f] = cm[f];
        const now = new Date().toISOString();
        prices.push({ set_id: setId, num, usd, eur, updated_at: now });
        history.push({ day: today, set_id: setId, num, usd });
      } catch (_) { failed++; }
    }
  }
  await Promise.all(Array.from({ length: 6 }, worker));

  if (prices.length) {
    const a = await sb.from("card_prices").upsert(prices);
    const b = await sb.from("price_history").upsert(history);
    if (a.error || b.error) return json({ error: (a.error ?? b.error)!.message }, 500);
  }

  // Today's USD -> IDR, once a day.
  const { data: fx } = await sb.from("fx_rates").select("day").eq("day", today).maybeSingle();
  if (!fx) {
    try {
      const r = await fetch("https://api.frankfurter.dev/v1/latest?base=USD&symbols=IDR");
      const j = await r.json();
      if (j?.rates?.IDR) await sb.from("fx_rates").upsert({ day: today, usd_idr: j.rates.IDR });
    } catch (_) { /* yesterday's rate still serves */ }
  }

  return json({ owned: owned.size, priced: prices.length, failed, alreadyFresh: isFresh.size });
});
