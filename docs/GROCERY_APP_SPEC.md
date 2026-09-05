# Grocery App — Spec

**Users (v1):** Tommy + wife. Standalone app, not part of home ops.
**Updated:** 2026-08-31

---

## The one hard problem

There is no grocery price API. LLMs don't know prices — ask one and it makes a number up.

So every price feature depends on a data pipeline you build. Where prices can come from:

| Source | What you get | Notes |
|---|---|---|
| **Your receipts** | Real prices, items you buy, stores you shop | The foundation. Build this first. |
| **Kroger API** | Real per-store prices | Free and public. Harris Teeter is Kroger-owned — **test if HT is covered.** |
| **Circular scraping** | Sale items only | Fragile, against ToS, breaks often. Skip for now. |
| **Whole Foods** | Itemized digital receipts in your Amazon account | No API. Copy-paste into the app. |
| Live shelf price, any store | — | Not possible. |

Giant, Safeway, Wegmans, Aldi, Lidl, Trader Joe's, Costco: no public price APIs.
Flipp has no developer API — it sells ad services to retailers.

---

## Features

### Core — all doable

| Feature | Notes |
|---|---|
| Auth | Supabase, magic link |
| Account linking | Build it as a **household**. Everything belongs to a household, users join one. |
| Lists, complete, flag unbought | Unbought items roll to the next list |
| Quantities | Add 2 of something. See below — messier than it looks. |
| Receipt reconciliation | See below. The best feature here. |
| History + quick add | Falls out of receipts free |
| Who added an item | — |
| Autocomplete / dedupe | Not AI. `pg_trgm` for typos, embeddings for synonyms. |
| Estimated total | Useless until ~25 receipts logged. Show "~$140 (12 of 18 priced)". |

### AI / pricing

| Feature | Verdict |
|---|---|
| Best price + where | **Partial.** Only stores you have data for. Last price paid, with package size shown. No per-unit math — see Prices. |
| Store search in range | **Easy.** Google Places. |
| Sale prediction | **Not v1.** Needs 6–12 months of data. It's math, not AI — track weeks between sales per item. Start logging now, ship later. |
| Which store to shop | **Partial.** Count the trip, not just the basket. Saving $6 across two stores is a loss. |
| Store preferences | **Easy.** |
| Price alerts | **Partial.** Good for Kroger stores, gaps everywhere else. |
| Weekly deals (Little Big Meal) | **Split.** Known repeat promos → hardcode as rules. Everything else needs scraping. |
| Recipe import | **Yes, with a catch.** NYT Cooking is paywalled and blocks bots. Paste the text instead — works everywhere. |

---

## Receipt reconciliation

Scan a receipt, it closes out the list, flags what you didn't buy, and logs prices. One action, four jobs.

Why it matters: scanning receipts on its own is a chore that pays off in three months. Nobody keeps that up. Tie it to closing out a trip and it pays off right away.

**It's a proposal you confirm, not an auto-apply:**

- Good match → pre-checked
- Unsure → confirm (`GV HVY WHP CRM` → heavy cream?)
- On list, not on receipt → flag as not bought
- On receipt, not on list → offer to save to history
- Substitution → listed whole milk, bought 2%. Confirm.

Every correction saves an alias, per store. After ~10 receipts a store, review is a glance.

**Watch out for:**
- In-aisle checking still has to work. If your wife is shopping and you're home, receipt-only means the list looks untouched all trip. Receipt closes it out; it doesn't replace live checking.
- One list, two stores = two receipts against one list. Must be additive.
- Filter out tax, bag fees, deposits.
- Quantity mismatches — see Quantities below.

---

## Quantities

One line per item with a count. Never two lines for the same thing.

**Units are the messy part.** "2 chicken thighs" is not "2 lb chicken thighs" is not "2 packs." Store a `default_unit` per item and use it, but let the user override on the line. Most items are just a count — don't make people pick a unit every time.

**Both of you will add the same thing.** You add milk, she adds milk. Don't create two lines and don't silently merge. Prompt: "Katie already added milk — make it 2?" Cheap to build, and it's the most likely daily annoyance in a two-person app.

**Partial buys need a third state.** Listed 3, bought 2. Not done, not skipped. Store what was wanted and what was bought separately:

- `qty` — what you asked for
- `qty_purchased` — what came home
- status becomes `partial` when they differ and neither is zero

The leftover rolls to the next list, same as an unbought item.

