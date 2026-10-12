---
type: "query"
date: "2026-10-12T11:50:48.423868+00:00"
question: "device A invoice 220 has previous balance 0 and owed 220, but device B shows previous -220 and owed 0"
contributor: "graphify"
outcome: "useful"
source_nodes: ["RealtimeSyncService", "CustomerBalanceStore", "SupplierBalanceStore", "CloudSnapshotGuard", "InvoiceFooterData"]
---

# Q: device A invoice 220 has previous balance 0 and owed 220, but device B shows previous -220 and owed 0

## Answer

Expanded from graph vocabulary: balance event running footer. Read-only copied cache from connected device B confirmed the exact failure: downloaded cloud balance 220, accepted and mirrored customer balance 0, zero financial events, missing baseline/checkpoint, and a saved Firestore unavailable error. The baseline fetched large product/invoice collections before importing events and could leave party profiles visible at opening balances. Implemented balance-first party hydration with complete server events, financialVersion completeness checks, receipt-event prefetch and party-before-invoice imports. Added resumable financialBaselineProgress retaining the original server head and completed steps; upgraded baseline version to 2. Collection-group permission/index failures fall back to authorized per-party server queries. Dedicated financialDownloadError survives unrelated background sync and dashboard shows/downloads detailed failure instead of a false all-synchronized status. Installed the first corrected build over device B data and verified copied live state: accepted and mirror 220, previous 0, total 220, paid 0, owed 220, two events. That verification also found a historical Timestamp serialization blocker; customer/supplier vouchers now recursively convert timestamps and CloudSnapshotGuard excludes non-string legacy operation tags, retaining financial-state guards. Full suite 177 passes; analysis no errors or warnings, 16 existing style infos; APK build successful. Final build installed over existing app data on device B. Read-only copied final state verified baseline version 2, receipt sequence 132, no pending baseline, no financial download error, and 2352 persisted history rows. Customer accepted/mirrored balance 220; invoice previous 0, total 220, paid 0 and owed 220. Device A should receive the same updated APK. No app data cleared and no cloud financial records changed by diagnostic tools. Raw phone cache copies and temporary inspection tests were removed after verification.

## Outcome

- Signal: useful

## Source Nodes

- RealtimeSyncService
- CustomerBalanceStore
- SupplierBalanceStore
- CloudSnapshotGuard
- InvoiceFooterData