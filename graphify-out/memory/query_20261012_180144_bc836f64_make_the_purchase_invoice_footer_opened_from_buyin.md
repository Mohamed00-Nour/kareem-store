---
type: "query"
date: "2026-10-12T18:01:44.887671+00:00"
question: "Make the purchase invoice footer opened from BuyingInvoiceListPage match the purchase invoice footer on the supplier page."
contributor: "graphify"
outcome: "useful"
source_nodes: ["BuyingInvoiceDetailPage", "SupplierInvoicesPage", "InvoiceTotalsFooter"]
---

# Q: Make the purchase invoice footer opened from BuyingInvoiceListPage match the purchase invoice footer on the supplier page.

## Answer

Expanded graph vocabulary: buying invoice footer supplier balance. Verified current BuyingInvoiceListPage navigation goes to BuyingInvoiceDetailPage. Detail previously injected currentSupplierBalance, whereas SupplierInvoicesPage computed chronological previous/remaining fields and used a different final label. Extracted the existing supplier chronological calculation into SupplierInvoiceRunningBalanceService.apply and reused it on SupplierInvoicesPage. Added buildPayload using canonical cached purchase invoices, returns and standalone supplier history, with ID/name lookup and latest cached invoice selection. BuyingInvoiceDetailPage now renders that payload instead of current supplier total. Both views render shared InvoiceTotalsFooter with remainingLabel set to المتبقي عليكم, giving identical rows, responsive styles and balances. Other footer callers retain their existing default label. Added regression cases for opening balance40, payments between/after purchases, editing an earlier purchase, equal display numbers, stale/name-only navigation data, returns and signed vouchers. All186 regression tests pass. Targeted analysis has no errors or warnings;25 preexisting style/deprecation infos. Display calculation only; no balance ledger or cloud financial write changes.

## Outcome

- Signal: useful

## Source Nodes

- BuyingInvoiceDetailPage
- SupplierInvoicesPage
- InvoiceTotalsFooter