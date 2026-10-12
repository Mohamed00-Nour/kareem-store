---
type: "query"
date: "2026-10-12T08:13:52.479527+00:00"
question: "Why does editing a buying invoice cause a cloud-conflict and block later synchronization on multiple devices?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["BuyingInvoiceUpdateService", "SupplierOperationService", "FinancialCloudUploader", "BatchSyncEngine"]
---

# Q: Why does editing a buying invoice cause a cloud-conflict and block later synchronization on multiple devices?

## Answer

Confirmed by two isolated in-memory Flutter diagnostics: mergeCloudBuying records cloudOperation only for the canonical buying invoices document. SupplierOperationService.cloud independently requires expectedOperationId for the suppliers/{supplierId}/buying invoices/{invoiceId} copy, whose local metadata may be absent or stale on a second device. A current downloaded invoice edit fails with Concurrent change to the supplier copy even without any external edit; recording matching copy metadata lets the identical edit upload successfully with correct supplier balance, stock and cash. The reported invoice 1070 error names the supplier copy, matching this failure. BatchSyncEngine blocks subsequent shared-resource operations, including shared cash-box writes; cloud-conflicts do not automatically retry. This was diagnosis only; no production fix was applied.

## Outcome

- Signal: useful

## Source Nodes

- BuyingInvoiceUpdateService
- SupplierOperationService
- FinancialCloudUploader
- BatchSyncEngine