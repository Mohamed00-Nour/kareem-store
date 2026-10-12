---
type: "query"
date: "2026-10-12T19:42:09.969113+00:00"
question: "when deleting a sales invoice then delete it's المدفوع from the PaymentsReportPage"
contributor: "graphify"
outcome: "useful"
source_nodes: ["CustomerOperationService", "PaymentBreakdownRepository", "LocalOperationJournal", "BatchSyncEngine", "RealtimeSyncService", "PaymentsReportPage"]
---

# Q: when deleting a sales invoice then delete it's المدفوع from the PaymentsReportPage

## Answer

Expanded graph vocabulary: sales invoice payment breakdown delete. Verified shared CustomerOperationService.deleteInvoice deleted invoice/history and reversed stock/cash but left payment_breakdowns records. Added canonical invoice_<id> and every locally linked payment ID to the same journal local deletes and atomic financial cloud tombstone transaction. Added typed payment box journal support, sequenced receipt import and post-upload refresh for payment_breakdowns, with pending-path guards and per-record queue dependencies. Payment repository imports now honor version/tombstone guards, and report views exclude known deleted invoice links to cover older or unknown legacy document IDs without deleting independent/unlinked records. Older pending payment upserts now transactionally check the linked sales/return invoice and preserve confirmed deletion; missing not-yet-uploaded parent invoices keep payments retryable rather than discarding them. No extra financial balance/cash adjustment is made for distribution cleanup. Regression reproduced orphan records before fix. New tests cover offline deletion, matching invoice display numbers with different IDs, alias payment IDs, restart/lost acknowledgement idempotence, late stale uploads, missing parent then successful retry, cross-device removal/stale snapshot rejection and live report totals. Full suite200 tests passes. Analysis has no errors;2 preexisting unused-local warnings in legacy batch handlers plus style infos. No APK build per user preference. Unrelated release CXX fingerprint changes observed during session were left untouched.

## Outcome

- Signal: useful

## Source Nodes

- CustomerOperationService
- PaymentBreakdownRepository
- LocalOperationJournal
- BatchSyncEngine
- RealtimeSyncService
- PaymentsReportPage