# Crystamber

Pokemon card collection tracker. Browse a set, mark what you own, record condition, edition and price paid. Collection state syncs to Supabase so it follows you across devices.

## Sets covered

Base, Jungle, Fossil, Team Rocket, Gym Heroes, Gym Challenge, Neo Genesis.

Card scans live in one folder per set [`base/`, `jungle/`, ...], named by zero-padded card number. The app builds image paths from those folders, so they need to stay in place.

## Stack

Single static `index.html` - no build step. Supabase for cloud sync, `server.js` as a small local dev server that also persists to `collection.json`.

## Run locally

```
node server.js
```

Serves on port 3000 and reads/writes `collection.json`.

## Data

- `collection.json` - local snapshot of owned cards by set, with acquisition dates. Personal data. Only written by `server.js`, so it goes stale unless you run locally.
- `collection-seed.json` - static export of the live collection in the same row shape as `collection_sets`. The hosted page loads this when Supabase is missing or the read fails, then union-merges with anything already in `localStorage`.
- Supabase holds the synced copy in `public.collection_sets`, one row per `(collection_id, set_id)`. If that host is gone, the app stays on the seed and does not retry or flush writes.

The Supabase URL and publishable key are inline in `index.html`. Publishable keys are client-side by design, and RLS scopes `anon` to `collection_id = 'crystamber'` only - select, insert and update, no delete. A write to any other collection id is rejected.

### Sync model

One row per set, not one blob for everything. Editing Jungle writes the Jungle row and nothing else, so a failed or half-built write can't take the other sets down with it.

- `rev` and `updated_at` are server-managed by a `before update` trigger, so the client can't forge them.
- Each device keeps the highest rev it has seen per set in `localStorage` under `crystamberRevs_v1`. On load it adopts a cloud row only when `cloud.rev > seen.rev`. Equal rev means this device wrote the current state, so it leaves it alone.
- Because rev also increments on a clear, **deletions propagate**. Emptying a set on one device empties it everywhere.
- Nothing is pushed until the first read resolves. A set edited before that read lands is treated as newer than the cloud and is never overwritten.
- Failed writes stay queued and retry with exponential backoff to 30s. The status dot reports honestly: grey connecting, amber saving, green all saved, red failing with the set names and the error.
- If the cloud read fails, the app hydrates from `collection-seed.json` once, keeps the local-first union, and does not retry or flush to a dead host. The dot stays green with "Using saved collection".
- Simultaneous edits on two devices are last-write-wins, which is correct for a single user.

## Deploy

Hosted on Vercel as the `crystamber` project. `.vercelignore` keeps `server.js` and `collection.json` out of the deploy. The hosted page still tries Supabase first, then falls back to `collection-seed.json`. `.vercel/` is gitignored, so run `vercel link` to reconnect a fresh clone.
