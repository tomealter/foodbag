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
