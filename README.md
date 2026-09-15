# Crystamber

Pokemon card collection tracker for a group of collectors. Each person signs up, marks what they own, records condition, edition and price paid, and flags cards they want or will trade. Groups join through an invite link and get trade matches and a completion board. Anyone can share a read-only binder link.

## Sets covered

Every English WotC-era set - 18 sets, 1,789 cards - grouped by era in the switcher:

- **Base:** Base, Jungle, Fossil, Base Set 2, Team Rocket, Legendary Collection
- **Gym:** Gym Heroes, Gym Challenge
- **Neo:** Neo Genesis, Neo Discovery, Neo Revelation, Neo Destiny
- **e-Card:** Expedition, Aquapolis, Skyridge
- **Promos & specials:** Black Star Promos, Best of Game, Southern Islands

The card lists are hardcoded in `index.html` - no catalog API at runtime. The first seven sets were entered by hand; the other eleven were generated from the [PokemonTCG/pokemon-tcg-data](https://github.com/PokemonTCG/pokemon-tcg-data) dataset in September 2026. Aquapolis and Skyridge print their holos as H1-H32; those are stored as numbers 151-182 so keys and sorting stay numeric, and keep the printed number in `label`.

To add a set: one card array, one `SETS` entry, and its id in `ERAS`.

## Images

Every card has two copies in `img/<set>/`, named by zero-padded card number: AVIF [quality 55] for browsers that support it and WebP [quality 80] as the fallback, served through a `<picture>` element. Both are 400px wide [Gym Heroes, Gym Challenge and Neo Genesis stay at their native 240px, never upscaled]. The AVIF set is 38.4MB against 62.5MB for WebP - 38% less, with no visible difference at card size.

Only the set on screen loads, and within it only the cards near the viewport. Opening the site on a phone pulls about 16 card images.

- For the first seven sets, the original scans stay in the per-set folders [`base/`, `jungle/`, ...] as the source of truth. `.vercelignore` keeps them out of the deploy.
- The other eleven sets were built straight from the pokemontcg.io large images [`images.pokemontcg.io/<set>/<number>_hires.png`]. No originals are kept - that URL is the source.
- To regenerate, resize each source to 400px wide with Pillow [LANCZOS] and save both formats into the matching `img/` folder: WebP `quality=80, method=6`, AVIF `quality=55, speed=6`.
- Vercel serves `img/` with a one-year immutable cache [`vercel.json`], and the service worker caches viewed images the same way. If an image ever changes, write the new files under a new folder name and repoint `imgPath` - overwriting in place leaves browsers on the old copy for a year.
- A missing image falls back to a numbered placeholder, so deleting the folders never breaks the app.

## Stack

Single static `index.html` - no build step. Supabase for auth and cloud sync. `server.js` is a small local dev server.

- **supabase-js is pinned and vendored** at `vendor/supabase-js-2.116.0.js` [the UMD build from npm], loaded at the end of `<body>`. A new release can't reach the live app untested. To upgrade, download the new version under its own file name, change the `<script>` tag, and change `LIBRARY` in `sw.js`.
- **`sw.js` makes the app work offline.** The page is served from cache and refreshed in the background, so a deploy shows up on the open after next. Images and the library are cache-first, and only what someone has viewed is cached. Supabase requests are never cached - the app's own sync queue handles offline edits. Offline with an expired token, the app opens from the session stored on the device. To switch the worker off, deploy a `sw.js` that calls `self.registration.unregister()`.
- A `preconnect` hint in `<head>` opens the Supabase connection while the page loads.

## Run locally

```
node server.js
```

Serves on port 3000, including `/?u=` binder and `/?join=` invite links.

## Accounts

Email and password through Supabase Auth. The username is passed as signup metadata and a trigger on `auth.users` copies it into `profiles`. "Confirm email" must stay off in the Supabase dashboard - the built-in mailer only sends a few emails an hour, so a group signing up together would stall.

## Data

Schema lives in `supabase/migrations/`.

- `profiles` - username and whether the binder is public. Usernames are readable by anyone so binder links resolve. The only column a user can change is `binder_public`.
- `user_sets` - one row per `(user_id, set_id)`: owned, conditions, prices, card_editions, wants, for_trade. Owner-only RLS.
- `groups`, `group_members` - created only through the `create_group` and `join_group` functions.
- Prices are private. Nobody reads another person's `user_sets` directly - `get_binder` and `group_collections` are security definer functions that never select the prices column.
- `collection_sets` is the old single-user table, kept as a frozen backup. The Supabase keepalive workflow still pings it.

The Supabase URL and publishable key are inline in `index.html`. Publishable keys are client-side by design - RLS and the function grants are what protect the data.

### Sync model

One row per set, not one blob for everything. Editing Jungle writes the Jungle row and nothing else, so a failed or half-built write can't take the other sets down with it.

- `rev` and `updated_at` are server-managed by a `before update` trigger, so the client can't forge them.
- `localStorage` keys are namespaced by user [`u:<userId>:<key>`], so two people on one phone never see each other's cards.
- Each device keeps the highest rev it has seen per set under `crystamberRevs_v1`. On load it adopts a cloud row only when `cloud.rev > seen.rev`. Equal rev means this device wrote the current state, so it leaves it alone.
- Because rev also increments on a clear, **deletions propagate**. Emptying a set on one device empties it everywhere.
- Nothing is pushed until the first read resolves. A set edited before that read lands is treated as newer than the cloud and is never overwritten.
- Failed writes stay queued and retry with exponential backoff to 30s. The status dot reports honestly: grey connecting, amber saving, green all saved, red failing with the set names and the error.
- Simultaneous edits on two devices are last-write-wins, which is correct because each row belongs to one person.

## Deploy

Hosted on Vercel as the `crystamber` project. `.vercelignore` keeps `server.js`, `collection.json`, the migrations and the original scans out of the deploy. `.vercel/` is gitignored, so run `vercel link` to reconnect a fresh clone.

`vercel.json` sets the cache headers: `img/` and `vendor/` are immutable for a year, and `sw.js` is `no-cache` so a new worker is picked up on the next visit.
