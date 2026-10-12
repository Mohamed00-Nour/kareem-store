---
type: "query"
date: "2026-10-12T18:15:55.220583+00:00"
question: "BuyingInvoiceListPage does not refresh until the app restarts; make it stream."
contributor: "graphify"
outcome: "useful"
source_nodes: ["BuyingInvoiceListPage", "InvoiceRepository"]
---

# Q: BuyingInvoiceListPage does not refresh until the app restarts; make it stream.

## Answer

Expanded graph vocabulary: buying invoice list stream watch. Verified current BuyingInvoiceListPage only loaded cache at initialization and after its startup/manual delta sync. Added a buyingInvoicesBox.watch subscription before initial cache load; each local operation or verified cloud import reloads the cached list and reapplies current search, month filter and sorting. Subscription is cancelled in dispose. Delete confirmation now captures the invoice map and its stable ID instead of a list index; a live insert cannot shift deletion onto a different invoice. Removed temporary list-only deletion and index-based rollback; Hive updates drive the display and failures reload the authoritative cache. Added three widget regression tests for live local creation and cloud creation/edit/tombstone, active search and month filters, disposal, and insertion while a delete confirmation is open. First two tests reproduced stale UI before the fix. All three final widget tests pass, including durable delete completion and success notification. Targeted analysis passed without errors/warnings, with19 preexisting style/deprecation infos. No APK build performed, following the user preference to skip builds.

## Outcome

- Signal: useful

## Source Nodes

- BuyingInvoiceListPage
- InvoiceRepository