**Reconciliation has to handle mismatches.** Receipt says 3, list says 2. Trust the receipt for what you paid and log the price against the real count, but flag the line so the list stays honest.

**Totals are `qty × unit_price`.** Obvious, but the estimate is wrong without it, and a wrong estimate is worse than none.

**Recipes stack.** Two recipes both want onions — merge into one line, keep both sources in the metadata so you can see why the number is 4.

---

## Prices — how far this goes

**Decision: last price paid per store. No per-unit math.**

Good call for v1. But there's a trap, and it needs one cheap fix.

"$5.99 at Giant vs $3.49 at Aldi" may be a 1.4 lb package against a 1 lb package. That's not a rough comparison — it's a wrong one, and the app would be stating it confidently.

**Fix: store the package size as text and show it. Never compute with it.**

> Giant · $5.99 (1.4 lb) · Aug 30
> Aldi · $3.49 (1 lb) · Aug 12

You do the math in your head. Costs nothing to build, and the app stops lying.

Two rules that follow:

- **Always show the date.** A price from March isn't a price. Gray it out past 60 days.
- **Don't say "cheaper at X"** unless package sizes match exactly. Show both, let the human decide. Save the confident version for when per-unit lands.

---

## Aisle order

**Decision: sort the list by how you walk the store.**

Order lives per store — Giant's layout isn't Aldi's.

**Where the order comes from:**

1. Ship a sensible default (produce → bakery → deli → meat → dairy → frozen → pantry → household). Works okay everywhere, zero setup.
2. Let them drag categories to fix it per store. One-time, five minutes, then it's right forever.

Don't try to learn layout from receipts. Receipts print in scan order, which only loosely tracks how you walk. Clever, unreliable, not worth it.

**Categories:**

- Fixed list of ~14. Not free-form — free-form fragments into "Veg" and "Produce" and "Vegetables" within a month.
- The LLM assigns a category when an item is first created. One cheap call. User can correct it, and the correction sticks.
- A list needs a store selected to sort. No store picked → default order.
- Two stores in one trip → the list sorts by whichever store you're standing in. Store picker at the top of the list.

---

## Brands

**Decision: generic only. "Milk" is "milk."**

Simplifies the item model — no brand table, `items` stays flat.

Two known costs, both acceptable:

- Receipt lines are branded (`GV HVY WHP CRM`). Matching still has to collapse them to generic. `item_aliases` already handles this.
- Prices will look noisy. Organic and conventional milk are both "milk," so "last paid" bounces around. Live with it, or add an optional note on the line.

---

## Loose ends

Not forks — just decisions that need making before code gets written. Defaults suggested.

| Gap | Default |
|---|---|
| Recurring staples | A "usual" template you can dump onto a new list. Otherwise you retype 15 items weekly. |
| Receipt parse fails | Always show a manual-entry fallback and a retry. Bad photos will happen. Never a dead end. |
| Empty items table | Seed ~300 common groceries with categories. Otherwise month one has no autocomplete and typing everything gets old fast. |
| Invite flow | You create both accounts. Two users, no reason to build invites. |
| Alerts | Email first. Web push needs the PWA installed to the home screen on iOS — extra setup, save it. |
| Offline conflicts | Last write wins on a checkbox. Say it out loud so it isn't a surprise. |
| First-run | The app is genuinely thin for a month while data builds. Say so on screen or it reads as broken. |

**For Claude Code specifically,** add before you hand it over: migration strategy, env var list, and 3–4 sample receipt images as fixtures. Otherwise it invents conventions you'll want to undo.

---

## Stack

```
Next.js PWA (React, TS, Tailwind)
        ↓
Vercel — route handlers, cron
        ↓                    ↓
Supabase                External APIs
  Postgres (RLS,          Claude — receipt parsing
    pgvector, pg_trgm)    Voyage — embeddings
  Auth                    Kroger — HT prices
  Storage                 Google Places — stores
  Realtime
```

**Why:**
- **RLS** scopes every query to your household automatically. No permission code to forget.
- **Realtime** syncs the list between two phones live. That's what makes in-aisle checking work.
- **pgvector + pg_trgm** are Postgres extensions. No separate vector database.

**Traps:**
- Anthropic has no embeddings endpoint. Use Voyage.
- Validate every LLM response with Zod before it hits the database.
- Receipt parsing takes 10–20s. Too long for a request handler, but don't build a queue yet — show a progress state. Add a jobs table + cron when you're doing batches.
- Camera is just `<input type="file" accept="image/*" capture="environment">`. No library.
- Compress images client-side before upload. Receipts are tall and skinny — downscaling cuts tokens and upload time for free.

