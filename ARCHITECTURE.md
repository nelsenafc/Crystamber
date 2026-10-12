# Crystamber architecture

Diagram and full write-up: https://claude.ai/artifact/2go93M4qEKoe9vPgyrSEyN
Source of that page: `docs/architecture.html` [kept off the public site]. Edit it there and republish to the same link.

- **App** - `index.html` [one file, plain JS, no build], `sw.js` [offline], `manifest.webmanifest`. Card data for all 18 sets lives inside `index.html`.
- **Hosting** - Vercel, static. `img/` and `vendor/` cached a year, `sw.js` no-cache.
- **Data** - Supabase [Mumbai, free tier]: Auth [email + password], `profiles`, `user_sets` [one row per user x set, `rev` counter], `groups` / `group_members` [off], `keepalive`. RLS on everything.
- **Saving** - tap -> localStorage -> queued -> upsert that set's row; retries with backoff; on load, read before push, union-merge if two devices both changed a set.
- **Shipping** - push `multi-user` -> wait for commit status -> fast-forward `main` -> live.
- **Keepalive** - `.github/workflows/keepalive.yml`, daily `keepalive_ping()` write.
- **Off for now** - Trades, Group, trade flags behind `const SOCIAL = false`.
