---
type: "query"
date: "2026-10-12T09:54:00.859728+00:00"
question: "if device A create an invoice and sync it successfully sometimes device B can't find the invoices or the customer statement"
contributor: "graphify"
outcome: "useful"
source_nodes: ["RealtimeSyncService", "DataSyncService", "ConnectivityService", "InvoiceRepository", "BalanceHistoryRepository"]
---

# Q: if device A create an invoice and sync it successfully sometimes device B can't find the invoices or the customer statement

## Answer

Expanded from original query via graph vocabulary: receipt sequence client statement. Source inspection after traversal found a downloader checkpoint gap in lib/sync/realtime_sync_service.dart. Compatibility bootstrap stores the feed head even when baseline and collection-group queries return incomplete cached data. Receipt import accepts default-source document reads without validating freshness or expected versions, then advances financialChangeSequence; receipts at or below that cursor are skipped. Startup with an existing cursor skips invoice/client baseline downloads. ConnectivityService.forceSync restarts the listener only if stopped and does not reconcile skipped financial records. Three temporary simulated-backend diagnostics passed: incomplete cached baseline leaves sale and statement missing after cursor advancement; cached missing receipt records advance cursor and are skipped on replay; fresh server data imports both correctly. Temporary diagnostics were removed. No production code changed for this diagnosis. This is a reproduced code failure mode, not confirmation of the exact live incident for customers new and new 2. APK parity remains unknown. Remediation needs server-confirmed baseline and receipt reads, validation before checkpoint advance, and catch-up reconciliation for already skipped records.

## Outcome

- Signal: useful

## Source Nodes

- RealtimeSyncService
- DataSyncService
- ConnectivityService
- InvoiceRepository
- BalanceHistoryRepository