**Rule: no model output ever becomes a displayed price.** Prices come from the database or an API, always with a source and date. The model reads and matches. It never guesses.

---

## Cost

**Your Claude subscription doesn't cover API calls.** You need a separate Console account, pay as you go, no minimum.

Receipt parsing on Haiku: about **$0.008 a receipt**. Ten a month is under a dime.
Vercel and Supabase free tiers cover two users.

**All in: $0–5/month.** Set a spend cap anyway — a runaway loop is the only real risk.

---

## Build order

| Phase | What |
|---|---|
| **v0.5** | Receipt logger. Auth, household, scan, review, save. No lists. Ship this first — everything else needs months of data, and the clock starts here. |
| **v1** | Lists, in-aisle checking, attribution, autocomplete, history, reconciliation, totals from your own data. No external APIs. |
| **v1.5** | Kroger/Harris Teeter prices, store locations, watchlist, price alerts. |
| **v2** | Recipes. Paste, parse, add to list. |
| **v3** | Sale prediction, store recommendation. Needs a year of history. |

---

## Schema

```
households          id, name
users               id, household_id, email, display_name
stores              id, chain, name, address, lat, lng, external_ids
household_stores    household_id, store_id, rank, enabled

items               id, canonical_name, category_id, default_unit, embedding
item_aliases        item_id, store_id, alias, source

categories          id, name, default_sort
store_categories    store_id, category_id, sort_order

lists               id, household_id, name, status, created_by, completed_at
list_items          id, list_id, item_id, qty, qty_purchased, unit,
                    added_by, status, checked_at, checked_by,
                    source_type, source_ref
                    status: pending | purchased | partial | unavailable | skipped

receipts            id, household_id, store_id, purchased_at, total,
                    image_url, raw_text, parse_status, reconciled_list_id
receipt_lines       id, receipt_id, item_id, raw_text, qty, unit_price,
                    total, match_confidence, matched_list_item_id

price_observations  id, item_id, store_id, price, unit, package_size,
                    observed_at, source, is_sale
                    source: receipt | kroger_api | circular | manual
                    package_size is display text only — never computed with

watchlist           household_id, item_id, target_price, notify
recipes             id, household_id, title, source_url, raw_text, parsed
```

- `price_observations` is the spine. Every price lands here with where it came from and when.
- `item_aliases` per store is what makes matching improve over time.
- RLS on `household_id` everywhere.

---

## Scaling ideas (pie in the sky)

Parked, not planned.

**Crowdsourced receipts at scale = a real price dataset.** Big advantage: it's the user's own data, given freely. Much safer than scraping, which gets you cease-and-desists and breaks on every redesign.

**The model already exists.** Fetch Rewards, Ibotta, and Numerator all do receipts in, purchase data out, sold to brands. Billion-dollar companies. So "we collect receipts" can't be the pitch.

**The angle that could work:** those are all rewards apps. Scanning is a chore users put up with for points, and their list features are an afterthought. Here the scan is useful on its own because it closes your list. Better reason to sign up, better reason to stay.

**Go deep, not wide.** There are 40,000+ US grocery stores. Ten thousand users spread nationally is a few receipts per store — worthless. The same ten thousand in one metro gives you live pricing for every store in it. Own DC first.

**Discounts for uploaders — two flags:**
- Fraud. Fake receipt generators already exist. Money for receipts means running fraud checks forever.
- Backwards revenue. Your best contributors pay you least. Points may beat discounts.

**Partnerships:**
- Instacart's platform is partner-gated, not self-serve.
- Retailers mostly don't want price comparison. Discounters might. Premium chains won't.
- Brands buy this data, not stores. That's who Fetch sells to.

**Also worth keeping in mind:** staying a two-person private tool is a fine ending. Worth naming so growth is a choice, not a drift.

---

## Open questions

1. What stores besides Whole Foods? Decides how much Kroger can cover.
2. Mobile: this gets used in an aisle. Offline list access is a day-one decision, not a retrofit.
3. Do your other stores email receipts if you ask? Every digital receipt is one less photo to read.
4. Portfolio piece or private tool?

---

## Next step

Register at `developer.kroger.com`. Run two calls: Locations for 22302, then a product price against whichever Harris Teeter comes back.

One afternoon. It decides whether you get real prices or only your own receipts.
