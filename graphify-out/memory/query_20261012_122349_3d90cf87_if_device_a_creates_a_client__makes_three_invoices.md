---
type: "query"
date: "2026-10-12T12:23:49.487290+00:00"
question: "If device A creates a client, makes three invoices and edits one invoice, what happens on devices A and B? Test it and summarize."
contributor: "graphify"
outcome: "useful"
source_nodes: ["CustomerOperationService", "CustomerBalanceStore", "InvoiceFooterData", "RealtimeSyncService", "BatchSyncEngine", "FinancialCloudUploader"]
---

# Q: If device A creates a client, makes three invoices and edits one invoice, what happens on devices A and B? Test it and summarize.

## Answer

Expanded from graph vocabulary: customer invoice balance statement receipt sync. Verified current production CustomerOperationService, FinancialCloudUploader, BatchSyncEngine and RealtimeSyncService using independent persisted Hive caches A and B and an in-memory Firestore test double. Added seven regression cases in test/realtime_sync_service_test.dart: both online with incremental catch-up, B offline until after edit, A queues all five operations offline with warm B, same with clean B, B interrupted during edit then restarted, concurrent edits to different invoices, and competing edits to the same invoice. Zero opening balance; invoices 220/paid0, 300/paid100, 150/paid50 produce balances 220,420,520. Edit invoice 2 to total350/paid120 adds only30, giving550; cash170. Normal scenarios converge to exactly one customer and three invoices, identical statement rows and footers, no duplication after repeat refresh or full repair. Final invoice footers previous0,220,450 and owed220,450,550. Different invoice B edit invoice3 to180/paid60 converges both devices to570 with cash180. Same invoice B conflicting edit is retained locally and classified conflict; cloud keeps A invoice350/paid120, balance550, cash170 and receipt sequence5 unchanged. All seven cases pass; full regression184 tests pass. Automated simulation, not a new physical two-phone test. Only test code added; existing APK production code unchanged.

## Outcome

- Signal: useful

## Source Nodes

- CustomerOperationService
- CustomerBalanceStore
- InvoiceFooterData
- RealtimeSyncService
- BatchSyncEngine
- FinancialCloudUploader