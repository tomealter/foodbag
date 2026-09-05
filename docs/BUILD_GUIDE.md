# Foodbag — Build Guide

Step-by-step path to v0.5 (receipt logger), then a sketch of v1.

**Tuned for:** you know React/Next.js and TypeScript. Postgres, RLS, and migrations are the new material — that's where the detail is. Sessions are sized for 1–2 hours and each ends with something committed and working.

**Rules of engagement:** you write the code. Claude explains, reviews, and writes only migrations/seeds/config/boilerplate unless you delegate. See [CLAUDE.md](../CLAUDE.md).

---

## Session 0 — Kroger API spike

**No code in the repo.** This is a decision, not a feature.

1. Register at `developer.kroger.com`. Create an app, get a client ID and secret.
2. Get an OAuth token (client credentials grant).
3. `GET /v1/locations?filter.zipCode.near=22302` — see what comes back.
4. Find a Harris Teeter in the results. Grab its `locationId`.
5. `GET /v1/products?filter.term=milk&filter.locationId=<id>` — check whether `items[].price` is populated.

**Done when:** you can answer "does Harris Teeter return real prices through the Kroger API, yes or no?"

Write the answer in `docs/DECISIONS.md`. If yes, v1.5 is real. If no, this app runs entirely on your own receipts and you should know that now.

> Do this whenever. It doesn't block anything below.

---

# v0.5 — Receipt Logger

Auth, household, scan a receipt, confirm what it says, save prices. **No lists.** Ship it, then scan receipts weekly while you build v1. The data clock starts the day this works.

---

## Session 1 — Repo and scaffold

**Learning goal:** none. Get the boring part over with.

1. `git init`. Commit the spec and CLAUDE.md that already exist.
2. `npx create-next-app@latest` — TypeScript, Tailwind, App Router, no `src/` unless you like it.
3. Delete the boilerplate homepage. Replace with a heading. Confirm `npm run dev` serves it.
4. Create `.env.example` (empty for now) and confirm `.env.local` is gitignored.
5. Commit.

**Done when:** localhost:3000 shows your own text.

---

## Session 2 — Supabase running locally

**Learning goal:** what Supabase actually *is* — it's Postgres plus services, not a database product.

1. Install Docker Desktop if you don't have it.
2. `npm i supabase --save-dev`, then `npx supabase init`. Look at what it wrote to `supabase/`.
3. `npx supabase start`. It'll print URLs and keys. This takes a few minutes the first time.
4. Open Studio (the URL it printed, usually `:54323`). Poke around. Find the `auth.users` table.
5. Put the local URL and anon key in `.env.local`, and the *names* of those vars in `.env.example`.
6. Install `@supabase/supabase-js` and `@supabase/ssr`. Don't wire anything up yet.

**Ask Claude:** what's the difference between the anon key and the service role key, and why does it matter which one reaches the browser?

**Done when:** `npx supabase status` shows everything running and Studio opens.

---

## Session 3 — First migration: households and profiles

**Learning goal:** migrations as forward-only history. This is the session that shapes every one after it.

**The modeling problem you'll hit immediately:** the spec lists a `users` table with `household_id`. But Supabase owns `auth.users` and you can't add columns to it. The convention is a separate `profiles` table with `id` referencing `auth.users(id)`. Understand *why* before you write it.

1. `npx supabase migration new create_households_and_profiles`.
2. Write the SQL. Two tables:
   - `households` — `id uuid primary key default gen_random_uuid()`, `name text not null`, `created_at timestamptz default now()`
   - `profiles` — `id uuid primary key references auth.users(id) on delete cascade`, `household_id uuid references households(id)`, `email text`, `display_name text`
3. `npx supabase db reset` — this replays every migration from scratch against a fresh database. Get used to this command; it's your undo button while nothing's in production.
4. Verify in Studio.
5. Commit.

**Concepts to have Claude explain, not just use:**
- Why `uuid` instead of an auto-incrementing integer here
- What `on delete cascade` does and when it will bite you
- Why migrations are forward-only, and what "never edit an applied migration" protects you from

**Done when:** `db reset` runs clean and both tables exist.

---

## Session 4 — Row Level Security

**Learning goal:** the highest-value hour in this whole project. RLS is why this app needs almost no permission code.

The idea: a policy is a `WHERE` clause Postgres bolts onto every query automatically, based on who's asking. Get it right once and no route handler can ever leak another household's data — even if you write the query wrong.

