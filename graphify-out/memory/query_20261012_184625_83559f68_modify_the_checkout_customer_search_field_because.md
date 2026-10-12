---
type: "query"
date: "2026-10-12T18:46:25.848113+00:00"
question: "Modify the checkout customer search field because typing a customer name prevents scrolling through other matching customers."
contributor: "graphify"
outcome: "useful"
source_nodes: ["invoice_checkout_sheet.dart", "checkoutClient"]
---

# Q: Modify the checkout customer search field because typing a customer name prevents scrolling through other matching customers.

## Answer

Expanded graph vocabulary: client checkout search options scroll. Verified native Autocomplete already has a bounded scrollable options list. Root cause was the checkout post-frame balance loader: a partial name that is not an exact customer sets checkoutClientNotFound=true and balance=null, then the next build automatically reloads it again, repeating setState and rebuilding the dropdown so scrolling is disrupted. Added the missing !checkoutClientNotFound guard to prevent automatic retries of a failed exact-name lookup. New typing and selection still reset the flag and explicitly load the new customer normally. The first phone-sized widget test with40 matching customers and a visible300px keyboard failed to settle under the old repeated-lookup behavior; after the guard it settled, verified options fully within the visible area, scrolled to customer29, selected the correct name and balance42, and continued with that selected customer. Native dropdown geometry and scroll behavior were retained because they passed the mobile/keyboard check after the lookup loop stopped. All8 checkout regression tests pass. Targeted analysis has no errors/warnings,9 preexisting style/async-context infos. No APK build performed per user preference.

## Outcome

- Signal: useful

## Source Nodes

- invoice_checkout_sheet.dart
- checkoutClient