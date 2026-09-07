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