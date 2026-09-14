# Crystamber

Pokemon card collection tracker for a group of collectors. Each person signs up, marks what they own, records condition, edition and price paid, and flags cards they want or will trade. Groups join through an invite link and get trade matches and a completion board. Anyone can share a read-only binder link.

## Sets covered

Base, Jungle, Fossil, Team Rocket, Gym Heroes, Gym Challenge, Neo Genesis. The card lists are hardcoded in `index.html` - no catalog API.

## Images

The site serves WebP copies from `img/<set>/`, named by zero-padded card number. They are 400px wide [the Gym and Neo sets stay at their native 240px, never upscaled], WebP quality 80. All 686 come to about 18MB, against 298MB for the original scans.

- The original scans stay in the per-set folders [`base/`, `jungle/`, ...] as the source of truth. `.vercelignore` keeps them out of the deploy.
- To regenerate, resize each original to 400px wide with Pillow [LANCZOS] and save as WebP, `quality=80, method=6`, into the matching `img/` folder.
- Vercel serves `img/` with a one-year immutable cache [`vercel.json`]. If an image ever changes, write the new files under a new folder name and repoint `imgPath` - overwriting in place leaves browsers on the old copy for a year.
- A missing image falls back to a numbered placeholder, so deleting the folders never breaks the app.

## Stack

Single static `index.html` - no build step. Supabase for auth and cloud sync. `server.js` is a small local dev server.

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