1. Enable RLS on both tables. **Note what happens: all queries now return zero rows.** Deny-by-default. That's correct and it's the point.
2. Write a helper — a SQL function `current_household_id()` that returns the household of the currently authenticated user. Every policy will call it.
3. Policy on `profiles`: a user can read profiles in their own household.
4. Policy on `households`: a user can read their own household.
5. Test it properly — create two households and two users in SQL, then query as each one and confirm neither sees the other's rows.

**Ask Claude to explain:** `auth.uid()`, the difference between `USING` and `WITH CHECK`, and why a `SECURITY DEFINER` function is needed for the household lookup (there's a recursion trap here — hit it, then understand the fix).

**Done when:** you have proof — not a vibe — that user A cannot read household B's rows.

> This is the single most important session in v0.5. Don't rush it into a night where you're tired. Everything after this assumes RLS works.

---

## Session 5 — Auth: magic link

**Learning goal:** how a session survives between server components, client components, and route handlers.

1. Set up the Supabase browser client and server client (`@supabase/ssr` — read its docs, the pattern matters).
2. Add middleware to refresh the session cookie.
3. Build a login page: email input → `signInWithOtp`.
4. Local Supabase catches outgoing mail — find Inbucket (usually `:54324`) and click the link from there.
5. Add a protected page that redirects to login when there's no session.
6. Add sign out.

**Ask Claude:** why the session lives in a cookie rather than localStorage, and what the middleware is actually refreshing.

**Done when:** you can log in, see your email on a protected page, and log out.

---

## Session 6 — Bootstrapping a household

**Learning goal:** database triggers — logic that lives in Postgres instead of your app.

A new `auth.users` row needs a matching `profiles` row. You could do it in application code after signup. Don't — it fails silently when signup happens any other way.

1. Write a trigger function on `auth.users` insert that creates the `profiles` row.
2. New migration, `db reset`, sign up a fresh user, confirm the profile appeared.
3. Create your household and your wife's account manually in SQL. Point both profiles at the same `household_id`. (Per the spec: no invite flow. Two users, done by hand.)

**Done when:** both accounts exist, share a household, and each can log in.

**Commit `docs/DECISIONS.md` now** if you haven't. One line per non-obvious choice, with the date and why. Start with the `profiles` vs `users` decision and the trigger.

---

## Session 7 — Categories and items

**Learning goal:** seed data, and indexes that make text search work.

1. Migration: `categories` (id, name, default_sort) and `items` (id, canonical_name, category_id, default_unit). Hold off on `embedding` — pgvector isn't needed until v1 autocomplete.
2. Seed the ~14 fixed categories in the correct default walk order: produce → bakery → deli → meat → dairy → frozen → pantry → household → etc.
3. Seed ~300 common groceries with categories. **Delegate this to Claude** — it's typing, not learning.
4. Enable `pg_trgm` and add a trigram index on `items.canonical_name`.
5. In Studio, run a fuzzy query — `similarity()` or `%` — against a deliberate typo. Watch it match.

**Ask Claude:** what a trigram actually is, and why this index makes typo matching fast instead of a full scan.

**Note:** `items` is household-agnostic — a shared vocabulary. Decide whether it gets RLS at all, and write down why.

**Done when:** typing "chedar" finds cheddar in a SQL query.

---

## Session 8 — Stores and the receipt schema

**Learning goal:** modeling a parent/child relationship and thinking about it before writing code.

1. Migration: `stores` (id, chain, name, address, lat, lng, external_ids jsonb).
2. Migration: `receipts` and `receipt_lines` per the spec's schema. `receipts.parse_status` should be a real enum or a checked text column, not free text.
3. Migration: `price_observations`. Re-read the spec's rule — `package_size` is display text only, never computed with. Consider a comment in the SQL saying so.
4. RLS on all three. `receipt_lines` has no `household_id` of its own — its policy has to reach through `receipts`. Work out how.
5. Insert your two or three real stores by hand.

**Ask Claude:** whether `receipt_lines` should carry a denormalized `household_id` for simpler and faster policies. There's a real tradeoff — make the call and log it in DECISIONS.

**Done when:** you can insert a receipt with lines in Studio and RLS still holds.

---

## Session 9 — Get a photo into storage

**Learning goal:** file upload, client-side image compression, and Supabase Storage policies.

1. Create a `receipts` storage bucket. Private, not public.
2. Storage RLS policies — path-scoped by household.
3. UI: `<input type="file" accept="image/*" capture="environment">`. No library. On a phone this opens the camera.
4. Compress client-side before upload — canvas resize, cap the long edge around 1600px. Receipts are tall and skinny; this cuts tokens and upload time for free.
5. Upload, create a `receipts` row with `parse_status = 'pending'`, show the image back.

**Do this session on your actual phone**, not the desktop browser. Use your local network IP. Camera behavior is the whole point.

**Collect your fixtures now:** photograph 3–4 real receipts from different stores. Save them in `fixtures/`. The spec calls these out and you'll need them constantly in Session 10.

**Done when:** you can photograph a receipt on your phone and see it stored.

---

## Session 10 — Parsing with Claude

**Learning goal:** structured LLM output, and never trusting it.

1. Console account at `console.anthropic.com`, API key, **set a spend cap**. This is separate from your Claude subscription.
2. Define the Zod schema for a parsed receipt first — store, date, total, and lines of `{raw_text, qty, unit_price, total}`. Schema before prompt.
3. Route handler: read the image from storage, send to Claude Haiku with the schema described in the prompt.
4. **Parse the response through Zod before it touches the database.** Non-negotiable. Handle the failure path — a bad parse writes `parse_status = 'failed'`, never a partial write.
5. Save the lines. Filter out tax, bag fees, and deposits.
6. Progress state in the UI — this takes 10–20 seconds. Don't build a job queue; the spec is explicit that it's too early.
7. Run all your fixtures through it. Tune the prompt against real failures, not imagined ones.

**Ask Claude:** how to structure the prompt for reliable extraction, and where to put the retry when Zod rejects the response.

**Done when:** a real photographed receipt becomes rows in `receipt_lines`.

---

## Session 11 — The review screen

**Learning goal:** none technically new. This is the product session — the one that decides whether the app is usable.

Show the parsed lines next to the photo. Every line editable. Nothing saves until you confirm.

- Confident matches pre-filled
- Uncertain ones visibly uncertain (`GV HVY WHP CRM` → heavy cream?)
- **A manual-entry fallback and a retry, always.** Bad photos will happen. Never a dead end.
- Store picker and date, both editable

**Done when:** you can correct a bad parse without touching the database by hand.

---

## Session 12 — Matching and aliases

**Learning goal:** where the app starts getting smarter over time. This is the mechanism that makes the whole thing work.

1. For each receipt line, look for an existing `item_aliases` row for that store and raw text. Exact hit → done, no guessing.
2. No alias → trigram match against `items.canonical_name`. Above a threshold, propose it. Below, ask.
3. **Every confirmation writes an alias**, scoped to that store. This is the entire trick: after ~10 receipts per store, review becomes a glance.
4. Unmatched line → offer to create a new `item`. Have Claude assign the category on creation — one cheap call, user can correct it, correction sticks.
5. On confirm, write a `price_observations` row per line: price, package size as text, `observed_at`, `source = 'receipt'`.

**Done when:** scanning a second receipt from the same store needs noticeably less correcting than the first.

---

## Session 13 — History, and ship it

1. A receipts list — date, store, total, thumbnail.
2. An item detail view: last price paid per store, **with the date, grayed past 60 days**. Never the words "cheaper at."
3. Deploy to Vercel. Create the hosted Supabase project, push migrations with `npx supabase db push`, set env vars.
4. Add to your home screen on both phones.

**v0.5 done.** Now scan every receipt, every week, without exception. The rest of the app is worth nothing without this data, and there's no shortcut that backfills it.

---

# v1 — Lists

Only start once receipts are a habit. Rough order:

1. `lists` and `list_items` schema + RLS
2. Add, check off, delete — the plain version first
3. Supabase Realtime so two phones stay in sync live (this is what makes in-aisle checking work)
4. Autocomplete off `items` via trigram; embeddings for synonyms only if trigram proves insufficient
5. Quantities, and the duplicate-add prompt — "Katie already added milk — make it 2?"
6. Attribution — who added what
7. Aisle sort per store, with drag-to-reorder categories
8. **Reconciliation** — connect a receipt to an open list. The hard one, and the reason the app exists. Save it for last.
9. Estimated total, once you have ~25 receipts. Show it as "~$140 (12 of 18 priced)".

---

## Working notes

- **One session, one commit minimum.** If a night ends with nothing committed, the step was too big — say so and split it.
- **`db reset` is free right now.** Break the schema deliberately while that's still true.
- **Write it wrong first, then get it reviewed.** Reading a correct answer teaches less than having your version pulled apart.
- **Log decisions the same day you make them.** In three weeks you won't remember why, and DECISIONS.md is the artifact that turns this into a portfolio piece if you ever want one.
- **Don't build ahead.** The build order exists because the data has to accumulate in real time.
