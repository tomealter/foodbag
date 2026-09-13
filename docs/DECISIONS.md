# Decisions

One entry per non-obvious choice. Date it, say why.

---

## 2026-09-05 — Kroger API returns real Harris Teeter prices

Spike: hit `/v1/products?filter.term=milk&filter.locationId=09700413` (Harris Teeter,
King St - Beauregard, Alexandria) via client credentials OAuth.

**Answer: yes.** `items[].price.regular` is populated with real numbers, and
`promo` shows active sale prices. Each item also has `effectiveDate` and `size`.

v1.5 (Kroger prices) is real — build it when we get there.

Note: Harris Teeter's chain code in the API is `HART`, not "Harris Teeter" —
`filter.chain` needs the internal code, not the storefront name.

---

## 2026-09-05 — CSS Modules instead of Tailwind

Spec/CLAUDE.md originally called for Tailwind. Switched to CSS Modules for the
styling approach — no utility-class build step, styles are scoped per component
via `*.module.css`, and it's built into Next.js with zero config.

## 2026-09-06 — profiles table instead of extending auth.users

Supabase own the auth.users - we can't add columns to it. Decision was made to create a profiles table which is a sidebar table: same as auth.users (FK with delete on cascade), holds
household_id/email/display_name instead.

---

## 2026-09-12 — get_household_id() must be SECURITY DEFINER

The `profiles` RLS policy needs to know the caller's household to filter rows.
Naive approach: have the policy query `profiles` directly to look up
`household_id` for `auth.uid()`. Problem: that lookup is itself a query against
`profiles`, so it triggers the same RLS policy again — infinite recursion.

Fix: pull the lookup into a `SECURITY DEFINER` function. It runs with the
function owner's privileges instead of the caller's, so it bypasses RLS on
`profiles` internally and just reads the row — no re-trigger, no recursion.

Paired with `set search_path = ''` — required any time a function is
`SECURITY DEFINER`, so an unqualified table name inside it can't be hijacked by
a caller who has a table of the same name earlier in their own search path.
Every reference inside the function is fully schema-qualified (`public.profiles`)
because of this.

---

## 2026-09-12 — RLS policies are select-only for now

`households` and `profiles` only have `for select` policies. No `insert`/
`update`/`delete` policies exist yet, which means the `authenticated` role
can't currently create or modify rows in either table (RLS is deny-by-default
per operation type).

This is deliberate, not an oversight — v0.5 hasn't built any write paths yet
(household creation, profile edits). Add write policies when that lands.