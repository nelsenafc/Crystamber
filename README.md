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

- `collection.json` - local snapshot of owned cards by set, with acquisition dates. Personal data.
- Supabase holds the synced copy, keyed by collection id.

The Supabase URL and publishable key are inline in `index.html`. Publishable keys are client-side by design, so this is safe as long as row-level security stays on for the collections table.

## Deploy

Hosted on Vercel as the `crystamber` project. `.vercelignore` keeps `server.js` and `collection.json` out of the deploy - the hosted build reads from Supabase instead. `.vercel/` is gitignored, so run `vercel link` to reconnect a fresh clone.
